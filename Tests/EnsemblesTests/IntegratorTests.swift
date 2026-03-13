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
        s.eventMOC.performAndWait {
            let modEvent = s.setup.addModEvent(store: "store2", revision: 0, timestamp: 123)

            let globalId1 = s.setup.addGlobalIdentifier("parent1", entity: "Parent")
            let globalId2 = s.setup.addGlobalIdentifier("child1", entity: "Child")
            let globalId3 = s.setup.addGlobalIdentifier("parent2", entity: "Parent")

            let objectChange1 = s.setup.addObjectChange(type: .insert, globalIdentifier: globalId1, event: modEvent)
            let dateChangeValue = s.setup.attributeChange(name: "date", value: NSDate(timeIntervalSinceReferenceDate: 0))
            let childChange = s.setup.toOneRelationshipChange(name: "child", relatedIdentifier: globalId2.globalIdentifier)
            let nameChange = s.setup.attributeChange(name: "name", value: "parent1" as NSString)
            objectChange1.propertyChangeValues = [dateChangeValue, childChange, nameChange] as NSArray

            let objectChange2 = s.setup.addObjectChange(type: .insert, globalIdentifier: globalId2, event: modEvent)
            let parentChange = s.setup.toOneRelationshipChange(name: "parent", relatedIdentifier: globalId1.globalIdentifier)
            objectChange2.propertyChangeValues = [parentChange] as NSArray

            let objectChange3 = s.setup.addObjectChange(type: .insert, globalIdentifier: globalId3, event: modEvent)
            let dateChangeValue1 = s.setup.attributeChange(name: "date", value: nil)
            let nameChange1 = s.setup.attributeChange(name: "name", value: "parent2" as NSString)
            objectChange3.propertyChangeValues = [dateChangeValue1, nameChange1] as NSArray

            try! s.eventMOC.save()
        }

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
        let parents = stack.fetchParents()
        let parent = parents.first { ($0.value(forKey: "name") as? String) == "parent1" }
        #expect(parent?.value(forKey: "date") as? Date == Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("Insert sets nil attribute")
    func insertSetsNilAttribute() async throws {
        try await stack.mergeEvents()
        let parents = stack.fetchParents()
        let parent = parents.first { ($0.value(forKey: "name") as? String) == "parent2" }
        #expect(parent?.value(forKey: "date") == nil)
    }

    @Test("Insert sets relationship")
    func insertSetsRelationship() async throws {
        try await stack.mergeEvents()
        let parents = stack.fetchParents()
        let parent = parents.first { ($0.value(forKey: "name") as? String) == "parent1" }
        #expect(parent?.value(forKey: "child") != nil)
    }

    @Test("Merge with no repair generates a store modification event")
    func mergeWithNoRepairGeneratesEvent() async throws {
        try await stack.mergeEvents()
        stack.eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            fetch.predicate = NSPredicate(format: "type = %d", StoreModificationEventType.merge.rawValue)
            let count = (try? stack.eventMOC.count(for: fetch)) ?? -1
            #expect(count == 1)
        }
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

        stack.eventMOC.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            fetch.predicate = NSPredicate(format: "type = %d", StoreModificationEventType.merge.rawValue)
            let events = (try? stack.eventMOC.fetch(fetch)) ?? []
            #expect(events.count == 1)

            let merge = events.last!
            #expect(merge.globalCount == 1)
            #expect(merge.eventRevision?.revisionNumber == 0)
        }
    }
}
