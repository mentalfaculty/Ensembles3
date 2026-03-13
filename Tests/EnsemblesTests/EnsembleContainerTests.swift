import Foundation
import Testing
@_spi(Testing) import Ensembles
import EnsemblesMemory
import CoreData

@Suite("EnsembleContainerTests", .serialized)
@MainActor
struct EnsembleContainerTests {

    // MARK: - Helpers

    struct TestFixture: @unchecked Sendable {
        let rootDir: URL
        let storeURL: URL
        let cloudFS: MemoryCloudFileSystem
        let model: NSManagedObjectModel
        let modelURL: URL

        init() {
            let root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ContainerTest_\(ProcessInfo.processInfo.globallyUniqueString)")
            try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.rootDir = root
            self.storeURL = root.appendingPathComponent("store.sqlite")
            self.cloudFS = MemoryCloudFileSystem()
            self.modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
            self.model = NSManagedObjectModel(contentsOf: modelURL)!
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: rootDir)
        }
    }

    // MARK: - Configuration Tests

    @Test("AutoSyncPolicy OptionSet basics")
    func autoSyncPolicyBasics() {
        let all: AutoSyncPolicy = .all
        #expect(all.contains(.onSave))
        #expect(all.contains(.onActivation))
        #expect(all.contains(.onTimer))

        let manual: AutoSyncPolicy = .manual
        #expect(!manual.contains(.onSave))
        #expect(!manual.contains(.onActivation))
        #expect(!manual.contains(.onTimer))

        let saveAndTimer: AutoSyncPolicy = [.onSave, .onTimer]
        #expect(saveAndTimer.contains(.onSave))
        #expect(saveAndTimer.contains(.onTimer))
        #expect(!saveAndTimer.contains(.onActivation))
    }

    @Test("EnsembleContainerConfiguration defaults")
    func configurationDefaults() {
        let config = EnsembleContainerConfiguration()
        #expect(config.autoSyncPolicy == .all)
        #expect(config.timerInterval == 60)
        #expect(config.seedPolicy == .mergeAllData)
        #expect(config.compatibilityMode == .ensembles3)
        #expect(config.persistentStoreOptions == nil)
        #expect(config.localDataRootDirectoryURL == nil)
    }

    // MARK: - CompatibilityMode Tests

    @Test("CompatibilityMode enforces compressModelHashes")
    func compatibilityModeEnforcesCompressModelHashes() {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            compatibilityMode: .ensembles2Compatible,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "CompatTest",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container")
            return
        }

        #expect(container.ensemble.compatibilityMode == .ensembles2Compatible)
        #expect(container.ensemble.compressModelHashes == false)

        // Setting compressModelHashes to true then setting compatibility mode back should force false
        container.ensemble.compressModelHashes = true
        container.ensemble.compatibilityMode = .ensembles2Compatible
        #expect(container.ensemble.compressModelHashes == false)

        container.ensemble.dismantle()
    }

    // MARK: - Init Tests

    @Test("Init from model URL")
    func initFromModelURL() {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "TestEnsemble",
            storeURL: fixture.storeURL,
            modelURL: fixture.modelURL,
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container from model URL")
            return
        }

        #expect(container.viewContext.persistentStoreCoordinator != nil)
        #expect(!container.isAttached)
        #expect(container.currentActivity == .none)

        container.ensemble.dismantle()
    }

    @Test("Init from model object")
    func initFromModel() {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "TestEnsemble",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container from model")
            return
        }

        #expect(container.viewContext.persistentStoreCoordinator != nil)
        #expect(!container.isAttached)

        container.ensemble.dismantle()
    }

    @Test("Init from NSPersistentContainer")
    func initFromPersistentContainer() {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let persistentContainer = NSPersistentContainer(name: "TestContainer", managedObjectModel: fixture.model)
        let description = NSPersistentStoreDescription(url: fixture.storeURL)
        persistentContainer.persistentStoreDescriptions = [description]
        persistentContainer.loadPersistentStores { _, _ in }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            persistentContainer: persistentContainer,
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container from NSPersistentContainer")
            return
        }

        #expect(container.viewContext === persistentContainer.viewContext)
        #expect(!container.isAttached)

        container.ensemble.dismantle()
    }

    @Test("Init from existing context")
    func initFromExistingContext() {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: fixture.model)
        _ = try! coordinator.addPersistentStore(type: .sqlite, at: fixture.storeURL, options: nil)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "TestEnsemble",
            viewContext: context,
            persistentStoreURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container from existing context")
            return
        }

        #expect(container.viewContext === context)
        #expect(!container.isAttached)

        container.ensemble.dismantle()
    }

    // MARK: - Sync Tests

    @Test("Sync attaches and merges")
    func syncAttachesAndMerges() async {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "SyncTest",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container")
            return
        }

        #expect(!container.isAttached)

        let success = await container.sync()
        #expect(success)
        #expect(container.isAttached)

        container.ensemble.dismantle()
    }

    @Test("Detach after attach")
    func detachAfterAttach() async throws {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "DetachTest",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container")
            return
        }

        await container.sync()
        #expect(container.isAttached)

        try await container.detach()
        #expect(!container.isAttached)

        container.ensemble.dismantle()
    }

    @Test("Global identifiers closure is invoked")
    func globalIdentifiersCallback() async {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "IDTest",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container")
            return
        }

        nonisolated(unsafe) var callbackInvoked = false
        container.globalIdentifiers = { objects in
            callbackInvoked = true
            return objects.map { _ in nil }
        }

        // Insert an object and save before attaching
        nonisolated(unsafe) let model = fixture.model
        container.viewContext.performAndWait {
            let entity = model.entitiesByName["Parent"]!
            let obj = NSManagedObject(entity: entity, insertInto: container.viewContext)
            obj.setValue("test", forKey: "name")
            try? container.viewContext.save()
        }

        await container.sync()
        #expect(callbackInvoked)

        container.ensemble.dismantle()
    }

    @Test("Seed policy is passed through")
    func seedPolicyPassedThrough() async {
        let fixture = TestFixture()
        defer { fixture.cleanup() }

        let config = EnsembleContainerConfiguration(
            autoSyncPolicy: .manual,
            seedPolicy: .excludeLocalData,
            localDataRootDirectoryURL: fixture.rootDir
        )
        guard let container = CoreDataEnsembleContainer(
            name: "SeedTest",
            storeURL: fixture.storeURL,
            managedObjectModel: fixture.model,
            managedObjectModels: [fixture.model],
            cloudFileSystem: fixture.cloudFS,
            configuration: config
        ) else {
            Issue.record("Failed to create container")
            return
        }

        // Insert data before attaching
        nonisolated(unsafe) let model = fixture.model
        container.viewContext.performAndWait {
            let entity = model.entitiesByName["Parent"]!
            let obj = NSManagedObject(entity: entity, insertInto: container.viewContext)
            obj.setValue("test", forKey: "name")
            try? container.viewContext.save()
        }

        // Sync with excludeLocalData — the data should not be exported
        let success = await container.sync()
        #expect(success)

        container.ensemble.dismantle()
    }
}
