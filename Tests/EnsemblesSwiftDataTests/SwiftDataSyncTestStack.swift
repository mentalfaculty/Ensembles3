import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

#if canImport(SwiftData)
import SwiftData
import EnsemblesSwiftData

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
final class SwiftDataSyncTestStack: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {

    let context1: NSManagedObjectContext
    let context2: NSManagedObjectContext
    let model: NSManagedObjectModel
    let ensemble1: CoreDataEnsemble
    let ensemble2: CoreDataEnsemble

    let testRootDirectory: String

    var globalIdentifiersBlock: (([NSManagedObject]) -> [String?])?

    init(modelTypes: [any PersistentModel.Type]) {
        let rootDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("SwiftDataSyncTest_\(ProcessInfo.processInfo.globallyUniqueString)")
        try! FileManager.default.createDirectory(atPath: rootDir, withIntermediateDirectories: true)
        self.testRootDirectory = rootDir

        let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes)!
        self.model = model

        // First store
        let storeFile1 = (rootDir as NSString).appendingPathComponent("store1.sqlite")
        let storeURL1 = URL(fileURLWithPath: storeFile1)

        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)

        let ctx1 = NSManagedObjectContext(.mainQueue)
        ctx1.persistentStoreCoordinator = psc1
        ctx1.stalenessInterval = 0.0
        ctx1.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        self.context1 = ctx1

        // Cloud
        let cloudDir = (rootDir as NSString).appendingPathComponent("cloudfiles")
        try! FileManager.default.createDirectory(atPath: cloudDir, withIntermediateDirectories: true)

        let cloudFS1 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let edRoot1 = (rootDir as NSString).appendingPathComponent("eventData1")

        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.swiftdatasynctest",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModel: model,
            managedObjectModels: [model],
            cloudFileSystem: cloudFS1,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot1)
        )!
        self.ensemble1 = ens1

        // Second store
        let storeFile2 = (rootDir as NSString).appendingPathComponent("store2.sqlite")
        let storeURL2 = URL(fileURLWithPath: storeFile2)

        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)

        let ctx2 = NSManagedObjectContext(.mainQueue)
        ctx2.persistentStoreCoordinator = psc2
        ctx2.stalenessInterval = 0.0
        ctx2.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump
        self.context2 = ctx2

        let cloudFS2 = LocalCloudFileSystem(rootDirectory: cloudDir)
        let edRoot2 = (rootDir as NSString).appendingPathComponent("eventData2")

        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.swiftdatasynctest",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModel: model,
            managedObjectModels: [model],
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

    // MARK: - Attach / Merge / Sync

    func attachStores() async throws {
        try await ensemble1.attachPersistentStore()
        try await ensemble2.attachPersistentStore()
    }

    func attachStoresExcludingDevice2Data() async throws {
        try await ensemble1.attachPersistentStore()
        try await ensemble2.attachPersistentStore(seedPolicy: .excludeLocalData)
    }

    func syncChanges() async throws {
        try await ensemble1.sync()
        try await ensemble2.sync()
        try await ensemble1.sync()
        try await ensemble2.sync()
    }

    // MARK: - Helpers

    func save(_ context: NSManagedObjectContext) {
        context.performAndWait {
            try! context.save()
        }
    }

    func fetchObjects(entity: String, in context: NSManagedObjectContext) -> [NSManagedObject] {
        nonisolated(unsafe) var result: [NSManagedObject] = []
        context.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: entity)
            fetch.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
            result = (try? context.fetch(fetch)) ?? []
        }
        return result
    }
}
#endif
