import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventIntegrator Merge Repair", .serialized)
struct IntegratorMergeRepairTests {

    let stack: IntegratorTestStack

    init() throws {
        let s = try IntegratorTestStack()
        s.integrator.performIntegrabilityChecks = false
        try s.addEventsFromJSONFile("IntegratorMergeTestsFixture")

        // Set up a failedSaveBlock that fixes the validation error
        s.integrator.failedSaveBlock = { context, error, reparationContext in
            let nsError = error as NSError
            var parentID: NSManagedObjectID?
            context.performAndWait {
                parentID = (nsError.userInfo["NSValidationErrorObject"] as? NSManagedObject)?.objectID
            }
            guard let parentID else { return true }

            reparationContext.performAndWait {
                let parent = try? reparationContext.existingObject(with: parentID)
                parent?.setValue(0, forKey: "invalidatingAttribute")
            }
            return true
        }

        stack = s
    }

    @Test("Fails to save due to invalid attribute")
    func failsToSaveDueToInvalidAttribute() async throws {
        nonisolated(unsafe) var failBlockInvoked = false
        nonisolated(unsafe) var failError: NSError?

        stack.integrator.failedSaveBlock = { context, error, reparationContext in
            failBlockInvoked = true
            failError = error as NSError
            return false
        }

        // mergeEvents will throw because the failedSaveBlock returns false
        do {
            try await stack.mergeEvents()
        } catch {
            // Expected
        }

        #expect(failBlockInvoked)
        #expect(failError != nil)
        #expect(failError?.code == NSValidationNumberTooSmallError)
    }

    @Test("Repair in fail leads to successful merge")
    func repairInFailLeadsToSuccessfulMerge() async throws {
        nonisolated(unsafe) var didSave = false
        stack.integrator.didSaveBlock = { context, info in
            didSave = true
        }
        try await stack.mergeEvents()
        #expect(didSave)
    }

    @Test("Merge event includes object changes")
    func mergeEventIncludesObjectChanges() async throws {
        try await stack.mergeEvents()

        let mergeEvents = try stack.eventStore.fetchEvents(types: [.merge], persistentStoreIdentifier: stack.setup.persistentStoreIdentifier)
        let mergeEvent = mergeEvents.last
        #expect(mergeEvent != nil)

        if let mergeEvent {
            let objectChanges = try stack.eventStore.fetchObjectChanges(eventId: mergeEvent.id)
            #expect(objectChanges.count == 1)

            let objectChange = objectChanges.first
            let propertyChanges = objectChange?.propertyChangeValues ?? []
            #expect(propertyChanges.count == 1)

            let propertyChange = propertyChanges.last
            #expect(propertyChange?.propertyName == "invalidatingAttribute")
            #expect(propertyChange?.value == StoredValue.int(0))
        }
    }

    @Test("Repair in will save block avoids fail")
    func repairInWillSaveBlockAvoidsFail() async throws {
        stack.integrator.shouldSaveBlock = { context, reparationContext in
            var parentID: NSManagedObjectID?
            context.performAndWait {
                parentID = context.insertedObjects.first?.objectID
            }
            guard let parentID else { return true }

            reparationContext.performAndWait {
                let repairParent = try? reparationContext.existingObject(with: parentID)
                repairParent?.setValue(0, forKey: "invalidatingAttribute")
            }
            return true
        }

        nonisolated(unsafe) var failBlockInvoked = false
        stack.integrator.failedSaveBlock = { context, error, reparationContext in
            failBlockInvoked = true
            return false
        }

        try await stack.mergeEvents()
        #expect(!failBlockInvoked)
    }

    @Test("Relationship update generates object change")
    func relationshipUpdateGeneratesObjectChange() async throws {
        stack.integrator.shouldSaveBlock = { context, reparationContext in
            var parentID: NSManagedObjectID?
            context.performAndWait {
                parentID = context.insertedObjects.first?.objectID
            }
            guard let parentID else { return true }

            reparationContext.performAndWait {
                let repairParent = try? reparationContext.existingObject(with: parentID)
                repairParent?.setValue(0, forKey: "invalidatingAttribute")

                let child = NSEntityDescription.insertNewObject(forEntityName: "Child", into: reparationContext)
                repairParent?.setValue(child, forKey: "child")
            }
            return true
        }

        try await stack.mergeEvents()

        let mergeEvents = try stack.eventStore.fetchEvents(types: [.merge], persistentStoreIdentifier: stack.setup.persistentStoreIdentifier)
        let mergeEvent = mergeEvents.last

        if let mergeEvent {
            let objectChanges = try stack.eventStore.fetchObjectChanges(eventId: mergeEvent.id)
            #expect(objectChanges.count == 2)

            let childChanges = objectChanges.filter { $0.nameOfEntity == "Child" }
            #expect(childChanges.count == 1)
            #expect(childChanges.first?.type == .insert)
        }
    }
}
