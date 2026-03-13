import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("Rebaser", .serialized)
struct RebaserTests {

    let setup: TestEventStoreSetup
    let rebaser: Rebaser

    init() throws {
        let s = try TestEventStoreSetup()
        let r = Rebaser(eventStore: s.eventStore, ensemble: nil)
        setup = s
        rebaser = r
    }

    // MARK: - Should Rebase

    @Test("Empty event store does not need rebasing")
    func emptyEventStoreDoesNotNeedRebasing() async {
        let should = await rebaser.shouldRebase()
        #expect(!should)
    }

    @Test("Event store with no baseline does not need rebasing")
    func eventStoreWithNoBaselineDoesNotNeedRebasing() async {
        setup.addEvents(type: .merge, storeId: "123", globalCounts: [0], revisions: [0])
        let should = await rebaser.shouldRebase()
        #expect(!should)
    }

    @Test("Event store with few events does not need rebasing")
    func eventStoreWithFewEventsDoesNotNeedRebasing() async {
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [0], revisions: [0])

        setup.context.performAndWait {
            let baseline = baselines.last!
            let rev = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "123", revisionNumber: 0, in: setup.context)
            baseline.eventRevisionsOfOtherStores = Set([rev])
            try! setup.context.save()
        }

        setup.addEvents(type: .merge, storeId: "123", globalCounts: [1, 2], revisions: [1, 2])

        let should = await rebaser.shouldRebase()
        #expect(!should)
    }

    // MARK: - Rebase

    @Test("Rebasing empty event store does not generate baseline")
    func rebasingEmptyEventStoreDoesNotGenerateBaseline() async throws {
        try await rebaser.rebase()

        setup.context.performAndWait {
            let events = setup.fetchStoreModEvents()
            #expect(events.count == 0)
        }
    }

    @Test("Revisions for rebasing with store not in baseline")
    func revisionsForRebasingWithStoreNotInBaseline() async throws {
        setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [2], revisions: [110])
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [4, 5], revisions: [111, 112])
        setup.addEvents(type: .save, storeId: "123", globalCounts: [3, 4, 5], revisions: [0, 1, 2])

        try await rebaser.rebase()

        setup.context.performAndWait {
            let events = setup.fetchStoreModEvents()
            // Should only clean up one event from storeId. "123" is ignored (not in baseline).
            #expect(events.count == 5)

            let baseline = setup.fetchBaseline()!
            let revSet = baseline.revisionSet
            let revForStore1 = revSet.revision(forPersistentStoreIdentifier: setup.persistentStoreIdentifier)
            let revFor123 = revSet.revision(forPersistentStoreIdentifier: "123")
            #expect(baseline.globalCount == 4)
            #expect(revForStore1?.revisionNumber == 111)
            #expect(revFor123 == nil)
        }
    }

    @Test("Global count of new baseline")
    func globalCountOfNewBaseline() async throws {
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20, 21], revisions: [111, 112])

        setup.context.performAndWait {
            let baseline = baselines.last!
            let rev = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "123", revisionNumber: 1, in: setup.context)
            baseline.eventRevisionsOfOtherStores = Set([rev])
            try! setup.context.save()
        }

        setup.addEvents(type: .save, storeId: "123", globalCounts: [16, 30], revisions: [2, 3])

        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            let baselineGlobalCount = baseline.globalCount
            #expect(baselineGlobalCount > 10)
            #expect(baselineGlobalCount < 30)
        }
    }

    @Test("Deleting redundant events")
    func deletingRedundantEvents() async throws {
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [0], revisions: [10])

        setup.context.performAndWait {
            let baseline = baselines.last!
            let rev = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "123", revisionNumber: 5, in: setup.context)
            baseline.eventRevisionsOfOtherStores = Set([rev])
            try! setup.context.save()
        }

        setup.addEvents(type: .save, storeId: "123", globalCounts: [1, 2, 3, 4], revisions: [3, 4, 5, 6])
        setup.addEvents(type: .merge, storeId: setup.persistentStoreIdentifier, globalCounts: [1, 2, 3, 4], revisions: [9, 10, 11, 12])

        try await rebaser.deleteEventsPrecedingBaseline()

        setup.context.performAndWait {
            let types: [StoreModificationEventType] = [.save, .merge]
            let fetch123 = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            if let pred = StoreModificationEvent.predicate(forAllowedTypes: types, persistentStoreIdentifier: "123") {
                fetch123.predicate = pred
            }
            let events123 = (try? setup.context.fetch(fetch123)) ?? []

            let fetchStore1 = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            if let pred = StoreModificationEvent.predicate(forAllowedTypes: types, persistentStoreIdentifier: setup.persistentStoreIdentifier) {
                fetchStore1.predicate = pred
            }
            let eventsStore1 = (try? setup.context.fetch(fetchStore1)) ?? []

            #expect(events123.count == 1)
            #expect(eventsStore1.count == 2)
        }
    }

    // MARK: - Rebasing Object Changes

    @Test("Rebasing attribute")
    func rebasingAttribute() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        setup.context.performAndWait {
            let baseline = baselines.last!

            let globalId1 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: setup.context) as! GlobalIdentifier
            globalId1.globalIdentifier = "unique"
            globalId1.nameOfEntity = "A"

            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change1.storeModificationEvent = baseline
            change1.objectChangeType = .insert
            change1.nameOfEntity = "A"
            change1.globalIdentifier = globalId1

            let value1 = PropertyChangeValue(type: .attribute, propertyName: "property")
            value1.value = NSNumber(value: 10)
            change1.propertyChangeValues = [value1] as NSArray

            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change2.storeModificationEvent = event1
            change2.objectChangeType = .insert
            change2.nameOfEntity = "A"
            change2.globalIdentifier = globalId1

            let value2 = PropertyChangeValue(type: .attribute, propertyName: "property")
            value2.value = NSNumber(value: 11)
            change2.propertyChangeValues = [value2] as NSArray

            try! setup.context.save()
        }

        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            #expect(baseline.objectChanges.count == 1)

            let values = (baseline.objectChanges.first?.propertyChangeValues as? [PropertyChangeValue]) ?? []
            let value = values.last!
            #expect(value.value as? NSNumber == NSNumber(value: 11))
        }
    }

    @Test("Rebasing attribute with same global ID but different entity")
    func rebasingAttributeWithDifferentEntity() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        setup.context.performAndWait {
            let baseline = baselines.last!

            let globalId1 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: setup.context) as! GlobalIdentifier
            globalId1.globalIdentifier = "unique"
            globalId1.nameOfEntity = "A"

            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change1.storeModificationEvent = baseline
            change1.objectChangeType = .insert
            change1.nameOfEntity = "A"
            change1.globalIdentifier = globalId1

            let value1 = PropertyChangeValue(type: .attribute, propertyName: "property")
            value1.value = NSNumber(value: 10)
            change1.propertyChangeValues = [value1] as NSArray

            let globalId2 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: setup.context) as! GlobalIdentifier
            globalId2.globalIdentifier = "unique"
            globalId2.nameOfEntity = "B"

            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change2.storeModificationEvent = event1
            change2.objectChangeType = .insert
            change2.nameOfEntity = "B"
            change2.globalIdentifier = globalId2

            let value2 = PropertyChangeValue(type: .attribute, propertyName: "property")
            value2.value = NSNumber(value: 11)
            change2.propertyChangeValues = [value2] as NSArray

            try! setup.context.save()
        }

        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            #expect(baseline.objectChanges.count == 2)
        }
    }

    @Test("Rebasing to-many relationship")
    func rebasingToManyRelationship() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [21], revisions: [112])
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [22], revisions: [113])
        let event2 = setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [23], revisions: [114]).last!
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [24], revisions: [115])

        setup.context.performAndWait {
            let baseline = baselines.last!

            let globalId1 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: setup.context) as! GlobalIdentifier
            globalId1.globalIdentifier = "unique"
            globalId1.nameOfEntity = "A"

            // Baseline change
            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change1.storeModificationEvent = baseline
            change1.objectChangeType = .insert
            change1.nameOfEntity = "A"
            change1.globalIdentifier = globalId1

            let value1 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
            value1.addedIdentifiers = Set(["11", "12", "13"] as [AnyHashable])
            value1.removedIdentifiers = Set<AnyHashable>()
            change1.propertyChangeValues = [value1] as NSArray

            // First event change
            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change2.storeModificationEvent = event1
            change2.objectChangeType = .update
            change2.nameOfEntity = "A"
            change2.globalIdentifier = globalId1

            let value2 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
            value2.addedIdentifiers = Set(["21", "22"] as [AnyHashable])
            value2.removedIdentifiers = Set(["11"] as [AnyHashable])
            change2.propertyChangeValues = [value2] as NSArray

            // Second event change
            let change3 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change3.storeModificationEvent = event2
            change3.objectChangeType = .update
            change3.nameOfEntity = "A"
            change3.globalIdentifier = globalId1

            let value3 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
            value3.addedIdentifiers = Set(["11", "33"] as [AnyHashable])
            value3.removedIdentifiers = Set(["12", "22"] as [AnyHashable])
            change3.propertyChangeValues = [value3] as NSArray

            try! setup.context.save()
        }

        // First rebase: events up to globalCount ~20
        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            #expect(baseline.objectChanges.count == 1)

            let change = baseline.objectChanges.first!
            let values = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(values.count == 1)
            #expect(change.objectChangeType == .insert)

            let value = values.last!
            #expect(value.type == .toManyRelationship)

            let expectedAdded: Set<AnyHashable> = Set(["12", "13", "21", "22"])
            #expect(value.addedIdentifiers == expectedAdded)
            #expect(value.removedIdentifiers == Set<AnyHashable>())
        }

        // Second rebase: events up to globalCount ~23
        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            #expect(baseline.objectChanges.count == 1)

            let change = baseline.objectChanges.first!
            let values = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(values.count == 1)
            #expect(change.objectChangeType == .insert)

            let value = values.last!
            #expect(value.type == .toManyRelationship)

            let expectedAdded: Set<AnyHashable> = Set(["11", "13", "21", "33"])
            #expect(value.addedIdentifiers == expectedAdded)
            #expect(value.removedIdentifiers == Set<AnyHashable>())
        }
    }

    @Test("Rebasing ordered to-many relationship")
    func rebasingOrderedToManyRelationship() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        setup.context.performAndWait {
            let baseline = baselines.last!

            let globalId1 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: setup.context) as! GlobalIdentifier
            globalId1.globalIdentifier = "unique"
            globalId1.nameOfEntity = "A"

            // Baseline change
            let change1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change1.storeModificationEvent = baseline
            change1.objectChangeType = .insert
            change1.nameOfEntity = "A"
            change1.globalIdentifier = globalId1

            let value1 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
            value1.addedIdentifiers = Set(["11", "12"] as [AnyHashable])
            value1.removedIdentifiers = Set<AnyHashable>()
            value1.movedIdentifiersByIndex = [0: "11", 1: "12"]
            change1.propertyChangeValues = [value1] as NSArray

            // Event change
            let change2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            change2.storeModificationEvent = event1
            change2.objectChangeType = .update
            change2.nameOfEntity = "A"
            change2.globalIdentifier = globalId1

            let value2 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
            value2.addedIdentifiers = Set(["21", "13"] as [AnyHashable])
            value2.removedIdentifiers = Set(["11", "22"] as [AnyHashable])
            value2.movedIdentifiersByIndex = [0: "21", 1: "13", 2: "17", 3: "666"]
            change2.propertyChangeValues = [value2] as NSArray

            try! setup.context.save()
        }

        try await rebaser.rebase()

        setup.context.performAndWait {
            let baseline = setup.fetchBaseline()!
            #expect(baseline.objectChanges.count == 1)

            let change = baseline.objectChanges.first!
            let values = change.propertyChangeValues as? [PropertyChangeValue] ?? []
            #expect(values.count == 1)
            #expect(change.objectChangeType == .insert)

            let value = values.last!
            #expect(value.type == .orderedToManyRelationship)

            let expectedAdded: Set<AnyHashable> = Set(["12", "21", "13"])
            #expect(value.addedIdentifiers == expectedAdded)
            #expect(value.removedIdentifiers == Set<AnyHashable>())

            let expectedMoved: NSDictionary = [NSNumber(value: 0): "21", NSNumber(value: 1): "12", NSNumber(value: 2): "13"]
            #expect(value.movedIdentifiersByIndex as NSDictionary? == expectedMoved)
        }
    }
}
