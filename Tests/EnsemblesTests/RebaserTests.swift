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
    func emptyEventStoreDoesNotNeedRebasing() throws {
        let should = try rebaser.shouldRebase()
        #expect(!should)
    }

    @Test("Event store with no baseline does not need rebasing")
    func eventStoreWithNoBaselineDoesNotNeedRebasing() throws {
        try setup.addEvents(type: .merge, storeId: "123", globalCounts: [0], revisions: [0])
        let should = try rebaser.shouldRebase()
        #expect(!should)
    }

    @Test("Event store with few events does not need rebasing")
    func eventStoreWithFewEventsDoesNotNeedRebasing() async throws {
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [0], revisions: [0])

        let baseline = baselines.last!
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "123", revisionNumber: 0, eventId: baseline.id, isEventRevision: false)

        try setup.addEvents(type: .merge, storeId: "123", globalCounts: [1, 2], revisions: [1, 2])

        let should = try rebaser.shouldRebase()
        #expect(!should)
    }

    // MARK: - Rebase

    @Test("Rebasing empty event store does not generate baseline")
    func rebasingEmptyEventStoreDoesNotGenerateBaseline() async throws {
        try rebaser.rebase()

        let events = try setup.fetchStoreModEvents()
        #expect(events.count == 0)
    }

    @Test("Revisions for rebasing with store not in baseline")
    func revisionsForRebasingWithStoreNotInBaseline() async throws {
        try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [2], revisions: [110])
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [4, 5], revisions: [111, 112])
        try setup.addEvents(type: .save, storeId: "123", globalCounts: [3, 4, 5], revisions: [0, 1, 2])

        try rebaser.rebase()

        let events = try setup.fetchStoreModEvents()
        // Should only clean up one event from storeId. "123" is ignored (not in baseline).
        #expect(events.count == 5)

        let baseline = try setup.fetchBaseline()!
        let revSet = try setup.eventStore.revisionSet(forEventId: baseline.id)
        let revForStore1 = revSet.revision(forPersistentStoreIdentifier: setup.persistentStoreIdentifier)
        let revFor123 = revSet.revision(forPersistentStoreIdentifier: "123")
        #expect(baseline.globalCount == 4)
        #expect(revForStore1?.revisionNumber == 111)
        #expect(revFor123 == nil)
    }

    @Test("Global count of new baseline")
    func globalCountOfNewBaseline() async throws {
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20, 21], revisions: [111, 112])

        let baseline = baselines.last!
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "123", revisionNumber: 1, eventId: baseline.id, isEventRevision: false)

        try setup.addEvents(type: .save, storeId: "123", globalCounts: [16, 30], revisions: [2, 3])

        try rebaser.rebase()

        let rebasedBaseline = try setup.fetchBaseline()!
        let baselineGlobalCount = rebasedBaseline.globalCount
        #expect(baselineGlobalCount > 10)
        #expect(baselineGlobalCount < 30)
    }

    @Test("Deleting redundant events")
    func deletingRedundantEvents() async throws {
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [0], revisions: [10])

        let baseline = baselines.last!
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "123", revisionNumber: 5, eventId: baseline.id, isEventRevision: false)

        try setup.addEvents(type: .save, storeId: "123", globalCounts: [1, 2, 3, 4], revisions: [3, 4, 5, 6])
        try setup.addEvents(type: .merge, storeId: setup.persistentStoreIdentifier, globalCounts: [1, 2, 3, 4], revisions: [9, 10, 11, 12])

        try rebaser.deleteEventsPrecedingBaseline()

        let types: [StoreModificationEventType] = [.save, .merge]
        let events123 = try setup.eventStore.fetchEvents(types: types, persistentStoreIdentifier: "123")
        let eventsStore1 = try setup.eventStore.fetchEvents(types: types, persistentStoreIdentifier: setup.persistentStoreIdentifier)

        #expect(events123.count == 1)
        #expect(eventsStore1.count == 2)
    }

    // MARK: - Rebasing Object Changes

    @Test("Rebasing attribute")
    func rebasingAttribute() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        let baseline = baselines.last!

        let globalId1 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "unique", nameOfEntity: "A")

        let value1 = PropertyChangeValue(type: .attribute, propertyName: "property")
        value1.value = NSNumber(value: 10)
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "A", eventId: baseline.id, globalIdentifierId: globalId1.id, propertyChanges: [value1.toStoredPropertyChange()])

        let value2 = PropertyChangeValue(type: .attribute, propertyName: "property")
        value2.value = NSNumber(value: 11)
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "A", eventId: event1.id, globalIdentifierId: globalId1.id, propertyChanges: [value2.toStoredPropertyChange()])

        try rebaser.rebase()

        let rebasedBaseline = try setup.fetchBaseline()!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: rebasedBaseline.id)
        #expect(changes.count == 1)

        let values = changes.first?.propertyChangeValues ?? []
        let value = values.last!
        #expect(value.value == StoredValue.int(11))
    }

    @Test("Rebasing attribute with same global ID but different entity")
    func rebasingAttributeWithDifferentEntity() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        let baseline = baselines.last!

        let globalId1 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "unique", nameOfEntity: "A")

        let value1 = PropertyChangeValue(type: .attribute, propertyName: "property")
        value1.value = NSNumber(value: 10)
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "A", eventId: baseline.id, globalIdentifierId: globalId1.id, propertyChanges: [value1.toStoredPropertyChange()])

        let globalId2 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "unique", nameOfEntity: "B")

        let value2 = PropertyChangeValue(type: .attribute, propertyName: "property")
        value2.value = NSNumber(value: 11)
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "B", eventId: event1.id, globalIdentifierId: globalId2.id, propertyChanges: [value2.toStoredPropertyChange()])

        try rebaser.rebase()

        let rebasedBaseline = try setup.fetchBaseline()!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: rebasedBaseline.id)
        #expect(changes.count == 2)
    }

    @Test("Rebasing to-many relationship")
    func rebasingToManyRelationship() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [21], revisions: [112])
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [22], revisions: [113])
        let event2 = try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [23], revisions: [114]).last!
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [24], revisions: [115])

        let baseline = baselines.last!

        let globalId1 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "unique", nameOfEntity: "A")

        // Baseline change
        let value1 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
        value1.addedIdentifiers = Set(["11", "12", "13"] as [AnyHashable])
        value1.removedIdentifiers = Set<AnyHashable>()
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "A", eventId: baseline.id, globalIdentifierId: globalId1.id, propertyChanges: [value1.toStoredPropertyChange()])

        // First event change
        let value2 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
        value2.addedIdentifiers = Set(["21", "22"] as [AnyHashable])
        value2.removedIdentifiers = Set(["11"] as [AnyHashable])
        try setup.eventStore.insertObjectChange(type: .update, nameOfEntity: "A", eventId: event1.id, globalIdentifierId: globalId1.id, propertyChanges: [value2.toStoredPropertyChange()])

        // Second event change
        let value3 = PropertyChangeValue(type: .toManyRelationship, propertyName: "property")
        value3.addedIdentifiers = Set(["11", "33"] as [AnyHashable])
        value3.removedIdentifiers = Set(["12", "22"] as [AnyHashable])
        try setup.eventStore.insertObjectChange(type: .update, nameOfEntity: "A", eventId: event2.id, globalIdentifierId: globalId1.id, propertyChanges: [value3.toStoredPropertyChange()])

        // First rebase: events up to globalCount ~20
        try rebaser.rebase()

        let rebasedBaseline1 = try setup.fetchBaseline()!
        let changes1 = try setup.eventStore.fetchObjectChanges(eventId: rebasedBaseline1.id)
        #expect(changes1.count == 1)

        let change1 = changes1.first!
        let values1 = change1.propertyChangeValues ?? []
        #expect(values1.count == 1)
        #expect(change1.type == .insert)

        let v1 = values1.last!
        #expect(v1.type == PropertyChangeType.toManyRelationship.rawValue)

        let expectedAdded1 = Set(["12", "13", "21", "22"])
        #expect(Set(v1.addedIdentifiers ?? []) == expectedAdded1)
        #expect(Set(v1.removedIdentifiers ?? []).isEmpty)

        // Second rebase: events up to globalCount ~23
        try rebaser.rebase()

        let rebasedBaseline2 = try setup.fetchBaseline()!
        let changes2 = try setup.eventStore.fetchObjectChanges(eventId: rebasedBaseline2.id)
        #expect(changes2.count == 1)

        let change2 = changes2.first!
        let values2 = change2.propertyChangeValues ?? []
        #expect(values2.count == 1)
        #expect(change2.type == .insert)

        let v2 = values2.last!
        #expect(v2.type == PropertyChangeType.toManyRelationship.rawValue)

        let expectedAdded2 = Set(["11", "13", "21", "33"])
        #expect(Set(v2.addedIdentifiers ?? []) == expectedAdded2)
        #expect(Set(v2.removedIdentifiers ?? []).isEmpty)
    }

    @Test("Rebasing ordered to-many relationship")
    func rebasingOrderedToManyRelationship() async throws {
        PropertyChangeValue.registerTransformer()
        let baselines = try setup.addEvents(type: .baseline, storeId: setup.persistentStoreIdentifier, globalCounts: [10], revisions: [110])
        let event1 = try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [20], revisions: [111]).last!
        try setup.addEvents(type: .save, storeId: setup.persistentStoreIdentifier, globalCounts: [25], revisions: [112])

        let baseline = baselines.last!

        let globalId1 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "unique", nameOfEntity: "A")

        // Baseline change
        let value1 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
        value1.addedIdentifiers = Set(["11", "12"] as [AnyHashable])
        value1.removedIdentifiers = Set<AnyHashable>()
        value1.movedIdentifiersByIndex = [0: "11", 1: "12"]
        try setup.eventStore.insertObjectChange(type: .insert, nameOfEntity: "A", eventId: baseline.id, globalIdentifierId: globalId1.id, propertyChanges: [value1.toStoredPropertyChange()])

        // Event change
        let value2 = PropertyChangeValue(type: .orderedToManyRelationship, propertyName: "property")
        value2.addedIdentifiers = Set(["21", "13"] as [AnyHashable])
        value2.removedIdentifiers = Set(["11", "22"] as [AnyHashable])
        value2.movedIdentifiersByIndex = [0: "21", 1: "13", 2: "17", 3: "666"]
        try setup.eventStore.insertObjectChange(type: .update, nameOfEntity: "A", eventId: event1.id, globalIdentifierId: globalId1.id, propertyChanges: [value2.toStoredPropertyChange()])

        try rebaser.rebase()

        let rebasedBaseline = try setup.fetchBaseline()!
        let changes = try setup.eventStore.fetchObjectChanges(eventId: rebasedBaseline.id)
        #expect(changes.count == 1)

        let change = changes.first!
        let values = change.propertyChangeValues ?? []
        #expect(values.count == 1)
        #expect(change.type == .insert)

        let value = values.last!
        #expect(value.type == PropertyChangeType.orderedToManyRelationship.rawValue)

        let expectedAdded = Set(["12", "21", "13"])
        #expect(Set(value.addedIdentifiers ?? []) == expectedAdded)
        #expect(Set(value.removedIdentifiers ?? []).isEmpty)

        let expectedMoved: [String: String] = ["0": "21", "1": "12", "2": "13"]
        #expect(value.movedIdentifiersByIndex == expectedMoved)
    }
}
