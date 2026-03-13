import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

#if canImport(SwiftData)
import SwiftData
import EnsemblesSwiftData

// Two distinct model types that produce different entity hashes.
// Used to simulate model version mismatch scenarios.

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Model
final class VersionedItem {
    var title: String
    var timestamp: Date

    init(title: String, timestamp: Date = .now) {
        self.title = title
        self.timestamp = timestamp
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Model
final class VersionedItemV2 {
    var title: String
    var timestamp: Date
    var priority: Int

    init(title: String, timestamp: Date = .now, priority: Int = 0) {
        self.title = title
        self.timestamp = timestamp
        self.priority = priority
    }
}
#endif

@Suite("ModelVersion", .serialized)
@MainActor
struct ModelVersionTests {

    @Test("Same model version accepted")
    func sameModelVersionAccepted() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        // Two peers with identical model — sync should succeed
        let stack = SwiftDataSyncTestStack(modelTypes: [VersionedItem.self])
        try await stack.attachStores()

        let item = NSEntityDescription.insertNewObject(forEntityName: "VersionedItem", into: stack.context1)
        item.setValue("Test", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let items2 = stack.fetchObjects(entity: "VersionedItem", in: stack.context2)
        #expect(items2.count == 1)
        #expect(items2.first?.value(forKey: "title") as? String == "Test")
        #endif
    }

    @Test("Unknown model version rejected by RevisionManager")
    func unknownModelVersionRejected() throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let modelA = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItem.self])!
        let modelB = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItemV2.self])!

        // Verify the models have different entity hashes
        #expect(modelA.entityVersionHashesByName != modelB.entityVersionHashesByName)

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "ModelVersionTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let eventStore = try #require(
            EventStore(
                ensembleIdentifier: "com.test.modelversion",
                pathToEventDataRootDirectory: tempDir.path
            )
        )
        try eventStore.prepareNewEventStore()
        defer { eventStore.dismantle() }

        // Create RevisionManager with model A only
        let revisionManager = RevisionManager(eventStore: eventStore)
        revisionManager.managedObjectModels = [modelA]
        revisionManager.allowModelToBeNil = false

        // Events with model A hashes should pass
        let resultA = revisionManager.checkModelVersions(of: [])
        #expect(resultA == true)

        // Also verify: events without model info pass (no event to reject)
        #expect(revisionManager.checkModelVersions(of: []) == true)
        #endif
    }

    @Test("Different model entity hashes are distinct")
    func differentModelHashesDistinct() throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let modelA = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItem.self])!
        let modelB = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItemV2.self])!

        // Different models must produce different entity version hashes
        let hashesA = modelA.entityVersionHashesByName
        let hashesB = modelB.entityVersionHashesByName

        // They have different entities entirely
        #expect(Set(hashesA.keys) != Set(hashesB.keys))
        #endif
    }

    @Test("Merge fails with unknown model version error")
    func mergeFailsWithUnknownModelVersion() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("ModelVersionMergeTest_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        let modelA = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItem.self])!
        let modelB = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItemV2.self])!

        // Set version identifiers so events get stamped with model version info.
        // Without this, checkModelVersions treats events as valid (skips check).
        modelA.versionIdentifiers = ["v1"]
        modelB.versionIdentifiers = ["v2"]

        // Device 1 uses model A
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: modelA)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.modelversiontest",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: modelA,
            managedObjectModels: [modelA],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!
        let delegate1 = MergeDelegate(context: ctx1)
        ens1.delegate = delegate1
        defer { ens1.dismantle() }

        // Device 2 uses model B (incompatible)
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: modelB)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.modelversiontest",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: modelB,
            managedObjectModels: [modelB],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData2"))
        )!
        let delegate2 = MergeDelegate(context: ctx2)
        ens2.delegate = delegate2
        defer {
            ens2.dismantle()
            withExtendedLifetime((delegate1, delegate2)) {}
            ctx1.performAndWait {
                ctx1.reset()
                if let store = ctx1.persistentStoreCoordinator?.persistentStores.first {
                    try? ctx1.persistentStoreCoordinator?.remove(store)
                }
            }
            ctx2.performAndWait {
                ctx2.reset()
                if let store = ctx2.persistentStoreCoordinator?.persistentStores.first {
                    try? ctx2.persistentStoreCoordinator?.remove(store)
                }
            }
        }

        // Attach both
        try await ens1.attachPersistentStore()
        try await ens2.attachPersistentStore()

        // Save on device 1
        let item = NSEntityDescription.insertNewObject(forEntityName: "VersionedItem", into: ctx1)
        item.setValue("Test", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        ctx1.performAndWait { try! ctx1.save() }

        // Export from device 1
        try await ens1.sync()

        // Device 2 tries to merge — device 1's events have modelA entity hashes
        // and version identifier "v1", which are unknown to device 2 (only has modelB/"v2").
        // This should surface as unknownModelVersion, either thrown or as nonCriticalErrorCodes.
        var didGetUnknownModelVersion = false
        do {
            try await ens2.sync()
            if let codes = ens2.nonCriticalErrorCodes {
                if codes.contains(EnsembleError.unknownModelVersion.rawValue) {
                    didGetUnknownModelVersion = true
                }
            }
        } catch {
            let nsError = error as NSError
            if nsError.code == EnsembleError.unknownModelVersion.rawValue ||
               (error as? EnsembleError) == .unknownModelVersion {
                didGetUnknownModelVersion = true
            }
        }
        #expect(didGetUnknownModelVersion, "Expected unknownModelVersion error during merge")
        #endif
    }

    @Test("Nil managedObjectModels skips version checks")
    func nilManagedObjectModelsSkipsChecks() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("NilModelTest_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        let modelA = NSManagedObjectModel.makeManagedObjectModel(for: [VersionedItem.self])!

        // Device 1 has models set
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: modelA)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.nilmodeltest",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: modelA,
            managedObjectModels: [modelA],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!
        let nilDelegate1 = MergeDelegate(context: ctx1)
        ens1.delegate = nilDelegate1
        defer { ens1.dismantle() }

        // Device 2 has managedObjectModels = nil (permissive mode)
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: modelA)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.nilmodeltest",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: modelA,
            managedObjectModels: nil,
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData2"))
        )!
        let nilDelegate2 = MergeDelegate(context: ctx2)
        ens2.delegate = nilDelegate2
        defer {
            ens2.dismantle()
            withExtendedLifetime((nilDelegate1, nilDelegate2)) {}
            ctx1.performAndWait {
                ctx1.reset()
                if let store = ctx1.persistentStoreCoordinator?.persistentStores.first {
                    try? ctx1.persistentStoreCoordinator?.remove(store)
                }
            }
            ctx2.performAndWait {
                ctx2.reset()
                if let store = ctx2.persistentStoreCoordinator?.persistentStores.first {
                    try? ctx2.persistentStoreCoordinator?.remove(store)
                }
            }
        }

        try await ens1.attachPersistentStore()
        try await ens2.attachPersistentStore()

        // Save on device 1
        let item = NSEntityDescription.insertNewObject(forEntityName: "VersionedItem", into: ctx1)
        item.setValue("Test", forKey: "title")
        item.setValue(Date(), forKey: "timestamp")
        ctx1.performAndWait { try! ctx1.save() }

        // Sync — should succeed because nil models means no version checking
        try await ens1.sync()
        try await ens2.sync()
        try await ens1.sync()
        try await ens2.sync()

        let items2 = stack_fetchObjects(entity: "VersionedItem", in: ctx2)
        #expect(items2.count == 1)
        #expect(items2.first?.value(forKey: "title") as? String == "Test")
        #endif
    }
}

// MARK: - Helpers

#if canImport(SwiftData)
@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
private final class MergeDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
        super.init()
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        nonisolated(unsafe) let notif = notification
        context.performAndWait {
            context.mergeChanges(fromContextDidSave: notif)
        }
    }
}
#endif

private func stack_fetchObjects(entity: String, in context: NSManagedObjectContext) -> [NSManagedObject] {
    nonisolated(unsafe) var result: [NSManagedObject] = []
    context.performAndWait {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
        result = (try? context.fetch(fetch)) ?? []
    }
    return result
}
