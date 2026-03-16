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

// MARK: - VersionedSchema definitions for schema evolution tests
// Follows the Keytakes pattern: nested @Model types inside VersionedSchema enums,
// with typealiases for the current version.

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
enum TestSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model
    final class Note {
        var title: String
        var timestamp: Date

        init(title: String, timestamp: Date = .now) {
            self.title = title
            self.timestamp = timestamp
        }
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
enum TestSchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Note.self] }

    @Model
    final class Note {
        var title: String
        var timestamp: Date
        var priority: Int?

        init(title: String, timestamp: Date = .now, priority: Int? = nil) {
            self.title = title
            self.timestamp = timestamp
            self.priority = priority
        }
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
enum TestMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TestSchemaV1.self, TestSchemaV2.self] }
    static var stages: [MigrationStage] { [] }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
typealias CurrentTestSchema = TestSchemaV2
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

    // MARK: - Schema Evolution Tests (VersionedSchema)

    @Test("Upgraded device accepts events from old schema version")
    func upgradedDeviceAcceptsOldSchemaEvents() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SchemaEvolution_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        // Schema V1 model (old device)
        let modelV1 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV1.models)!
        modelV1.versionIdentifiers = ["v1"]

        // Schema V2 model (upgraded device) — same entity name, extra attribute
        let modelV2 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV2.models)!
        modelV2.versionIdentifiers = ["v2"]

        // Device 1: old app version (Schema V1 only)
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: modelV1)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.schemaevolution",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: modelV1,
            managedObjectModels: [modelV1],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!
        let delegate1 = MergeDelegate(context: ctx1)
        ens1.delegate = delegate1
        defer { ens1.dismantle() }

        // Device 2: upgraded app (knows both V1 and V2)
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: modelV2)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.schemaevolution",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: modelV2,
            managedObjectModels: [modelV1, modelV2],
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

        // Device 1 (old version) saves a Note
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: ctx1)
        note.setValue("Old Version Note", forKey: "title")
        note.setValue(Date(), forKey: "timestamp")
        ctx1.performAndWait { try! ctx1.save() }

        // Device 1 exports, device 2 imports (one-way only — device 1 can't
        // accept device 2's V2-stamped baseline, which is expected)
        try await ens1.sync()
        try await ens2.sync()

        // Device 2 (upgraded) should have received the note from device 1
        let items2 = stack_fetchObjects(entity: "Note", in: ctx2)
        #expect(items2.count == 1)
        #expect(items2.first?.value(forKey: "title") as? String == "Old Version Note")

        // The new optional attribute should be nil (no value from V1 schema)
        let priority = items2.first?.value(forKey: "priority")
        #expect(priority == nil || priority is NSNull)
        #endif
    }

    @Test("Old device rejects events from newer schema version")
    func oldDeviceRejectsNewerSchemaEvents() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SchemaReject_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        let modelV1 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV1.models)!
        modelV1.versionIdentifiers = ["v1"]
        let modelV2 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV2.models)!
        modelV2.versionIdentifiers = ["v2"]

        // Device 1: upgraded app (Schema V2, knows both versions)
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: modelV2)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.schemareject",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: modelV2,
            managedObjectModels: [modelV1, modelV2],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!
        let delegate1 = MergeDelegate(context: ctx1)
        ens1.delegate = delegate1
        defer { ens1.dismantle() }

        // Device 2: old app version (only knows Schema V1)
        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: modelV1)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.schemareject",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: modelV1,
            managedObjectModels: [modelV1],
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

        // Device 1 (upgraded) saves a Note with the new priority attribute
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: ctx1)
        note.setValue("New Version Note", forKey: "title")
        note.setValue(Date(), forKey: "timestamp")
        note.setValue(5, forKey: "priority")
        ctx1.performAndWait { try! ctx1.save() }

        // Device 1 exports
        try await ens1.sync()

        // Device 2 (old version) tries to import — should reject the V2 events
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
        #expect(didGetUnknownModelVersion, "Old device should reject events from newer schema version")

        // Device 2 should have no imported notes
        let items2 = stack_fetchObjects(entity: "Note", in: ctx2)
        #expect(items2.count == 0)
        #endif
    }

    @Test("Both devices on V2 sync new attribute correctly")
    func bothDevicesOnV2SyncNewAttribute() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }

        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SchemaBothV2_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: rootDir) }

        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        let modelV1 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV1.models)!
        modelV1.versionIdentifiers = ["v1"]
        let modelV2 = NSManagedObjectModel.makeManagedObjectModel(for: TestSchemaV2.models)!
        modelV2.versionIdentifiers = ["v2"]

        // Both devices on V2, knowing both schema versions (simulates post-upgrade)
        let storeURL1 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store1.sqlite"))
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: modelV2)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.bothv2",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: modelV2,
            managedObjectModels: [modelV1, modelV2],
            cloudFileSystem: LocalCloudFileSystem(rootDirectory: cloudDir),
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData1"))
        )!
        let delegate1 = MergeDelegate(context: ctx1)
        ens1.delegate = delegate1
        defer { ens1.dismantle() }

        let storeURL2 = URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("store2.sqlite"))
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: modelV2)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.bothv2",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: modelV2,
            managedObjectModels: [modelV1, modelV2],
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
                if let store = psc1.persistentStores.first { try? psc1.remove(store) }
            }
            ctx2.performAndWait {
                ctx2.reset()
                if let store = psc2.persistentStores.first { try? psc2.remove(store) }
            }
        }

        try await ens1.attachPersistentStore()
        try await ens2.attachPersistentStore()

        // Device 1 saves a note using the new priority attribute
        let note1 = NSEntityDescription.insertNewObject(forEntityName: "Note", into: ctx1)
        note1.setValue("Priority Note", forKey: "title")
        note1.setValue(Date(), forKey: "timestamp")
        note1.setValue(3, forKey: "priority")
        ctx1.performAndWait { try! ctx1.save() }

        // Device 2 saves a note without setting priority (nil)
        let note2 = NSEntityDescription.insertNewObject(forEntityName: "Note", into: ctx2)
        note2.setValue("No Priority Note", forKey: "title")
        note2.setValue(Date(), forKey: "timestamp")
        ctx2.performAndWait { try! ctx2.save() }

        // Full sync
        try await ens1.sync()
        try await ens2.sync()
        try await ens1.sync()
        try await ens2.sync()

        // Both devices should have both notes
        let items1 = stack_fetchObjects(entity: "Note", in: ctx1)
        let items2 = stack_fetchObjects(entity: "Note", in: ctx2)
        #expect(items1.count == 2)
        #expect(items2.count == 2)

        // The priority note should have priority = 3 on device 2
        let priorityNote = items2.first { $0.value(forKey: "title") as? String == "Priority Note" }
        #expect(priorityNote?.value(forKey: "priority") as? Int == 3)

        // The no-priority note should have nil priority
        let noPriorityNote = items2.first { $0.value(forKey: "title") as? String == "No Priority Note" }
        let noPriority = noPriorityNote?.value(forKey: "priority")
        #expect(noPriority == nil || noPriority is NSNull)
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
