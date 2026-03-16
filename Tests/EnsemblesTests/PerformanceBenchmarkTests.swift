import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile
import Darwin.Mach

// MARK: - Measurement Helpers

private struct Measurement {
    let label: String
    let durationMs: Double
    let memoryDeltaKB: Int64
}

private func currentMemoryKB() -> Int64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Int64(info.resident_size) / 1024
}

@MainActor private func measure(_ label: String, body: @MainActor () async throws -> Void) async throws -> Measurement {
    let memBefore = currentMemoryKB()
    let start = ContinuousClock.now
    try await body()
    let elapsed = start.duration(to: .now)
    let memAfter = currentMemoryKB()
    let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
    return Measurement(label: label, durationMs: ms, memoryDeltaKB: memAfter - memBefore)
}

private func fileSize(atPath path: String) -> Int64 {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
    var total: Int64 = 0
    while let file = enumerator.nextObject() as? String {
        let full = (path as NSString).appendingPathComponent(file)
        if let attrs = try? fm.attributesOfItem(atPath: full),
           let size = attrs[.size] as? Int64 {
            total += size
        }
    }
    return total
}

private func pad(_ string: String, _ width: Int) -> String {
    if string.count >= width { return string }
    return string + String(repeating: " ", count: width - string.count)
}

private func formatBytes(_ bytes: Int64) -> String {
    if bytes < 1024 { return "\(bytes) B" }
    let kb = Double(bytes) / 1024
    if kb < 1024 { return String(format: "%.1f KB", kb) }
    let mb = kb / 1024
    return String(format: "%.2f MB", mb)
}

// MARK: - Benchmark Suite

@Suite("PerformanceBenchmark", .serialized)
@MainActor
struct PerformanceBenchmarkTests {

    @Test("Full sync performance benchmark")
    func fullBenchmark() async throws {
        var measurements: [Measurement] = []
        var sizeSnapshots: [(label: String, device1: Int64, device2: Int64, cloud: Int64)] = []

        // --- Setup ---
        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("PerfBench_\(ProcessInfo.processInfo.globallyUniqueString)")
        let fm = FileManager.default
        try fm.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: rootDir) }

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloud")
        try fm.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        // Device 1
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let edRoot1 = (rootDir as NSString).appendingPathComponent("eventData1")
        let cloudFS1 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.perfbench",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS1,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot1)
        )!

        // Delegate bridge for device 1
        let delegate = BenchmarkDelegate()
        delegate.context1 = ctx1
        delegate.ensemble1 = ens1
        ens1.delegate = delegate

        // --- 1. Attach ---
        let attachM = try await measure("1. Attach (empty store)") {
            try await ens1.attachPersistentStore()
        }
        measurements.append(attachM)

        // --- 2. Insert 500 Parents x 3 Children = 2000 objects, then sync ---
        var saveM: Measurement!
        let insertSyncM = try await measure("2. Insert 2000 objects + first sync (total)") {
            saveM = try await measure("2a. Save 2000 objects") {
                ctx1.performAndWait {
                    for i in 0..<500 {
                        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: ctx1)
                        parent.setValue("parent_\(i)", forKey: "name")
                        parent.setValue(Date(), forKey: "date")
                        for j in 0..<3 {
                            let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: ctx1)
                            child.setValue("child_\(i)_\(j)", forKey: "name")
                            child.setValue(parent, forKey: "parent")
                        }
                    }
                    try! ctx1.save()
                }
            }

            _ = try await measure("_sync") {
                try await ens1.sync()
            }
        }
        measurements.append(saveM)
        let firstSyncM = Measurement(
            label: "2b. First sync (export 2000 objects)",
            durationMs: insertSyncM.durationMs - saveM.durationMs,
            memoryDeltaKB: insertSyncM.memoryDeltaKB - saveM.memoryDeltaKB
        )
        measurements.append(firstSyncM)

        sizeSnapshots.append((
            label: "After insert + first sync",
            device1: fileSize(atPath: edRoot1),
            device2: 0,
            cloud: fileSize(atPath: cloudDir)
        ))

        // --- 3. Two-device import sync ---
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let edRoot2 = (rootDir as NSString).appendingPathComponent("eventData2")
        let cloudFS2 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.perfbench",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS2,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot2)
        )!

        let delegate2 = BenchmarkDelegate()
        delegate2.context1 = ctx2
        delegate2.ensemble1 = ens2
        ens2.delegate = delegate2

        let device2ImportM = try await measure("3. Device 2 attach + import sync") {
            try await ens2.attachPersistentStore()
            try await ens2.sync()
        }
        measurements.append(device2ImportM)

        // Verify import
        let importedParents: Int = ctx2.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            return (try? ctx2.fetch(fetch))?.count ?? 0
        }
        let importedChildren: Int = ctx2.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
            return (try? ctx2.fetch(fetch))?.count ?? 0
        }

        sizeSnapshots.append((
            label: "After device 2 import",
            device1: fileSize(atPath: edRoot1),
            device2: fileSize(atPath: edRoot2),
            cloud: fileSize(atPath: cloudDir)
        ))

        // --- 4. Incremental sync: device 2 inserts 50 Parents + 150 Children ---
        let dev2SaveM = try await measure("4a. Device 2 save 200 objects") {
            ctx2.performAndWait {
                for i in 0..<50 {
                    let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: ctx2)
                    parent.setValue("dev2_parent_\(i)", forKey: "name")
                    parent.setValue(Date(), forKey: "date")
                    for j in 0..<3 {
                        let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: ctx2)
                        child.setValue("dev2_child_\(i)_\(j)", forKey: "name")
                        child.setValue(parent, forKey: "parent")
                    }
                }
                try! ctx2.save()
            }
        }
        measurements.append(dev2SaveM)

        let dev2SyncM = try await measure("4b. Device 2 sync (export)") {
            try await ens2.sync()
        }
        measurements.append(dev2SyncM)

        let dev1SyncM = try await measure("4c. Device 1 sync (import incremental)") {
            try await ens1.sync()
        }
        measurements.append(dev1SyncM)

        sizeSnapshots.append((
            label: "After incremental sync",
            device1: fileSize(atPath: edRoot1),
            device2: fileSize(atPath: edRoot2),
            cloud: fileSize(atPath: cloudDir)
        ))

        // --- 5. Rebase ---
        let rebaseM = try await measure("5. Rebase (device 1)") {
            try await ens1.sync(options: .forceRebase)
        }
        measurements.append(rebaseM)

        // Sync device 2 after rebase
        let postRebaseSyncM = try await measure("5b. Device 2 sync after rebase") {
            try await ens2.sync()
        }
        measurements.append(postRebaseSyncM)

        sizeSnapshots.append((
            label: "After rebase",
            device1: fileSize(atPath: edRoot1),
            device2: fileSize(atPath: edRoot2),
            cloud: fileSize(atPath: cloudDir)
        ))

        // --- Cleanup ensembles ---
        ens1.dismantle()
        ens2.dismantle()

        // --- Print Results ---
        print("\n" + String(repeating: "=", count: 80))
        print("ENSEMBLES 3 PERFORMANCE BENCHMARK")
        print(String(repeating: "=", count: 80))
        print("")
        print(pad("Operation", 50) + pad("Time (ms)", 12) + pad("Mem (KB)", 12))
        print(String(repeating: "-", count: 74))
        for m in measurements {
            let timeStr = String(format: "%.1f", m.durationMs)
            let memStr = "\(m.memoryDeltaKB)"
            print(pad(m.label, 50) + pad(timeStr, 12) + pad(memStr, 12))
        }
        print(String(repeating: "-", count: 74))

        print("")
        print("OBJECT COUNTS")
        print(String(repeating: "-", count: 40))
        print("  Device 2 imported: \(importedParents) parents, \(importedChildren) children")

        print("")
        print(pad("Stage", 36) + pad("Device 1", 14) + pad("Device 2", 14) + pad("Cloud", 14))
        print(String(repeating: "-", count: 78))
        for s in sizeSnapshots {
            let d2 = s.device2 > 0 ? formatBytes(s.device2) : "-"
            print(pad(s.label, 36) + pad(formatBytes(s.device1), 14) + pad(d2, 14) + pad(formatBytes(s.cloud), 14))
        }
        print(String(repeating: "=", count: 80))
        print("")
    }
}

// MARK: - Benchmark Delegate

private final class BenchmarkDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    var context1: NSManagedObjectContext!
    var ensemble1: CoreDataEnsemble!

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        nonisolated(unsafe) let notif = notification
        context1.performAndWait {
            context1.mergeChanges(fromContextDidSave: notif)
        }
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] {
        []
    }
}
