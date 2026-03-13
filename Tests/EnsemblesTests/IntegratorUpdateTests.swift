import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventIntegrator Updates", .serialized)
@MainActor
struct IntegratorUpdateTests {

    let stack: IntegratorTestStack
    let parent1: NSManagedObject?
    let child1: NSManagedObject?
    let child2: NSManagedObject?
    let child3: NSManagedObject?

    init() async throws {
        let s = try IntegratorTestStack()
        s.integrator.performIntegrabilityChecks = false

        // Load first fixture and merge
        s.addEventsFromJSONFile("IntegratorUpdateTestsFixture1")
        try await s.mergeEvents()
        s.testMOC.performAndWait { try! s.testMOC.save() }
        s.testMOC.performAndWait { s.testMOC.reset() }

        // Load second fixture and merge
        s.addEventsFromJSONFile("IntegratorUpdateTestsFixture2")
        try await s.mergeEvents()
        s.testMOC.performAndWait { try! s.testMOC.save() }
        s.testMOC.performAndWait { s.testMOC.reset() }

        stack = s

        // Fetch results
        let parents = s.fetchParents()
        parent1 = parents.last

        let children = s.fetchChildren()
        child1 = children.first { ($0.value(forKey: "name") as? String) == "child1" }
        child2 = children.first { ($0.value(forKey: "name") as? String) == "child2" }
        child3 = children.first { ($0.value(forKey: "name") as? String) == "child3" }
    }

    @Test("One-to-one relationship updated to nil")
    func oneToOneRelationshipUpdatedToNil() {
        #expect(parent1 != nil)
        #expect(child1 != nil)
        stack.testMOC.performAndWait {
            #expect(parent1?.value(forKey: "child") == nil)
            #expect(child1?.value(forKey: "parent") == nil)
        }
    }

    @Test("One-to-many relationship updated")
    func oneToManyRelationshipUpdated() {
        stack.testMOC.performAndWait {
            let children = parent1?.value(forKey: "children") as? Set<NSManagedObject>
            #expect(children?.count == 1)
            #expect(children?.first === child2)
            #expect(child2?.value(forKey: "parentWithSiblings") != nil)
            #expect(child1?.value(forKey: "parentWithSiblings") == nil)
        }
    }

    @Test("Many-to-many relationships updated")
    func manyToManyRelationshipsUpdated() {
        stack.testMOC.performAndWait {
            let friends = parent1?.value(forKey: "friends") as? Set<NSManagedObject>
            #expect(friends?.count == 2)
            let child2Friends = child2?.value(forKey: "testFriends") as? Set<NSManagedObject>
            #expect(child2Friends?.count == 1)
            let child1Friends = child1?.value(forKey: "testFriends") as? Set<NSManagedObject>
            #expect(child1Friends?.count == 1)
        }
    }

    @Test("Deletions")
    func deletions() {
        #expect(child3 == nil)
    }
}
