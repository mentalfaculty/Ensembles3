import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

/// Two-peer sync test harness with two `CoreDataEnsemble` instances
/// sharing a single `LocalCloudFileSystem`. Mirrors the ObjC `CDESyncTest` base class.
final class SyncTestStack: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {

    let context1: NSManagedObjectContext
    let context2: NSManagedObjectContext
    let model1: NSManagedObjectModel
    let model2: NSManagedObjectModel
    let ensemble1: CoreDataEnsemble
    let ensemble2: CoreDataEnsemble

    let testRootDirectory: String
    let cloudRootDir: String
    let eventDataRoot1: String
    let eventDataRoot2: String
    let testStoreURL1: URL
    let testStoreURL2: URL

    let testModelURL: URL

    // Delegate customization hooks
    var globalIdentifiersBlock: (([NSManagedObject]) -> [String?])?
    var shouldSaveBlock: ((CoreDataEnsemble, NSManagedObjectContext, NSManagedObjectContext) -> Void)?
    var shouldFailMerge = false

    override init() {
        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDESyncTest_\(ProcessInfo.processInfo.globallyUniqueString)")
        try! FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        self.testRootDirectory = rootDir

        // Test model
        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        self.testModelURL = modelURL

        // First store
        let storeFile1 = (rootDir as NSString).appendingPathComponent("store1.sql")
        let storeURL1 = URL(fileURLWithPath: storeFile1)
        self.testStoreURL1 = storeURL1

        let m1 = TestModelCache.model(for: modelURL)!
        self.model1 = m1
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: m1)
        try! psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)

        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.stalenessInterval = 0.0
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        self.context1 = ctx1

        // Cloud
        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try! FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)
        self.cloudRootDir = cloudDir

        let cloudFS1 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let edRoot1 = (rootDir as NSString).appendingPathComponent("eventData1")
        self.eventDataRoot1 = edRoot1

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.synctest",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: m1,
            cloudFileSystem: cloudFS1,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot1)
        )!
        self.ensemble1 = ens1

        // Second store
        let storeFile2 = (rootDir as NSString).appendingPathComponent("store2.sql")
        let storeURL2 = URL(fileURLWithPath: storeFile2)
        self.testStoreURL2 = storeURL2

        let m2 = m1  // Use same model instance for both ensembles
        self.model2 = m2
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: m2)
        try! psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)

        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.stalenessInterval = 0.0
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        self.context2 = ctx2

        let cloudFS2 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let edRoot2 = (rootDir as NSString).appendingPathComponent("eventData2")
        self.eventDataRoot2 = edRoot2

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.synctest",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: m2,
            cloudFileSystem: cloudFS2,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot2)
        )!
        self.ensemble2 = ens2

        super.init()

        ens1.delegate = self
        ens2.delegate = self
    }

    deinit {
        ensemble1.dismantle()
        ensemble2.dismantle()
        context1.performAndWait {
            context1.reset()
            if let store = context1.persistentStoreCoordinator?.persistentStores.first {
                try? context1.persistentStoreCoordinator?.remove(store)
            }
        }
        context2.performAndWait {
            context2.reset()
            if let store = context2.persistentStoreCoordinator?.persistentStores.first {
                try? context2.persistentStoreCoordinator?.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: testRootDirectory)
    }

    // MARK: - Delegate

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        nonisolated(unsafe) let notif = notification
        if ensemble === ensemble1 {
            context1.performAndWait {
                context1.mergeChanges(fromContextDidSave: notif)
            }
        } else if ensemble === ensemble2 {
            context2.performAndWait {
                context2.mergeChanges(fromContextDidSave: notif)
            }
        }
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] {
        globalIdentifiersBlock?(objects) ?? []
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, shouldSaveMergedChangesIn savingContext: NSManagedObjectContext, reparationContext: NSManagedObjectContext) -> Bool {
        shouldSaveBlock?(ensemble, savingContext, reparationContext)
        return !shouldFailMerge
    }

    // MARK: - Attach / Merge / Sync

    func attachStores() async throws {
        try await ensemble1.attachPersistentStore()
        try await ensemble2.attachPersistentStore()
    }

    func syncEnsemble(_ ensemble: CoreDataEnsemble) async throws {
        try await ensemble.sync()
    }

    func rebaseEnsemble(_ ensemble: CoreDataEnsemble) async throws {
        try await ensemble.sync(options: .forceRebase)
    }

    func syncEnsembleAndSuppressRebase(_ ensemble: CoreDataEnsemble) async throws {
        try await ensemble.sync(options: .suppressRebase)
    }

    func syncChanges() async throws {
        try await syncEnsemble(ensemble1)
        try await syncEnsemble(ensemble2)
        try await syncEnsemble(ensemble1)
        try await syncEnsemble(ensemble2)
    }

    func syncChangesAndSuppressRebase() async throws {
        try await syncEnsembleAndSuppressRebase(ensemble1)
        try await syncEnsembleAndSuppressRebase(ensemble2)
        try await syncEnsembleAndSuppressRebase(ensemble1)
        try await syncEnsembleAndSuppressRebase(ensemble2)
    }

    func attachEnsemble(_ ensemble: CoreDataEnsemble) async throws {
        try await ensemble.attachPersistentStore()
    }

    func detachEnsemble(_ ensemble: CoreDataEnsemble) async throws {
        try await ensemble.detachPersistentStore()
    }

    // MARK: - Fetch Helpers

    func fetchObjects(entity: String, in context: NSManagedObjectContext) -> [NSManagedObject] {
        nonisolated(unsafe) var result: [NSManagedObject] = []
        context.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
            result = (try? context.fetch(fetch)) ?? []
        }
        return result
    }

    func fetchParents(in context: NSManagedObjectContext) -> [NSManagedObject] {
        fetchObjects(entity: "Parent", in: context)
    }

    func fetchChildren(in context: NSManagedObjectContext) -> [NSManagedObject] {
        fetchObjects(entity: "Child", in: context)
    }

    func save(_ context: NSManagedObjectContext) {
        context.performAndWait {
            try! context.save()
        }
    }

    // MARK: - Insert Helpers

    @discardableResult
    func insertParent(name: String? = nil, in context: NSManagedObjectContext) -> NSManagedObject {
        insertObject(entity: "Parent", name: name, in: context)
    }

    @discardableResult
    func insertChild(name: String? = nil, in context: NSManagedObjectContext) -> NSManagedObject {
        insertObject(entity: "Child", name: name, in: context)
    }

    @discardableResult
    func insertObject(entity: String, name: String? = nil, in context: NSManagedObjectContext) -> NSManagedObject {
        let obj = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
        if let name { obj.setValue(name, forKey: "name") }
        return obj
    }

    // MARK: - Fetch-by-Name Helpers

    func fetchParent(named name: String, in context: NSManagedObjectContext) -> NSManagedObject? {
        fetchParents(in: context).first { ($0.value(forKey: "name") as? String) == name }
    }

    func fetchChild(named name: String, in context: NSManagedObjectContext) -> NSManagedObject? {
        fetchChildren(in: context).first { ($0.value(forKey: "name") as? String) == name }
    }

    // MARK: - File System Helpers

    func cloudBaselinesDir() -> String {
        (cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/baselines")
    }

    func cloudEventsDir() -> String {
        (cloudRootDir as NSString).appendingPathComponent("com.ensembles.synctest/events")
    }

    func contentsOfDirectory(atPath path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }
}
