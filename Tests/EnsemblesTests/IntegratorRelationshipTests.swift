import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventIntegrator Relationships", .serialized)
struct IntegratorRelationshipTests {

    let stack: IntegratorTestStack

    init() async throws {
        let s = try IntegratorTestStack()
        s.integrator.performIntegrabilityChecks = false
        s.addEventsFromJSONFile("BasicIntegratorRelationshipTestsFixture")
        try await s.mergeEvents()
        stack = s
    }

    @Test("Parent inserted")
    func parentInserted() {
        let parents = stack.fetchParents()
        #expect(parents.count == 1)
    }

    @Test("Child inserted")
    func childInserted() {
        let children = stack.fetchChildren()
        #expect(children.count == 1)
    }

    @Test("Parent date attribute is set")
    func parentDateAttributeIsSet() {
        let parents = stack.fetchParents()
        let parent = parents.last!
        stack.testMOC.performAndWait {
            let date = parent.value(forKey: "date") as? Date
            let expected = 58472395723.0
            #expect(abs((date?.timeIntervalSinceReferenceDate ?? 0) - expected) < 0.001)
        }
    }

    @Test("One-to-one relationship is set on parent")
    func oneToOneRelationshipIsSetOnParent() {
        let parents = stack.fetchParents()
        let parent = parents.last!
        stack.testMOC.performAndWait {
            #expect(parent.value(forKey: "child") != nil)
        }
    }

    @Test("Many-to-one relationship is set")
    func manyToOneRelationshipIsSet() {
        let parents = stack.fetchParents()
        let parent = parents.last!
        stack.testMOC.performAndWait {
            let children = parent.value(forKey: "children") as? Set<NSManagedObject>
            #expect(children?.count == 1)
        }
    }

    @Test("One-to-many relationship is set on child")
    func oneToManyRelationshipIsSetOnChild() {
        let children = stack.fetchChildren()
        let child = children.last!
        stack.testMOC.performAndWait {
            #expect(child.value(forKey: "parentWithSiblings") != nil)
        }
    }

    @Test("Children relationship is set on parent")
    func childrenRelationshipIsSetOnParent() {
        let parents = stack.fetchParents()
        let parent = parents.last!
        stack.testMOC.performAndWait {
            let children = parent.value(forKey: "children") as? Set<NSManagedObject>
            #expect(children?.count == 1)
        }
    }

    @Test("Many-to-many relationship is set on parent")
    func manyToManyRelationshipIsSetOnParent() {
        let parents = stack.fetchParents()
        let parent = parents.last!
        stack.testMOC.performAndWait {
            let friends = parent.value(forKey: "friends") as? Set<NSManagedObject>
            #expect(friends?.count == 1)
        }
    }

    @Test("Many-to-many relationship is set on child")
    func manyToManyRelationshipIsSetOnChild() {
        let children = stack.fetchChildren()
        let child = children.last!
        stack.testMOC.performAndWait {
            let testFriends = child.value(forKey: "testFriends") as? Set<NSManagedObject>
            #expect(testFriends?.count == 1)
        }
    }
}
