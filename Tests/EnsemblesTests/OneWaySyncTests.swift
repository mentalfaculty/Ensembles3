import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("OneWaySync", .serialized)
@MainActor
struct OneWaySyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Attaching")
    func attaching() async throws {
        try await stack.ensemble1.attachPersistentStore()
        #expect(stack.ensemble1.isAttached)
    }

    @Test("Attaching twice gives error")
    func attachingTwiceGivesError() async throws {
        try await stack.ensemble1.attachPersistentStore()
        await #expect(throws: (any Error).self) {
            try await stack.ensemble1.attachPersistentStore()
        }
        #expect(stack.ensemble1.isAttached)
    }

    @Test("Detaching")
    func detaching() async throws {
        try await stack.ensemble1.attachPersistentStore()
        try await stack.ensemble1.detachPersistentStore()
        #expect(!stack.ensemble1.isAttached)
    }

    @Test("Detaching twice gives error")
    func detachingTwiceGivesError() async throws {
        try await stack.ensemble1.attachPersistentStore()
        try await stack.ensemble1.detachPersistentStore()
        await #expect(throws: (any Error).self) {
            try await stack.ensemble1.detachPersistentStore()
        }
        #expect(!stack.ensemble1.isAttached)
    }

    @Test("Importing existing data")
    func importingExistingData() async throws {
        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let parent2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent2.setValue(parent1, forKey: "relatedParentsInverse")
        stack.save(stack.context1)

        try await stack.attachStores()
        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 2)
        let parent = parents.last!
        #expect(parent.value(forKey: "relatedParentsInverse") != nil || (parent.value(forKey: "relatedParents") as? NSSet)?.count != 0)
    }

    @Test("Save and merge")
    func saveAndMerge() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let date = Date(timeIntervalSinceReferenceDate: 10.0)
        parent.setValue("bob", forKey: "name")
        parent.setValue(date, forKey: "date")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let syncedParent = parents.last!
        #expect(syncedParent.value(forKey: "name") as? String == "bob")
        #expect(syncedParent.value(forKey: "date") as? Date == date)
    }

    @Test("Update")
    func update() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let date = Date(timeIntervalSinceReferenceDate: 10.0)
        parent.setValue("bob", forKey: "name")
        parent.setValue(date, forKey: "date")
        stack.save(stack.context1)

        try await stack.syncChanges()

        parent.setValue("dave", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let syncedParent = parents.last!
        #expect(syncedParent.value(forKey: "name") as? String == "dave")
        #expect(syncedParent.value(forKey: "date") as? Date == date)
    }

    @Test("NaN attribute")
    func notANumberAttribute() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(NSNumber(value: Double.nan), forKey: "doubleProperty")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        let syncedParent = parents.last!
        #expect(syncedParent.value(forKey: "doubleProperty") == nil)
        #expect(parent.value(forKey: "doubleProperty") == nil)
    }

    @Test("Small double attribute")
    func smallDoubleAttribute() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(NSNumber(value: 0.000555), forKey: "doubleProperty")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        let syncedParent = parents.last!
        let value = (syncedParent.value(forKey: "doubleProperty") as? NSNumber)?.doubleValue ?? 0
        #expect(abs(value - 0.000555) < 0.000001)
    }

    @Test("Large double attribute")
    func largeDoubleAttribute() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(NSNumber(value: 1.005e10), forKey: "doubleProperty")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        let syncedParent = parents.last!
        let value = (syncedParent.value(forKey: "doubleProperty") as? NSNumber)?.doubleValue ?? 0
        #expect(abs(value - 1.005e10) < 1.0e7)
    }

    @Test("Small float attribute")
    func smallFloatAttribute() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(NSNumber(value: Float(0.000555)), forKey: "floatProperty")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let value = (parent.value(forKey: "floatProperty") as? NSNumber)?.floatValue ?? 0
        #expect(abs(value - 0.000555) < 0.000001)
    }

    @Test("To-one relationship")
    func toOneRelationship() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let children = stack.fetchChildren(in: stack.context2)
        #expect(children.count == 1)

        let syncedParent = parents.last!
        let syncedChild = children.last!
        #expect((syncedParent.value(forKey: "child") as? NSManagedObject) == syncedChild)
    }

    @Test("To-one relationship from super entity")
    func toOneRelationshipFromSuperEntity() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        let child = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchObjects(entity: "DerivedParent", in: stack.context2)
        #expect(parents.count == 1)
        let children = stack.fetchObjects(entity: "DerivedChild", in: stack.context2)
        #expect(children.count == 1)

        let syncedParent = parents.last!
        let syncedChild = children.last!
        #expect((syncedParent.value(forKey: "child") as? NSManagedObject) == syncedChild)
    }

    @Test("To-many relationship")
    func toManyRelationship() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue(parent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        let children = stack.fetchChildren(in: stack.context2)
        let syncedParent = parents.last!
        let syncedChild = children.last!
        #expect((syncedParent.value(forKey: "children") as? NSSet)?.anyObject() as? NSManagedObject == syncedChild)
    }

    @Test("Inherited one-to-many relationships between descended entities")
    func inheritedOneToManyRelationshipsBetweenDescendedEntities() async throws {
        try await stack.attachStores()

        let bOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "B", into: stack.context1)
        let cOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "C", into: stack.context1)
        cOnDevice1.setValue(bOnDevice1, forKey: "inverseObject")
        bOnDevice1.setValue(cOnDevice1, forKey: "inverseObject")
        stack.save(stack.context1)

        try await stack.syncChanges()

        var fetch = NSFetchRequest<NSManagedObject>(entityName: "C")
        fetch.includesSubentities = false
        let cObjects = (try? stack.context2.fetch(fetch)) ?? []
        let cOnDevice2 = cObjects.last
        #expect(cOnDevice2 != nil)

        fetch = NSFetchRequest<NSManagedObject>(entityName: "B")
        fetch.includesSubentities = false
        let bObjects = (try? stack.context2.fetch(fetch)) ?? []
        let bOnDevice2 = bObjects.last
        #expect(bOnDevice2 != nil)

        #expect((cOnDevice2?.value(forKey: "inverseObject") as? NSManagedObject) == bOnDevice2)
        #expect((bOnDevice2?.value(forKey: "inverseObject") as? NSManagedObject) == cOnDevice2)
    }

    @Test("Initial import with no global identifiers provided")
    func initialImportWithNoGlobalIdentifiersProvided() async throws {
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        stack.ensemble1.delegate = nil
        stack.ensemble2.delegate = nil
        try await stack.attachStores()
        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let children = stack.fetchChildren(in: stack.context2)
        #expect(children.count == 1)

        let syncedParent = parents.last!
        let syncedChild = children.last!
        #expect((syncedParent.value(forKey: "child") as? NSManagedObject) == syncedChild)
    }

    @Test("Save with no global identifiers provided")
    func saveWithNoGlobalIdentifiersProvided() async throws {
        stack.ensemble1.delegate = nil
        stack.ensemble2.delegate = nil
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let children = stack.fetchChildren(in: stack.context2)
        #expect(children.count == 1)

        let syncedParent = parents.last!
        let syncedChild = children.last!
        #expect((syncedParent.value(forKey: "child") as? NSManagedObject) == syncedChild)
    }

    @Test("Change relationship with no global identifiers provided")
    func changeRelationshipWithNoGlobalIdentifiersProvided() async throws {
        stack.ensemble1.delegate = nil
        stack.ensemble2.delegate = nil
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        stack.save(stack.context1)

        child1.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        var children = stack.fetchChildren(in: stack.context2)
        #expect(children.count == 2)

        let syncedParent = parents.last!
        let syncedChild = syncedParent.value(forKey: "child") as? NSManagedObject
        #expect(syncedChild != nil)

        children = children.filter { $0 != syncedChild }
        let otherChild = children.last!
        syncedParent.setValue(otherChild, forKey: "child")
        stack.save(stack.context2)

        try await stack.syncChanges()

        stack.context1.refresh(parent, mergeChanges: false)
        #expect((parent.value(forKey: "child") as? NSManagedObject) == child2)
    }

    @Test("Small data attribute leads to no external data files")
    func smallDataAttributeLeadsToNoExternalDataFiles() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(Data(count: 10000), forKey: "data")
        stack.save(stack.context1)

        let eventStoreDataDir = (stack.eventDataRoot1 as NSString).appendingPathComponent("com.ensembles.synctest/data")
        let contents = stack.contentsOfDirectory(atPath: eventStoreDataDir)
        #expect(contents.count == 0)
    }

    @Test("Large data attribute leads to external data file")
    func largeDataAttributeLeadsToExternalDataFile() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(Data(count: 10001), forKey: "data")
        stack.save(stack.context1)

        let eventStoreDataDir = (stack.eventDataRoot1 as NSString).appendingPathComponent("com.ensembles.synctest/data")
        let contents = stack.contentsOfDirectory(atPath: eventStoreDataDir)
        #expect(contents.count == 1)
    }

    @Test("Sync of large data transfers file")
    func syncOfLargeDataTransfersFile() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(Data(count: 10001), forKey: "data")
        stack.save(stack.context1)

        let eventStoreDataDir = (stack.eventDataRoot2 as NSString).appendingPathComponent("com.ensembles.synctest/data")
        var contents = stack.contentsOfDirectory(atPath: eventStoreDataDir)
        #expect(contents.count == 0)

        try await stack.syncChanges()

        contents = stack.contentsOfDirectory(atPath: eventStoreDataDir)
        #expect(contents.count == 1)

        let parents = stack.fetchParents(in: stack.context2)
        let parentInContext2 = parents.last!
        #expect((parentInContext2.value(forKey: "data") as? Data)?.count == 10001)
    }

    @Test("Import of large data")
    func importOfLargeData() async throws {
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(Data(count: 10001), forKey: "data")
        stack.save(stack.context1)

        try await stack.attachStores()

        let eventStoreDataDir = (stack.eventDataRoot1 as NSString).appendingPathComponent("com.ensembles.synctest/data")
        let contents = stack.contentsOfDirectory(atPath: eventStoreDataDir)
        #expect(contents.count == 1)
    }

    @Test("Sync of small data")
    func syncOfSmallData() async throws {
        try await stack.attachStores()

        let testString = "sadf s sfd fa d afsd fd asfd af fd dfas  f sfadasdf"
        let data = testString.data(using: .utf8)!
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(data, forKey: "data")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        let parentInContext2 = parents.last!
        let syncData = parentInContext2.value(forKey: "data") as? Data
        #expect(syncData == data)
    }

    @Test("Batched migration and multipart file sets")
    func batchedMigrationAndMultipartFileSets() async throws {
        try await stack.attachStores()
        try await stack.syncEnsemble(stack.ensemble2) // Exports baseline

        for _ in 0..<500 {
            NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: stack.context1)
        }
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        try await stack.syncEnsemble(stack.ensemble2)

        let parents = stack.fetchObjects(entity: "BatchParent", in: stack.context2)
        #expect(parents.count == 500)
    }

    @Test("Batched migration of related objects")
    func batchedMigrationOfRelatedObjects() async throws {
        try await stack.attachStores()

        for _ in 0..<100 {
            let parent = NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: stack.context1)
            for _ in 0..<5 {
                let child = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
                child.setValue(parent, forKey: "batchParent")
            }
        }
        stack.save(stack.context1)
        try await stack.syncEnsemble(stack.ensemble1)

        try await stack.syncEnsemble(stack.ensemble2)
        try await stack.syncEnsemble(stack.ensemble1)

        let parents = stack.fetchObjects(entity: "BatchParent", in: stack.context2)
        #expect(parents.count == 100)

        let children = stack.fetchObjects(entity: "BatchChild", in: stack.context2)
        #expect(children.count == 500)
    }

    @Test("Update negative Int64")
    func updateNegativeLongLong() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue(NSNumber(value: Int64.min), forKey: "integer64Attribute")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let syncedParent = parents.last!
        #expect(parent.value(forKey: "integer64Attribute") as? NSNumber == NSNumber(value: Int64.min))
        #expect(syncedParent.value(forKey: "integer64Attribute") as? NSNumber == NSNumber(value: Int64.min))

        parent.setValue(NSNumber(value: Int64.min + 1), forKey: "integer64Attribute")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents2 = stack.fetchParents(in: stack.context2)
        #expect(parents2.count == 1)
        #expect(parent.value(forKey: "integer64Attribute") as? NSNumber == NSNumber(value: Int64.min + 1))
        #expect(syncedParent.value(forKey: "integer64Attribute") as? NSNumber == NSNumber(value: Int64.min + 1))
    }
}
}
