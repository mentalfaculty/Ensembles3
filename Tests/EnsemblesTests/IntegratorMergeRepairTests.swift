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
        s.addEventsFromJSONFile("IntegratorMergeTestsFixture")

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

        stack.eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            fetch.predicate = NSPredicate(format: "type = %d AND eventRevision.persistentStoreIdentifier = %@",
                                          StoreModificationEventType.merge.rawValue,
                                          stack.setup.persistentStoreIdentifier)
            let events = (try? stack.eventMOC.fetch(fetch)) ?? []
            let mergeEvent = events.last
            #expect(mergeEvent != nil)
            #expect(mergeEvent?.objectChanges.count == 1)

            let objectChange = mergeEvent?.objectChanges.first
            let propertyChanges = objectChange?.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(propertyChanges.count == 1)

            let propertyChange = propertyChanges.last
            #expect(propertyChange?.propertyName == "invalidatingAttribute")
            #expect(propertyChange?.value as? NSNumber == NSNumber(value: 0))
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

        stack.eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            fetch.predicate = NSPredicate(format: "type = %d AND eventRevision.persistentStoreIdentifier = %@",
                                          StoreModificationEventType.merge.rawValue,
                                          stack.setup.persistentStoreIdentifier)
            let events = (try? stack.eventMOC.fetch(fetch)) ?? []
            let mergeEvent = events.last

            let objectChanges = mergeEvent?.objectChanges ?? []
            #expect(objectChanges.count == 2)

            let childChanges = objectChanges.filter { $0.nameOfEntity == "Child" }
            #expect(childChanges.count == 1)
            #expect(childChanges.first?.objectChangeType == .insert)
        }
    }
}
