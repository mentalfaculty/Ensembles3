import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("TwoWaySync", .serialized)
@MainActor
struct TwoWaySyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Update attribute on second device")
    func updateAttributeOnSecondDevice() async throws {
        try await stack.attachStores()

        let parentOnDevice1 = stack.insertParent(name: "bob", in: stack.context1)
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parentOnDevice2 = stack.fetchParents(in: stack.context2).last!
        parentOnDevice2.setValue("dave", forKey: "name")
        stack.save(stack.context2)

        try await stack.syncChanges()

        #expect(parentOnDevice1.value(forKey: "name") as? String == "dave")
        #expect(parentOnDevice2.value(forKey: "name") as? String == "dave")
    }

    @Test("Conflicting attribute updates")
    func conflictingAttributeUpdates() async throws {
        try await stack.attachStores()

        let parentOnDevice1 = stack.insertParent(name: "bob", in: stack.context1)
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Update on device 1
        parentOnDevice1.setValue("john", forKey: "name")
        stack.save(stack.context1)

        // Concurrent update on device 2. Should win due to later timestamp.
        // Small delay ensures device 2's event timestamp is strictly later on fast CI machines.
        try await Task.sleep(for: .milliseconds(10))
        let parentOnDevice2 = stack.fetchParents(in: stack.context2).last!
        #expect(parentOnDevice2.value(forKey: "name") as? String == "bob")

        parentOnDevice2.setValue("dave", forKey: "name")
        stack.save(stack.context2)

        try await stack.syncChanges()

        #expect(parentOnDevice1.value(forKey: "name") as? String == "dave")
        #expect(parentOnDevice2.value(forKey: "name") as? String == "dave")
    }

    @Test("Repeated global identifiers")
    func repeatedGlobalIdentifiers() async throws {
        try await stack.attachStores()

        stack.insertParent(name: "bob", in: stack.context1)
        stack.insertParent(name: "tom", in: stack.context1)
        stack.insertChild(name: "bob", in: stack.context1)
        stack.insertChild(name: "tom", in: stack.context1)

        stack.save(stack.context1)
        try await stack.syncChanges()

        let parentNames = Set(stack.fetchParents(in: stack.context2).compactMap { $0.value(forKey: "name") as? String })
        #expect(parentNames == Set(["bob", "tom"]))

        let childNames = Set(stack.fetchChildren(in: stack.context2).compactMap { $0.value(forKey: "name") as? String })
        #expect(childNames == Set(["bob", "tom"]))
    }

    @Test("Concurrent inserts of same object")
    func concurrentInsertsOfSameObject() async throws {
        stack.globalIdentifiersBlock = { objects in
            objects.map { $0.value(forKey: "name") as? String }
        }

        try await stack.attachStores()

        let date = Date(timeIntervalSinceReferenceDate: 10.0)
        let parent1 = stack.insertParent(name: "bob", in: stack.context1)
        parent1.setValue(date, forKey: "date")
        stack.save(stack.context1)

        let parent2 = stack.insertParent(name: "bob", in: stack.context2)
        parent2.setValue(date, forKey: "date")
        stack.save(stack.context2)

        try await stack.syncChanges()

        #expect(stack.fetchParents(in: stack.context2).count == 1)
        #expect(stack.fetchParents(in: stack.context1).count == 1)
    }

    @Test("Multiple changes sharing single data file")
    func multipleChangesSharingSingleDataFile() async throws {
        try await stack.attachStores()

        let data = Data(count: 10001)
        let parent1 = stack.insertParent(name: "1", in: stack.context1)
        parent1.setValue(data, forKey: "data")
        stack.save(stack.context1)

        let parent2 = stack.insertParent(name: "2", in: stack.context2)
        parent2.setValue(data, forKey: "data")
        stack.save(stack.context2)

        try await stack.syncChanges()

        stack.context1.delete(parent1)
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context1)
        #expect(parents.count == 1)
        let resultParent = parents.last!
        #expect(resultParent.value(forKey: "data") as? Data == data)
        #expect(resultParent.value(forKey: "name") as? String == "2")
    }

    @Test("Update to-one relationship")
    func updateToOneRelationship() async throws {
        try await stack.attachStores()

        let parent = stack.insertParent(in: stack.context1)
        let childOnDevice1 = stack.insertChild(in: stack.context1)
        childOnDevice1.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let childOnDevice2 = stack.fetchChildren(in: stack.context2).last!

        let newParent = stack.insertParent(name: "newdad", in: stack.context2)
        childOnDevice2.setValue(newParent, forKey: "parent")
        stack.save(stack.context2)

        try await stack.syncChanges()

        let newParentOnDevice1 = childOnDevice1.value(forKey: "parent") as? NSManagedObject
        #expect(newParentOnDevice1 != nil)
        #expect(newParentOnDevice1 != parent)
        #expect(newParentOnDevice1?.value(forKey: "name") as? String == "newdad")
    }

    @Test("Update to-many relationship")
    func updateToManyRelationship() async throws {
        try await stack.attachStores()

        let parent = stack.insertParent(in: stack.context1)
        let child1 = stack.insertChild(name: "child1", in: stack.context1)
        child1.setValue(parent, forKey: "parentWithSiblings")
        let child2 = stack.insertChild(name: "child2", in: stack.context1)
        child2.setValue(parent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let child1OnDevice2 = stack.fetchChild(named: "child1", in: stack.context2)!
        stack.context2.delete(child1OnDevice2)
        stack.save(stack.context2)

        try await stack.syncChanges()

        let childrenOnDevice1 = parent.value(forKey: "children") as? NSSet
        #expect(childrenOnDevice1?.count == 1)
        #expect(child2.value(forKey: "name") as? String == "child2")
    }

    @Test("Update ordered relationship")
    func updateOrderedRelationship() async throws {
        try await stack.attachStores()

        let parent = stack.insertParent(in: stack.context1)
        let child1 = stack.insertChild(name: "child1", in: stack.context1)
        let child2 = stack.insertChild(name: "child2", in: stack.context1)
        let child3 = stack.insertChild(name: "child3", in: stack.context1)
        parent.setValue(NSOrderedSet(array: [child1, child2, child3]), forKey: "orderedChildren")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parentOnDevice2 = stack.fetchParents(in: stack.context2).last!
        let childrenOnDevice2 = (parentOnDevice2.value(forKey: "orderedChildren") as! NSOrderedSet).mutableCopy() as! NSMutableOrderedSet
        #expect(childrenOnDevice2.count == 3)

        // Reorder: move child3 to index 1
        childrenOnDevice2.moveObjects(at: IndexSet(integer: 2), to: 1)
        parentOnDevice2.setValue(childrenOnDevice2, forKey: "orderedChildren")
        stack.save(stack.context2)

        try await stack.syncChanges()

        let orderedChildrenOnDevice1 = parent.value(forKey: "orderedChildren") as! NSOrderedSet
        #expect(orderedChildrenOnDevice1.count == 3)
        #expect(orderedChildrenOnDevice1[0] as? NSManagedObject == child1)
        #expect(orderedChildrenOnDevice1[1] as? NSManagedObject == child3)
        #expect(orderedChildrenOnDevice1[2] as? NSManagedObject == child2)
    }

    @Test("Self-referential relationships")
    func selfReferentialRelationships() async throws {
        try await stack.attachStores()

        let parent1 = stack.insertParent(name: "item1", in: stack.context1)
        let parent2 = stack.insertParent(name: "item2", in: stack.context1)
        let parent3 = stack.insertParent(name: "item3", in: stack.context1)
        parent1.setValue(NSSet(array: [parent2, parent3]), forKey: "relatedParents")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parent1OnDevice2 = stack.fetchParent(named: "item1", in: stack.context2)!
        #expect((parent1OnDevice2.value(forKey: "relatedParents") as? NSSet)?.count == 2)
    }

    @Test("Inherited one-to-many relationships between subentities")
    func inheritedOneToManyRelationshipsBetweenSubentities() async throws {
        try await stack.attachStores()

        let parent = stack.insertObject(entity: "DerivedParent", name: "item1", in: stack.context1)
        let child1 = stack.insertObject(entity: "DerivedChild", name: "item1", in: stack.context1)
        child1.setValue(parent, forKey: "parentWithSiblings")
        let child2 = stack.insertObject(entity: "DerivedChild", name: "item2", in: stack.context1)
        child2.setValue(parent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let children = stack.fetchObjects(entity: "DerivedChild", in: stack.context2)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "item1" }!
        stack.context2.delete(child1OnDevice2)
        stack.save(stack.context2)

        try await stack.syncChanges()

        let childrenOnDevice1 = parent.value(forKey: "children") as? NSSet
        #expect(child2.value(forKey: "name") as? String == "item2")
        #expect(childrenOnDevice1?.count == 1)
    }

    @Test("Inherited one-to-one relationships between subentities")
    func inheritedOneToOneRelationshipsBetweenSubentities() async throws {
        try await stack.attachStores()

        let parent = stack.insertObject(entity: "DerivedParent", name: "item", in: stack.context1)
        let child1 = stack.insertObject(entity: "DerivedChild", name: "item", in: stack.context1)
        child1.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let children = stack.fetchObjects(entity: "DerivedChild", in: stack.context2)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "item" }!
        #expect(child1OnDevice2.value(forKey: "parent") != nil)
    }

    @Test("Uninherited relationships between subentities")
    func uninheritedRelationshipsBetweenSubentities() async throws {
        try await stack.attachStores()

        let parent = stack.insertObject(entity: "DerivedParent", name: "item1", in: stack.context1)
        let child1 = stack.insertObject(entity: "DerivedChild", name: "item1", in: stack.context1)
        child1.setValue(parent, forKey: "derivedParent")
        let child2 = stack.insertObject(entity: "DerivedChild", name: "item2", in: stack.context1)
        child2.setValue(parent, forKey: "derivedParent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let children = stack.fetchObjects(entity: "DerivedChild", in: stack.context2)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "item1" }!
        stack.context2.delete(child1OnDevice2)
        stack.save(stack.context2)

        try await stack.syncChanges()

        let childrenOnDevice1 = parent.value(forKey: "derivedChildren") as? NSSet
        #expect(child2.value(forKey: "name") as? String == "item2")
        #expect(childrenOnDevice1?.count == 1)
    }

    @Test("Relationships mixing entities")
    func relationshipsMixingEntities() async throws {
        try await stack.attachStores()

        let derivedParent = stack.insertObject(entity: "DerivedParent", name: "dp1", in: stack.context1)
        let parent = stack.insertParent(name: "p2", in: stack.context1)

        let child1 = stack.insertObject(entity: "DerivedChild", name: "dc1", in: stack.context1)
        child1.setValue(parent, forKey: "parent")
        child1.setValue(derivedParent, forKey: "parentWithSiblings")

        let child2 = stack.insertChild(name: "c2", in: stack.context1)
        child2.setValue(derivedParent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let child1OnDevice2 = stack.fetchChild(named: "dc1", in: stack.context2)!
        let child2OnDevice2 = stack.fetchChild(named: "c2", in: stack.context2)!
        let derivedParentOnDevice2 = stack.fetchParent(named: "dp1", in: stack.context2)!
        let parentOnDevice2 = stack.fetchParent(named: "p2", in: stack.context2)!

        #expect((child1OnDevice2.value(forKey: "parent") as? NSManagedObject) == parentOnDevice2)
        #expect((child1OnDevice2.value(forKey: "parentWithSiblings") as? NSManagedObject) == derivedParentOnDevice2)
        #expect((child2OnDevice2.value(forKey: "parentWithSiblings") as? NSManagedObject) == derivedParentOnDevice2)
    }

    @Test("Attaching with no import of local data")
    func attachingWithNoImportOfLocalData() async throws {
        stack.insertObject(entity: "DerivedParent", in: stack.context1)
        stack.save(stack.context1)
        stack.insertObject(entity: "DerivedParent", in: stack.context2)
        stack.save(stack.context2)

        try await stack.ensemble1.attachPersistentStore()
        try await stack.ensemble2.attachPersistentStore(seedPolicy: .excludeLocalData)

        try await stack.syncChanges()

        #expect(stack.fetchObjects(entity: "DerivedParent", in: stack.context2).count == 1)
        #expect(stack.fetchObjects(entity: "DerivedParent", in: stack.context1).count == 1)

        // Add more objects
        stack.insertObject(entity: "DerivedParent", in: stack.context1)
        stack.save(stack.context1)
        stack.insertObject(entity: "DerivedParent", in: stack.context2)
        stack.save(stack.context2)

        try await stack.syncChanges()

        #expect(stack.fetchObjects(entity: "DerivedParent", in: stack.context2).count == 3)
        #expect(stack.fetchObjects(entity: "DerivedParent", in: stack.context1).count == 3)
    }

    @Test("Leaving behind devices in a rebase")
    func leavingBehindDevicesInARebase() async throws {
        try await stack.attachStores()
        try await stack.syncChangesAndSuppressRebase()

        stack.insertParent(name: "bob", in: stack.context1)
        stack.save(stack.context1)
        try await stack.syncChanges()

        // Perform multiple rebases to leave device 2 behind
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble2)

        // Add object to left-behind device
        stack.insertParent(name: "fred", in: stack.context2)
        stack.save(stack.context2)

        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble2)

        let request = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        request.predicate = NSPredicate(format: "name == %@", "fred")
        let objectsInContext2AfterSync = try stack.context2.fetch(request)
        #expect(objectsInContext2AfterSync.count == 1)
    }

    @Test("Rebase of one-to-many relationship")
    func rebaseOfOneToManyRelationship() async throws {
        try await stack.attachStores()
        try await stack.syncChangesAndSuppressRebase()

        let parent1 = stack.insertParent(name: "1", in: stack.context1)
        let parent3 = stack.insertParent(name: "3", in: stack.context1)
        let parent4 = stack.insertParent(name: "4", in: stack.context1)
        stack.save(stack.context1)
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble1)

        // Relate them
        parent1.mutableSetValue(forKey: "relatedParents").add(parent3)
        stack.save(stack.context1)
        parent1.mutableSetValue(forKey: "relatedParents").add(parent4)
        stack.save(stack.context1)
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble1)

        // Unrelate them
        parent1.mutableSetValue(forKey: "relatedParents").remove(parent3)
        stack.save(stack.context1)
        #expect(parent3.value(forKey: "relatedParentsInverse") == nil)
        parent1.mutableSetValue(forKey: "relatedParents").remove(parent4)
        stack.save(stack.context1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 0)
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble1)

        try await stack.rebaseEnsemble(stack.ensemble1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 0)
    }

    @Test("Many rebases of one-to-many relationship")
    func manyRebasesOfOneToManyRelationship() async throws {
        try await stack.attachStores()
        try await stack.syncChangesAndSuppressRebase()

        let parent1 = stack.insertParent(name: "1", in: stack.context1)
        let parent3 = stack.insertParent(name: "3", in: stack.context1)
        let parent4 = stack.insertParent(name: "4", in: stack.context1)
        stack.save(stack.context1)

        // Relate
        parent1.mutableSetValue(forKey: "relatedParents").add(parent3)
        stack.save(stack.context1)
        parent1.mutableSetValue(forKey: "relatedParents").add(parent4)
        stack.save(stack.context1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 2)

        // Rebase
        try await stack.rebaseEnsemble(stack.ensemble1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 2)

        // Unrelate
        parent1.mutableSetValue(forKey: "relatedParents").remove(parent3)
        stack.save(stack.context1)
        parent1.mutableSetValue(forKey: "relatedParents").remove(parent4)
        stack.save(stack.context1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 0)

        // Rebase
        try await stack.rebaseEnsemble(stack.ensemble1)
        #expect((parent1.value(forKey: "relatedParents") as? NSSet)?.count == 0)
        #expect(parent3.value(forKey: "relatedParentsInverse") == nil)
        #expect(parent4.value(forKey: "relatedParentsInverse") == nil)
    }
}
}
