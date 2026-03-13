import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

@Suite("CoreDataEnsembleMergeTests", .serialized)
@MainActor
struct CoreDataEnsembleMergeTests {

    let rootDir: String
    let cloudDir: String
    let ensemble1: CoreDataEnsemble
    let ensemble2: CoreDataEnsemble
    let context1: NSManagedObjectContext
    let context2: NSManagedObjectContext

    init() async throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CoreDataEnsembleMergeTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        self.rootDir = root

        let cloud = (root as NSString).appendingPathComponent("cloud")
        try FileManager.default.createDirectory(atPath: cloud, withIntermediateDirectories: true)
        self.cloudDir = cloud

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!

        // First ensemble
        let storePath1 = (root as NSString).appendingPathComponent("first.sqlite")
        let storeURL1 = URL(fileURLWithPath: storePath1)
        let psc1 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc1.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL1, options: nil)
        let moc1 = NSManagedObjectContext(.mainQueue)
        moc1.persistentStoreCoordinator = psc1
        self.context1 = moc1

        let cloudFS1 = LocalCloudFileSystem(rootDirectory: cloud)
        let eventDataRoot1 = (root as NSString).appendingPathComponent("eventStore1")
        let ens1 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL1,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS1,
            localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot1)
        )!
        self.ensemble1 = ens1

        try await ens1.attachPersistentStore()

        // Second ensemble
        let storePath2 = (root as NSString).appendingPathComponent("second.sqlite")
        let storeURL2 = URL(fileURLWithPath: storePath2)
        let psc2 = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc2.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL2, options: nil)
        let moc2 = NSManagedObjectContext(.mainQueue)
        moc2.persistentStoreCoordinator = psc2
        self.context2 = moc2

        let cloudFS2 = LocalCloudFileSystem(rootDirectory: cloud)
        let eventDataRoot2 = (root as NSString).appendingPathComponent("eventStore2")
        let ens2 = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL2,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS2,
            localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot2)
        )!
        self.ensemble2 = ens2

        try await ens2.attachPersistentStore()
    }

    // MARK: - Tests

    @Test("Will-save merge repair method")
    func willSaveMergeRepair() async throws {
        // Insert in context2 and merge to cloud
        context2.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context2)
            try! context2.save()
        }
        try await ensemble2.sync()

        // Set delegate on ensemble1 and merge
        let delegate = MergeRepairDelegate()
        ensemble1.delegate = delegate
        try await ensemble1.sync()

        try await Task.sleep(for: .milliseconds(50))

        #expect(delegate.willSaveRepairMethodWasCalled)
        #expect(delegate.inserted.count + delegate.updated.count == 1)
        #expect(delegate.deleted.count == 0)
    }

    @Test("Did-save merge repair method")
    func didSaveMergeRepair() async throws {
        // Insert in context2 and merge to cloud
        context2.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context2)
            try! context2.save()
        }
        try await ensemble2.sync()

        // Set delegate on ensemble1 and merge
        let delegate = MergeRepairDelegate()
        ensemble1.delegate = delegate
        try await ensemble1.sync()

        try await Task.sleep(for: .milliseconds(50))

        #expect(delegate.didSaveRepairMethodWasCalled)
        #expect(delegate.inserted.count + delegate.updated.count == 1)
    }

    @Test("Did-fail merge repair method")
    func didFailMergeRepair() async throws {
        // Insert parent in context2, merge to both sides
        nonisolated(unsafe) var parentInContext2: NSManagedObject!
        context2.performAndWait {
            parentInContext2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context2)
            try! context2.save()
        }
        try await ensemble2.sync()
        try await ensemble1.sync()

        // Create conflicting changes exceeding maxedChildren limit
        context2.performAndWait {
            let child3 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: context2)
            parentInContext2.setValue(NSSet(object: child3), forKey: "maxedChildren")
            try! context2.save()
        }

        let ctx1 = context1
        context1.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            let parentInContext1 = (try! ctx1.fetch(fetch)).last!
            let child1 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: ctx1)
            let child2 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: ctx1)
            parentInContext1.setValue(NSSet(array: [child1, child2]), forKey: "maxedChildren")
            try! ctx1.save()
        }

        // Merge ensemble2 to cloud
        try await ensemble2.sync()

        // Merge ensemble1 with delegate that repairs the conflict
        let delegate = MergeRepairDelegate()
        ensemble1.delegate = delegate
        try await ensemble1.sync()

        try await Task.sleep(for: .milliseconds(50))

        #expect(delegate.failedSaveRepairMethodWasCalled)
        #expect(delegate.failedSaveErrorCode == NSValidationRelationshipExceedsMaximumCountError)

        // Check that repairs are present in context1
        context1.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            let parents = (try? ctx1.fetch(fetch)) ?? []
            #expect(parents.count == 2)
            #expect(parents[0].value(forKey: "doubleProperty") != nil)
        }

        // Merge repairs back to second context
        try await ensemble2.sync()

        let ctx2 = context2
        context2.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            let parents = (try? ctx2.fetch(fetch)) ?? []
            #expect(parents.count == 2)
            #expect(parents[0].value(forKey: "doubleProperty") != nil)
        }
    }

    @Test("Delegate returns false to abort merge")
    func delegateReturnsFalseToAbortMerge() async throws {
        // Insert in context2 and merge to cloud
        context2.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context2)
            try! context2.save()
        }
        try await ensemble2.sync()

        // Set delegate on ensemble1 that rejects the merge
        let delegate = MergeAbortDelegate()
        ensemble1.delegate = delegate

        // Merge should throw because the delegate aborted it
        do {
            try await ensemble1.sync()
            Issue.record("Expected merge to throw when delegate returns false")
        } catch {
            // Expected — the ensemble throws cancelled when the delegate rejects
        }

        // Delegate should have been called
        #expect(delegate.shouldSaveWasCalled)

        // The merge was aborted, so context1 should not have the new object
        let ctx1 = context1
        let count: Int = context1.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            return (try? ctx1.count(for: fetch)) ?? 0
        }
        #expect(count == 0)
    }

    @Test("Rapid successive merges serialize correctly")
    func rapidSuccessiveMergesSerialize() async throws {
        // Insert some data in context1
        context1.performAndWait {
            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context1)
            try! context1.save()
        }

        // Fire 5 merges rapidly
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await self.ensemble1.sync()
                }
            }
            try await group.waitForAll()
        }

        // All should complete without error — the ensemble serializes them
        #expect(ensemble1.isAttached)
    }

    @Test("Concurrent attach and merge attempts")
    func concurrentAttachAndMerge() async throws {
        // Detach first so we can test attach + merge
        try await ensemble1.detachPersistentStore()
        #expect(!ensemble1.isAttached)

        // Start attach and immediately call merge
        async let attachResult: Void = ensemble1.attachPersistentStore()
        async let syncResult: Void = ensemble1.sync()

        // One should succeed and one may throw (merge before attach)
        do {
            try await attachResult
        } catch {
            // Attach can fail if merge somehow ran first, but normally succeeds
        }
        do {
            try await syncResult
        } catch {
            // Merge before attach is complete may throw disallowedStateChange
        }

        // After both complete, ensemble should be in a consistent state
        // (either attached or cleanly not attached)
        try await Task.sleep(for: .milliseconds(100))
    }
}

// MARK: - Delegate

private final class MergeAbortDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    var shouldSaveWasCalled = false

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, shouldSaveMergedChangesIn savingContext: NSManagedObjectContext, reparationContext: NSManagedObjectContext) -> Bool {
        shouldSaveWasCalled = true
        return false  // Reject the merge
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {}
    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] { [] }
}

private final class MergeRepairDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    var willSaveRepairMethodWasCalled = false
    var didSaveRepairMethodWasCalled = false
    var failedSaveRepairMethodWasCalled = false
    var failedSaveErrorCode: Int = 0
    var inserted: Set<NSManagedObject> = []
    var updated: Set<NSManagedObject> = []
    var deleted: Set<NSManagedObject> = []

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, shouldSaveMergedChangesIn savingContext: NSManagedObjectContext, reparationContext: NSManagedObjectContext) -> Bool {
        savingContext.performAndWait {
            inserted = savingContext.insertedObjects
            updated = savingContext.updatedObjects
            deleted = savingContext.deletedObjects
        }
        willSaveRepairMethodWasCalled = true
        return true
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didFailToSaveMergedChangesIn savingContext: NSManagedObjectContext, error: Error, reparationContext: NSManagedObjectContext) -> Bool {
        failedSaveRepairMethodWasCalled = true
        failedSaveErrorCode = (error as NSError).code

        // Carry out repairs: remove a child, add new parent with child
        reparationContext.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
            if let originalParent = (try? reparationContext.fetch(fetch))?.last {
                if let children = originalParent.value(forKey: "maxedChildren") as? Set<NSManagedObject>,
                   let originalChild = children.first {
                    reparationContext.delete(originalChild)
                }
            }

            let newParent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: reparationContext)
            let newChild = NSEntityDescription.insertNewObject(forEntityName: "Child", into: reparationContext)
            newParent.setValue(NSSet(object: newChild), forKey: "maxedChildren")
        }

        return true
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        didSaveRepairMethodWasCalled = true
    }

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String?] { [] }
}
