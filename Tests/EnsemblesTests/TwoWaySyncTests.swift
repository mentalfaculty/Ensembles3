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

        let parentOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parentOnDevice1.setValue("bob", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchParents(in: stack.context2)
        #expect(parents.count == 1)
        let parentOnDevice2 = parents.last!
        parentOnDevice2.setValue("dave", forKey: "name")
        stack.save(stack.context2)

        try await stack.syncChanges()

        #expect(parentOnDevice1.value(forKey: "name") as? String == "dave")
        #expect(parentOnDevice2.value(forKey: "name") as? String == "dave")
    }

    @Test("Conflicting attribute updates")
    func conflictingAttributeUpdates() async throws {
        try await stack.attachStores()

        let parentOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parentOnDevice1.setValue("bob", forKey: "name")
        stack.save(stack.context1)

        try await stack.syncChanges()

        // Update on device 1
        parentOnDevice1.setValue("john", forKey: "name")
        stack.save(stack.context1)

        // Concurrent update on device 2. Should win due to later timestamp.
        // Small delay ensures device 2's event timestamp is strictly later on fast CI machines.
        try await Task.sleep(for: .milliseconds(10))
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parentOnDevice2 = try stack.context2.fetch(fetch).last!
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

        var parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("bob", forKey: "name")
        parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("tom", forKey: "name")

        var child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue("bob", forKey: "name")
        child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child.setValue("tom", forKey: "name")

        stack.save(stack.context1)
        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context2.fetch(fetch)
        let parentNames = Set(parents.compactMap { $0.value(forKey: "name") as? String })
        #expect(parentNames == Set(["bob", "tom"]))

        let childFetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
        let children = try stack.context2.fetch(childFetch)
        let childNames = Set(children.compactMap { $0.value(forKey: "name") as? String })
        #expect(childNames == Set(["bob", "tom"]))
    }

    @Test("Concurrent inserts of same object")
    func concurrentInsertsOfSameObject() async throws {
        stack.globalIdentifiersBlock = { objects in
            objects.map { $0.value(forKey: "name") as? String }
        }

        try await stack.attachStores()

        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let date = Date(timeIntervalSinceReferenceDate: 10.0)
        parent1.setValue("bob", forKey: "name")
        parent1.setValue(date, forKey: "date")
        stack.save(stack.context1)

        let parent2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        parent2.setValue("bob", forKey: "name")
        parent2.setValue(date, forKey: "date")
        stack.save(stack.context2)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents2 = try stack.context2.fetch(fetch)
        #expect(parents2.count == 1)

        let parents1 = try stack.context1.fetch(fetch)
        #expect(parents1.count == 1)
    }

    @Test("Multiple changes sharing single data file")
    func multipleChangesSharingSingleDataFile() async throws {
        try await stack.attachStores()

        let data = Data(count: 10001)
        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent1.setValue("1", forKey: "name")
        parent1.setValue(data, forKey: "data")
        stack.save(stack.context1)

        let parent2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        parent2.setValue("2", forKey: "name")
        parent2.setValue(data, forKey: "data")
        stack.save(stack.context2)

        try await stack.syncChanges()

        stack.context1.delete(parent1)
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context1.fetch(fetch)
        #expect(parents.count == 1)
        let resultParent = parents.last!
        #expect(resultParent.value(forKey: "data") as? Data == data)
        #expect(resultParent.value(forKey: "name") as? String == "2")
    }

    @Test("Update to-one relationship")
    func updateToOneRelationship() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let childOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        childOnDevice1.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let childFetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
        let children = try stack.context2.fetch(childFetch)
        let childOnDevice2 = children.last!

        let newParent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        newParent.setValue("newdad", forKey: "name")
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

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child1.setValue("child1", forKey: "name")
        child1.setValue(parent, forKey: "parentWithSiblings")
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child2.setValue("child2", forKey: "name")
        child2.setValue(parent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let childFetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
        let children = try stack.context2.fetch(childFetch)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "child1" }!
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

        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        let child3 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child1.setValue("child1", forKey: "name")
        child2.setValue("child2", forKey: "name")
        child3.setValue("child3", forKey: "name")
        parent.setValue(NSOrderedSet(array: [child1, child2, child3]), forKey: "orderedChildren")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context2.fetch(fetch)
        let parentOnDevice2 = parents.last!
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

        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent1.setValue("item1", forKey: "name")
        let parent2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent2.setValue("item2", forKey: "name")
        let parent3 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent3.setValue("item3", forKey: "name")
        parent1.setValue(NSSet(array: [parent2, parent3]), forKey: "relatedParents")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context2.fetch(fetch)
        let parent1OnDevice2 = parents.first { ($0.value(forKey: "name") as? String) == "item1" }!
        #expect((parent1OnDevice2.value(forKey: "relatedParents") as? NSSet)?.count == 2)
    }

    @Test("Inherited one-to-many relationships between subentities")
    func inheritedOneToManyRelationshipsBetweenSubentities() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        parent.setValue("item1", forKey: "name")
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child1.setValue("item1", forKey: "name")
        child1.setValue(parent, forKey: "parentWithSiblings")
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child2.setValue("item2", forKey: "name")
        child2.setValue(parent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "DerivedChild")
        let children = try stack.context2.fetch(fetch)
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

        let parent = NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        parent.setValue("item", forKey: "name")
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child1.setValue("item", forKey: "name")
        child1.setValue(parent, forKey: "parent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "DerivedChild")
        let children = try stack.context2.fetch(fetch)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "item" }!
        #expect(child1OnDevice2.value(forKey: "parent") != nil)
    }

    @Test("Uninherited relationships between subentities")
    func uninheritedRelationshipsBetweenSubentities() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        parent.setValue("item1", forKey: "name")
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child1.setValue("item1", forKey: "name")
        child1.setValue(parent, forKey: "derivedParent")
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child2.setValue("item2", forKey: "name")
        child2.setValue(parent, forKey: "derivedParent")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "DerivedChild")
        let children = try stack.context2.fetch(fetch)
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

        let derivedParent = NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        derivedParent.setValue("dp1", forKey: "name")
        let parent = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent.setValue("p2", forKey: "name")

        let child1 = NSEntityDescription.insertNewObject(forEntityName: "DerivedChild", into: stack.context1)
        child1.setValue("dc1", forKey: "name")
        child1.setValue(parent, forKey: "parent")
        child1.setValue(derivedParent, forKey: "parentWithSiblings")

        let child2 = NSEntityDescription.insertNewObject(forEntityName: "Child", into: stack.context1)
        child2.setValue("c2", forKey: "name")
        child2.setValue(derivedParent, forKey: "parentWithSiblings")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let childFetch = NSFetchRequest<NSManagedObject>(entityName: "Child")
        let children = try stack.context2.fetch(childFetch)
        let child1OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "dc1" }!
        let child2OnDevice2 = children.first { ($0.value(forKey: "name") as? String) == "c2" }!

        let parentFetch = NSFetchRequest<NSManagedObject>(entityName: "Parent")
        let parents = try stack.context2.fetch(parentFetch)
        let derivedParentOnDevice2 = parents.first { ($0.value(forKey: "name") as? String) == "dp1" }!
        let parentOnDevice2 = parents.first { ($0.value(forKey: "name") as? String) == "p2" }!

        #expect((child1OnDevice2.value(forKey: "parent") as? NSManagedObject) == parentOnDevice2)
        #expect((child1OnDevice2.value(forKey: "parentWithSiblings") as? NSManagedObject) == derivedParentOnDevice2)
        #expect((child2OnDevice2.value(forKey: "parentWithSiblings") as? NSManagedObject) == derivedParentOnDevice2)
    }

    @Test("Attaching with no import of local data")
    func attachingWithNoImportOfLocalData() async throws {
        NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        stack.save(stack.context1)
        NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context2)
        stack.save(stack.context2)

        try await stack.ensemble1.attachPersistentStore()
        try await stack.ensemble2.attachPersistentStore(seedPolicy: .excludeLocalData)

        try await stack.syncChanges()

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "DerivedParent")
        var parents = try stack.context2.fetch(fetch)
        #expect(parents.count == 1)

        parents = try stack.context1.fetch(fetch)
        #expect(parents.count == 1)

        // Add more objects
        NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context1)
        stack.save(stack.context1)
        NSEntityDescription.insertNewObject(forEntityName: "DerivedParent", into: stack.context2)
        stack.save(stack.context2)

        try await stack.syncChanges()

        parents = try stack.context2.fetch(fetch)
        #expect(parents.count == 3)
        parents = try stack.context1.fetch(fetch)
        #expect(parents.count == 3)
    }

    @Test("Leaving behind devices in a rebase")
    func leavingBehindDevicesInARebase() async throws {
        try await stack.attachStores()
        try await stack.syncChangesAndSuppressRebase()

        let parentOnDevice1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parentOnDevice1.setValue("bob", forKey: "name")
        stack.save(stack.context1)
        try await stack.syncChanges()

        // Perform multiple rebases to leave device 2 behind
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.rebaseEnsemble(stack.ensemble1)
        try await stack.syncEnsembleAndSuppressRebase(stack.ensemble2)

        // Add object to left-behind device
        let parentOnDevice2 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context2)
        parentOnDevice2.setValue("fred", forKey: "name")
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

        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent1.setValue("1", forKey: "name")
        let parent3 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent3.setValue("3", forKey: "name")
        let parent4 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent4.setValue("4", forKey: "name")
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

        let parent1 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent1.setValue("1", forKey: "name")
        let parent3 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent3.setValue("3", forKey: "name")
        let parent4 = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: stack.context1)
        parent4.setValue("4", forKey: "name")
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
