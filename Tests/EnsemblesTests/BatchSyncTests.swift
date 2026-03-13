import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

extension SyncTests {
@Suite("BatchSync", .serialized)
@MainActor
struct BatchSyncTests {

    let stack: SyncTestStack

    init() {
        stack = SyncTestStack()
    }

    @Test("Single entity")
    func singleEntity() async throws {
        try await stack.attachStores()

        for _ in 0..<101 {
            NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: stack.context1)
        }
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchObjects(entity: "BatchParent", in: stack.context2)
        #expect(parents.count == 101)
    }

    @Test("Related entities")
    func relatedEntities() async throws {
        try await stack.attachStores()

        for _ in 0..<2 {
            let parent = NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: stack.context1)
            for _ in 0..<600 {
                let child = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
                child.setValue(parent, forKey: "batchParent")
            }
        }
        stack.save(stack.context1)

        try await stack.syncChanges()

        let parents = stack.fetchObjects(entity: "BatchParent", in: stack.context2)
        #expect(parents.count == 2)
        #expect((parents.last?.value(forKey: "batchChildren") as? NSSet)?.count == 600)
    }

    @Test("Self-referential relationship")
    func selfReferentialRelationship() async throws {
        try await stack.attachStores()

        for _ in 0..<30 {
            let child1 = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
            let child2 = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
            child1.setValue(child2, forKey: "friend")
            child2.setValue(NSSet(array: [child1, child2]), forKey: "siblings")
        }
        stack.save(stack.context1)

        try await stack.syncChanges()

        let children = stack.fetchObjects(entity: "BatchChild", in: stack.context2)
        #expect(children.count == 60)

        let child = children.last!
        #expect(child.value(forKey: "friend") != nil || (child.value(forKey: "siblings") as? NSSet)?.count ?? 0 > 0)

        let friends = children.compactMap { $0.value(forKey: "friend") as? NSManagedObject }
        #expect(friends.count == 30)
    }

    @Test("Three entities")
    func threeEntities() async throws {
        try await stack.attachStores()

        let parent = NSEntityDescription.insertNewObject(forEntityName: "BatchParent", into: stack.context1)
        let child1 = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
        let child2 = NSEntityDescription.insertNewObject(forEntityName: "BatchChild", into: stack.context1)
        child1.setValue("thing1", forKey: "name")
        child2.setValue("thing2", forKey: "name")
        let grandparent = NSEntityDescription.insertNewObject(forEntityName: "BatchGrandParent", into: stack.context1)

        parent.setValue(NSSet(array: [child1, child2]), forKey: "batchChildren")
        parent.setValue(grandparent, forKey: "batchGrandParent")
        grandparent.setValue(NSSet(object: child1), forKey: "batchChildren")
        stack.save(stack.context1)

        try await stack.syncChanges()

        let children = stack.fetchObjects(entity: "BatchChild", in: stack.context2)
        #expect(children.count == 2)

        let thing1 = children.first { ($0.value(forKey: "name") as? String) == "thing1" }!
        #expect(thing1.value(forKey: "batchParent") != nil)
        #expect((thing1.value(forKey: "batchGrandParents") as? NSSet)?.count == 1)

        let parentInCtx2 = thing1.value(forKey: "batchParent") as! NSManagedObject
        #expect(parentInCtx2.value(forKey: "batchGrandParent") != nil)
        #expect((parentInCtx2.value(forKey: "batchChildren") as? NSSet)?.count == 2)
    }
}
}
