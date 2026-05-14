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

    // MARK: - Catastrophic Wipe Guard (beta.12 regression)

    @Test("Full integration with no integrable events must not wipe the store")
    func fullIntegrationWithNoIntegrableEventsDoesNotWipe() async throws {
        // Reproduces the beta.12 E2->E3 migration wipe at the integrator level.
        // When the only baseline is unusable (no `.baseline` event exists, so it is
        // invisible to `fetchBaselineEvent()`), `RevisionManager.integrableEvents`
        // returns an empty set. Combined with `needsFullIntegration`, the integrator
        // would previously run a full integration with zero events, deleting every
        // existing object as "unreferenced". That is never correct: a full
        // integration with nothing to integrate must abort, not wipe.
        let s = try IntegratorTestStack()

        // Populate the store with objects via a normal merge (integrability checks
        // off, matching the rest of this suite's setup).
        s.integrator.performIntegrabilityChecks = false
        try s.addEventsFromJSONFile("DoubleInsertFixture", subdirectory: "Corner Cases")
        try await s.mergeEvents()
        s.testMOC.performAndWait { try! s.testMOC.save() }
        s.testMOC.performAndWait { s.testMOC.reset() }
        #expect(s.fetchParents().count == 1)

        // Now simulate the wipe condition: a baseline that is stuck at
        // `.baselineMissingDependencies` (type 400) so it is invisible to
        // `fetchBaselineEvent()`/`currentBaselineIdentifier`, plus
        // `needsFullIntegration`. `integrableEvents` will reject it and return [].
        let strandedBaseline = try s.eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .baselineMissingDependencies,
            timestamp: 10,
            globalCount: 0,
            modelVersion: "DEFAULT"
        )
        try s.eventStore.insertRevision(
            persistentStoreIdentifier: "remote-store",
            revisionNumber: 0,
            eventId: strandedBaseline.id,
            isEventRevision: true
        )
        s.eventStore.needsFullIntegration = true
        s.integrator.performIntegrabilityChecks = true

        // Merging must not delete the pre-existing objects. It may throw or no-op,
        // but a wipe is unacceptable.
        _ = try? await s.mergeEvents()

        s.testMOC.performAndWait { s.testMOC.reset() }
        #expect(s.fetchParents().count == 1, "Full integration with no integrable events wiped the store")
    }
}
