import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventIntegrator Corner Cases", .serialized)
struct IntegratorCornerCaseTests {

    let stack: IntegratorTestStack

    init() throws {
        let s = try IntegratorTestStack()
        s.integrator.performIntegrabilityChecks = false
        stack = s
    }

    private func addEventsAndMerge(_ filename: String) async throws {
        try stack.addEventsFromJSONFile(filename, subdirectory: "Corner Cases")
        try await stack.mergeEvents()
    }

    @Test("Double insert")
    func doubleInsert() async throws {
        try await addEventsAndMerge("DoubleInsertFixture")
        let parents = stack.fetchParents()
        #expect(parents.count == 1)
        stack.testMOC.performAndWait {
            let parent = parents.last!
            let date = parent.value(forKey: "date") as? Date
            #expect(date?.timeIntervalSinceReferenceDate == 20.0)
        }
    }

    @Test("Update following deletion")
    func updateFollowingDeletion() async throws {
        try await addEventsAndMerge("UpdateFollowingDeletion")
        let parents = stack.fetchParents()
        #expect(parents.count == 0)
    }

    @Test("Insert following deletion")
    func insertFollowingDeletion() async throws {
        try await addEventsAndMerge("InsertFollowingDeletion")
        let parents = stack.fetchParents()
        #expect(parents.count == 1)
    }

    @Test("Update concurrent with insert")
    func updateConcurrentWithInsert() async throws {
        try await addEventsAndMerge("UpdateConcurrentWithInsert")
        let parents = stack.fetchParents()
        #expect(parents.count == 1)
        stack.testMOC.performAndWait {
            let parent = parents.last!
            let date = parent.value(forKey: "date") as? Date
            #expect(date?.timeIntervalSinceReferenceDate == 10.0)
        }
    }

    @Test("Update to uninserted")
    func updateToUninserted() async throws {
        try await addEventsAndMerge("UpdateToUninserted")
        let parents = stack.fetchParents()
        #expect(parents.count == 0)
    }

    @Test("Delete uninserted")
    func deleteUninserted() async throws {
        try await addEventsAndMerge("DeleteUninserted")
        let parents = stack.fetchParents()
        #expect(parents.count == 0)
    }

    @Test("Update relationship concurrently")
    func updateRelationshipConcurrently() async throws {
        try await addEventsAndMerge("UpdateRelationshipConcurrently")
        let parents = stack.fetchParents()
        #expect(parents.count == 1)
        stack.testMOC.performAndWait {
            let parent = parents.last!
            let friends = parent.value(forKey: "friends") as? Set<NSManagedObject>
            #expect(friends?.count == 1)
        }
    }

    @Test("Update relationship concurrent with deletion")
    func updateRelationshipConcurrentWithDeletion() async throws {
        try await addEventsAndMerge("UpdateRelationshipConcurrentWithDeletion")
        let parents = stack.fetchParents()
        #expect(parents.count == 0)

        let children = stack.fetchChildren()
        #expect(children.count == 1)
        stack.testMOC.performAndWait {
            let child = children.last!
            let testFriends = child.value(forKey: "testFriends") as? Set<NSManagedObject>
            #expect(testFriends?.count == 0)
        }
    }
}
