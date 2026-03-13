import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

@Suite("CoreDataEnsembleTests", .serialized)
@MainActor
struct CoreDataEnsembleTests {

    let rootDir: String
    let cloudDir: String
    let storeURL: URL
    let testModelURL: URL
    let testModel: NSManagedObjectModel
    let managedObjectContext: NSManagedObjectContext
    let mockFS: MockLocalCloudFileSystem
    let ensemble: CoreDataEnsemble

    init() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CoreDataEnsembleTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        self.rootDir = root

        let cloud = (root as NSString).appendingPathComponent("cloud")
        try FileManager.default.createDirectory(atPath: cloud, withIntermediateDirectories: true)
        self.cloudDir = cloud

        let fs = MockLocalCloudFileSystem(rootDirectory: cloud, identityToken: "first" as NSString)
        self.mockFS = fs

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        self.testModelURL = modelURL
        let model = TestModelCache.model(for: modelURL)!
        self.testModel = model

        let storePath = (root as NSString).appendingPathComponent("teststore.sqlite")
        let url = URL(fileURLWithPath: storePath)
        self.storeURL = url

        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let moc = NSManagedObjectContext(.mainQueue)
        moc.persistentStoreCoordinator = psc
        moc.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: moc)
            try! moc.save()
        }
        self.managedObjectContext = moc

        let eventDataRoot = (root as NSString).appendingPathComponent("eventStore")
        let ens = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: url,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: fs,
            localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot)
        )!
        self.ensemble = ens
    }

    // MARK: - Tests

    @Test("Initialization")
    func initialization() {
        #expect(ensemble.ensembleIdentifier == "testensemble")
    }

    @Test("Cannot share persistent store URL")
    func cannotSharePersistentStoreURL() {
        // Same ensemble ID, same store URL → should fail
        let e1 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS
        )
        #expect(e1 == nil)

        // Different ensemble ID, same store URL → should also fail
        let e2 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble1",
            persistentStoreURL: storeURL,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS
        )
        #expect(e2 == nil)

        // Different store URL → should succeed
        let otherPath = (rootDir as NSString).appendingPathComponent("teststore1.sqlite")
        let otherURL = URL(fileURLWithPath: otherPath)
        let e3 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble1",
            persistentStoreURL: otherURL,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS
        )
        #expect(e3 != nil)
        e3?.dismantle()
    }

    @Test("Dismantle frees store URL")
    func dismantle() {
        // Can't create with same URL while first ensemble exists
        let e1 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS
        )
        #expect(e1 == nil)

        // After dismantling, should be able to create
        ensemble.dismantle()

        let e2 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS
        )
        #expect(e2 != nil)
        e2?.dismantle()
    }

    @Test("Released ensemble gets dealloced")
    func releasedEnsembleGetsDealloced() async throws {
        ensemble.dismantle()

        weak var weakEnsemble: CoreDataEnsemble?
        do {
            let eventDataRoot = (rootDir as NSString).appendingPathComponent("eventStore2")
            let e = CoreDataEnsemble(
                ensembleIdentifier: "testensemble",
                persistentStoreURL: storeURL,
                persistentStoreOptions: nil,
                managedObjectModelURL: testModelURL,
                managedObjectModel: testModel,
                cloudFileSystem: mockFS,
                localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot)
            )!
            try await e.attachPersistentStore()
            try await e.sync()
            weakEnsemble = e
        }

        // Allow any pending operations to complete
        if let e = weakEnsemble {
            try await e.processPendingChanges()
        }

        // After the reference goes out of scope, ensemble should be deallocated
        // Note: in Swift, deallocation may be deferred, but the weak reference
        // will eventually become nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(weakEnsemble == nil)
    }

    @Test("Attach")
    func attach() async throws {
        #expect(!ensemble.isAttached)
        try await ensemble.attachPersistentStore()
        #expect(ensemble.isAttached)
    }

    @Test("Detach")
    func detach() async throws {
        try await ensemble.attachPersistentStore()
        try await ensemble.detachPersistentStore()
        #expect(!ensemble.isAttached)
    }

    @Test("Detach without attach")
    func detachWithoutAttach() async throws {
        await #expect(throws: (any Error).self) {
            try await ensemble.detachPersistentStore()
        }
    }

    @Test("Changing identity token causes detach")
    func changingIdentityTokenCausesDetach() async throws {
        let delegate = DetachTrackingDelegate()
        ensemble.delegate = delegate

        try await ensemble.attachPersistentStore()
        mockFS.identityToken = "second" as NSString

        // Merge triggers the identity check
        try? await ensemble.sync()

        try await Task.sleep(for: .milliseconds(500))
        #expect(delegate.detachOccurred)
    }

    @Test("Removing registration info causes detach")
    func removingRegistrationInfoCausesDetach() async throws {
        let delegate = DetachTrackingDelegate()
        ensemble.delegate = delegate

        try await ensemble.attachPersistentStore()

        // Remove the store registration file from cloud
        let storeId = ensemble.eventStore.persistentStoreIdentifier!
        let storesPath = (cloudDir as NSString).appendingPathComponent("testensemble/stores")
        let regPath = (storesPath as NSString).appendingPathComponent(storeId)
        try? FileManager.default.removeItem(atPath: regPath)

        // Merge should fail and trigger detach
        try? await ensemble.sync()

        try await Task.sleep(for: .milliseconds(500))
        #expect(delegate.detachOccurred)
    }

    @Test("Incomplete mandatory events cause detach")
    func incompleteMandatoryEventsCausesDetach() async throws {
        try await ensemble.attachPersistentStore()

        // Register an incomplete mandatory event
        ensemble.eventStore.registerIncompleteMandatoryEventIdentifier("123")

        try? await ensemble.processPendingChanges()

        // Dismantle and recreate
        ensemble.dismantle()

        let eventDataRoot = (rootDir as NSString).appendingPathComponent("eventStore")
        let newEnsemble = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: testModelURL,
            managedObjectModel: testModel,
            cloudFileSystem: mockFS,
            localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot)
        )!

        let delegate = DetachTrackingDelegate()
        newEnsemble.delegate = delegate

        try await Task.sleep(for: .milliseconds(500))
        #expect(delegate.detachOccurred)

        newEnsemble.dismantle()
    }

    @Test("Saving during attaching causes error")
    func savingDuringAttachingCausesError() async throws {
        nonisolated(unsafe) let moc = managedObjectContext
        let delegate = SaveDuringImportDelegate(context: moc)
        ensemble.delegate = delegate

        await #expect(throws: (any Error).self) {
            try await ensemble.attachPersistentStore()
        }
    }
}

// MARK: - Delegate Helpers

private final class DetachTrackingDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    var detachOccurred = false

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didDetachWithError error: Error) {
        detachOccurred = true
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {}
    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] { [] }
}

private final class SaveDuringImportDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func coreDataEnsembleWillImportStore(_ ensemble: CoreDataEnsemble) {
        context.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context)
            try! context.save()
        }
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {}
    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] { [] }
}
