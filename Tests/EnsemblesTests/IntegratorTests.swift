import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventIntegrator", .serialized)
struct IntegratorTests {

    let stack: IntegratorTestStack

    init() throws {
        let s = try IntegratorTestStack()
        s.integrator.performIntegrabilityChecks = false

        // Create events manually (like ObjC setUp)
        let modEvent = try s.setup.addModEvent(store: "store2", revision: 0, timestamp: 123)

        let globalId1 = try s.setup.addGlobalIdentifier("parent1", entity: "Parent")
        let globalId2 = try s.setup.addGlobalIdentifier("child1", entity: "Child")
        let globalId3 = try s.setup.addGlobalIdentifier("parent2", entity: "Parent")

        let dateChangeValue = s.setup.attributeChange(name: "date", value: NSDate(timeIntervalSinceReferenceDate: 0))
        let childChange = s.setup.toOneRelationshipChange(name: "child", relatedIdentifier: globalId2.globalIdentifier)
        let nameChange = s.setup.attributeChange(name: "name", value: "parent1" as NSString)
        try s.setup.addObjectChange(type: .insert, globalIdentifier: globalId1, event: modEvent, propertyChanges: [dateChangeValue, childChange, nameChange].map { $0.toStoredPropertyChange() })

        let parentChange = s.setup.toOneRelationshipChange(name: "parent", relatedIdentifier: globalId1.globalIdentifier)
        try s.setup.addObjectChange(type: .insert, globalIdentifier: globalId2, event: modEvent, propertyChanges: [parentChange.toStoredPropertyChange()])

        let dateChangeValue1 = s.setup.attributeChange(name: "date", value: nil)
        let nameChange1 = s.setup.attributeChange(name: "name", value: "parent2" as NSString)
        try s.setup.addObjectChange(type: .insert, globalIdentifier: globalId3, event: modEvent, propertyChanges: [dateChangeValue1, nameChange1].map { $0.toStoredPropertyChange() })

        stack = s
    }

    @Test("Insert generates objects")
    func insertGeneratesObjects() async throws {
        try await stack.mergeEvents()
        let parents = stack.fetchParents()
        #expect(parents.count == 2)
    }

    @Test("Insert sets attribute")
    func insertSetsAttribute() async throws {
        try await stack.mergeEvents()
        let parent = stack.fetchParent(named: "parent1")
        #expect(parent?.value(forKey: "date") as? Date == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("Insert sets nil attribute")
    func insertSetsNilAttribute() async throws {
        try await stack.mergeEvents()
        let parent = stack.fetchParent(named: "parent2")
        #expect(parent?.value(forKey: "date") == nil)
    }

    @Test("Insert sets relationship")
    func insertSetsRelationship() async throws {
        try await stack.mergeEvents()
        let parent = stack.fetchParent(named: "parent1")
        #expect(parent?.value(forKey: "child") != nil)
    }

    @Test("Merge with no repair generates a store modification event")
    func mergeWithNoRepairGeneratesEvent() async throws {
        try await stack.mergeEvents()
        let mergeCount = try stack.eventStore.countEvents(type: .merge)
        #expect(mergeCount == 1)
    }

    @Test("Merge with repair generates store modification event")
    func mergeWithRepairGeneratesEvent() async throws {
        stack.integrator.shouldSaveBlock = { savingContext, reparationContext in
            savingContext.performAndWait {
                NSEntityDescription.insertNewObject(forEntityName: "Parent", into: savingContext)
            }
            return true
        }

        try await stack.mergeEvents()

        let mergeEvents = try stack.eventStore.fetchEvents(types: [.merge], persistentStoreIdentifier: nil)
        #expect(mergeEvents.count == 1)

        let merge = mergeEvents.last!
        #expect(merge.globalCount == 1)
        let eventRevision = try stack.eventStore.fetchEventRevision(eventId: merge.id)
        #expect(eventRevision?.revisionNumber == 0)
    }
}
