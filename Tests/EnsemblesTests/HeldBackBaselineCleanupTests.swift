import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// A follower that has imported a baseline but cannot adopt it yet (the baseline is
// held at `.baselineMissingDependencies` because a data file it references has not
// arrived) must treat that baseline as PRESENT. Before 3.0.11 the cloud cleanup and
// the retrieval list matched local baselines of type `.baseline` only, so a held-back
// baseline was invisible: the follower deleted the source's baseline files from the
// cloud at the end of a sync that reported success, and stayed empty until the source
// happened to sync again. The same logic is in Ensembles 2.

private let heldBackEnsembleID = "com.ensembles.heldbackbaseline"

/// One simulated device: its own SQLite store, context, event data directory and
/// ensemble, sharing a `MemoryCloudFileSystem` with the other devices.
private final class HeldBackDevice: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    let label: String
    let rootDir: String
    let storeURL: URL
    let eventDataRoot: String
    let context: NSManagedObjectContext
    let ensemble: CoreDataEnsemble

    init(label: String, cloud: MemoryCloudFileSystem) {
        self.label = label
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDEHeldBack_\(label)_\(ProcessInfo.processInfo.globallyUniqueString)")
        try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        self.rootDir = root
        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!
        let url = URL(fileURLWithPath: (root as NSString).appendingPathComponent("store.sql"))
        self.storeURL = url
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.persistentStoreCoordinator = psc
        ctx.stalenessInterval = 0
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        self.context = ctx
        let edRoot = (root as NSString).appendingPathComponent("eventData")
        self.eventDataRoot = edRoot
        self.ensemble = CoreDataEnsemble(
            ensembleIdentifier: heldBackEnsembleID,
            persistentStoreURL: url,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloud,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot)
        )!
        super.init()
        ensemble.delegate = self
    }

    /// Simulates the app's "local reset": tears down the ensemble and deletes the
    /// persistent store AND the event data directory.
    func destroy() {
        ensemble.dismantle()
        context.performAndWait {
            context.reset()
            if let store = context.persistentStoreCoordinator?.persistentStores.first {
                try? context.persistentStoreCoordinator?.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: rootDir)
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        nonisolated(unsafe) let notif = notification
        context.performAndWait { context.mergeChanges(fromContextDidSave: notif) }
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String] {
        objects.map { obj in
            if obj.entity.attributesByName["name"] != nil, let name = obj.value(forKey: "name") as? String, !name.isEmpty {
                return name
            }
            return obj.objectID.uriRepresentation().absoluteString
        }
    }

    func count(_ entity: String) -> Int {
        nonisolated(unsafe) var n = 0
        context.performAndWait {
            context.reset()
            n = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? -1
        }
        return n
    }

    func parentsWithData() -> Int {
        nonisolated(unsafe) var n = 0
        context.performAndWait {
            context.reset()
            let parents = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Parent"))) ?? []
            n = parents.filter { ($0.value(forKey: "data") as? Data)?.count ?? 0 > 10000 }.count
        }
        return n
    }

    /// Source content: ten Parents each with a DISTINCT >10000 byte blob (ten
    /// external data files) plus 60 BatchParents. BatchParent has
    /// CDEMigrationBatchSizeKey=50 in the test model, so the exported baseline
    /// splits into two parts.
    func insertSourceContent() {
        context.performAndWait {
            for i in 0..<10 {
                let p = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context)
                p.setValue("parent\(i)", forKey: "name")
                var bytes = Data(count: 10500)
                bytes[0] = UInt8(i + 1)
                bytes[10499] = UInt8(i + 1)
                p.setValue(bytes, forKey: "data")
            }
            for i in 0..<60 {
                let b = NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: context)
                if b.entity.attributesByName["name"] != nil { b.setValue("batch\(i)", forKey: "name") }
            }
            try! context.save()
        }
    }

    /// Gives every Parent a new blob, so none of the original data files is referenced.
    func replaceAllParentData() {
        context.performAndWait {
            let parents = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Parent"))) ?? []
            for (i, p) in parents.enumerated() {
                var bytes = Data(count: 10600)
                bytes[0] = UInt8(100 + i)
                bytes[10599] = UInt8(100 + i)
                p.setValue(bytes, forKey: "data")
            }
            try! context.save()
        }
    }

    /// All event rows, in id order. `moment` only labels a failure.
    func dumpEventStore(_ moment: String) -> [StoreModificationEvent] {
        ((try? ensemble.eventStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)) ?? []).sorted { $0.id < $1.id }
    }
}

private func cloudListing(_ cloud: MemoryCloudFileSystem, _ dir: String) async -> [String] {
    let items = (try? await cloud.contentsOfDirectory(atPath: "/\(heldBackEnsembleID)/\(dir)")) ?? []
    return items.map(\.name).sorted()
}


extension SyncTests {
@Suite("HeldBackBaselineCleanup", .serialized)
@MainActor
struct HeldBackBaselineCleanupTests {

    /// Source A publishes a two-part baseline and ten data files. Returns the baseline
    /// filenames, and the name and saved contents of one data file removed from the cloud.
    private func publishSourceAndWithholdOneDataFile(_ a: HeldBackDevice, cloud: MemoryCloudFileSystem) async throws -> (baselineFiles: [String], withheldName: String, withheldCopy: String) {
        a.insertSourceContent()
        try await a.ensemble.attachPersistentStore()
        try await a.ensemble.sync()
        let baselineFiles = await cloudListing(cloud, "baselines")
        let dataFiles = await cloudListing(cloud, "data")
        try #require(baselineFiles.count == 2, "expected a two-part baseline from the source")
        try #require(dataFiles.count == 10)

        let withheld = dataFiles[0]
        let copy = (a.rootDir as NSString).appendingPathComponent("withheld-\(withheld)")
        try await cloud.downloadFile(atPath: "/\(heldBackEnsembleID)/data/\(withheld)", toLocalFile: copy)
        try await cloud.removeItem(atPath: "/\(heldBackEnsembleID)/data/\(withheld)")
        return (baselineFiles, withheld, copy)
    }

    @Test("A held-back baseline is not deleted from the cloud, and is adopted once its data file arrives", arguments: [SeedPolicy.mergeAllData, .excludeLocalData])
    func heldBackBaselineSurvivesCleanup(followerPolicy: SeedPolicy) async throws {
        let cloud = MemoryCloudFileSystem()
        let a = HeldBackDevice(label: "A", cloud: cloud)
        defer { a.destroy() }
        let source = try await publishSourceAndWithholdOneDataFile(a, cloud: cloud)

        let b = HeldBackDevice(label: "B", cloud: cloud)
        defer { b.destroy() }
        try await b.ensemble.attachPersistentStore(seedPolicy: followerPolicy)

        // Several syncs while the data file is missing. Each succeeds, none may remove
        // the source's baseline, and the held-back baseline must not be imported again.
        for pass in 1...3 {
            try await b.ensemble.sync()
            let listed = Set(await cloudListing(cloud, "baselines"))
            #expect(listed.isSuperset(of: source.baselineFiles), "sync \(pass) removed the source's baseline from the cloud")

            let events = b.dumpEventStore("pass \(pass)")
            let heldBack = events.filter { $0.type == .baselineMissingDependencies }
            #expect(heldBack.count == 1, "expected exactly one held-back baseline after sync \(pass), found \(heldBack.count)")
            #expect(b.count("Parent") == 0)
            #expect(b.ensemble.nonCriticalErrorCodes?.contains(EnsembleError.missingDataFiles.rawValue) == true, "a held-back baseline must be reported, not silent (sync \(pass))")
        }

        // The data file arrives, WITHOUT the source syncing again.
        try await cloud.uploadLocalFile(atPath: source.withheldCopy, toPath: "/\(heldBackEnsembleID)/data/\(source.withheldName)")
        try await b.ensemble.sync()

        #expect(b.count("Parent") == 10)
        #expect(b.parentsWithData() == 10)
        #expect(b.count("BatchParent") == 60)
        let finalEvents = b.dumpEventStore("after data file arrived")
        #expect(finalEvents.filter { $0.type == .baselineMissingDependencies }.isEmpty)

        // And the source is unharmed by whatever the follower published.
        try await a.ensemble.sync()
        #expect(a.count("Parent") == 10)
        #expect(a.parentsWithData() == 10)
        #expect(a.count("BatchParent") == 60)
    }

    /// The data file never arrives: the source moves on, rebases, and its new baseline
    /// no longer references the file. The follower must adopt the new baseline and drop
    /// the old held-back one, not report it as missing data files for ever after.
    @Test("A held-back baseline that has been superseded is dropped, and stops being reported")
    func supersededHeldBackBaselineIsDropped() async throws {
        let cloud = MemoryCloudFileSystem()
        let a = HeldBackDevice(label: "A", cloud: cloud)
        defer { a.destroy() }
        _ = try await publishSourceAndWithholdOneDataFile(a, cloud: cloud)

        let b = HeldBackDevice(label: "B", cloud: cloud)
        defer { b.destroy() }
        try await b.ensemble.attachPersistentStore()
        try await b.ensemble.sync()
        try #require(b.dumpEventStore("held back").filter { $0.type == .baselineMissingDependencies }.count == 1)

        a.replaceAllParentData()
        try await a.ensemble.sync(options: .forceRebase)

        for pass in 1...2 {
            try await b.ensemble.sync()
            let heldBack = b.dumpEventStore("pass \(pass)").filter { $0.type == .baselineMissingDependencies }
            #expect(heldBack.isEmpty, "superseded held-back baseline still present after sync \(pass)")
            #expect(b.ensemble.nonCriticalErrorCodes?.contains(EnsembleError.missingDataFiles.rawValue) != true, "210 still reported after sync \(pass)")
        }
        #expect(b.count("Parent") == 10)
        #expect(b.parentsWithData() == 10)
        #expect(b.count("BatchParent") == 60)
    }
}
}
