import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("StoreModificationEvent")
struct StoreModificationEventTests {

    @Test("Event type round-trips through raw value")
    func eventTypeRoundTrip() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 0)
        #expect(event.type == .save)
        try setup.eventStore.updateEventType(id: event.id, type: .merge)
        let fetched = try setup.eventStore.fetchEvent(id: event.id)!
        #expect(fetched.type == .merge)
    }

    @Test("Revision set includes event revision and other stores")
    func revisionSetIncludesAll() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 3, globalCount: 10)
        var otherRevSet = RevisionSet()
        otherRevSet.addRevision(Revision(persistentStoreIdentifier: "store2", revisionNumber: 5, globalCount: 8))
        try setup.eventStore.setRevisionSetOfOtherStores(otherRevSet, forEventId: event.id)

        let revSet = try setup.eventStore.revisionSet(forEventId: event.id)
        #expect(revSet.numberOfRevisions == 2)
        #expect(revSet.revision(forPersistentStoreIdentifier: "store1")?.revisionNumber == 3)
        #expect(revSet.revision(forPersistentStoreIdentifier: "store2")?.revisionNumber == 5)
    }

    @Test("Fetch complete events excludes incomplete events")
    func fetchCompleteEvents() throws {
        let setup = try TestEventStoreSetup()
        let event1 = try setup.addModEvent(store: "store1", revision: 0)
        try setup.eventStore.updateEventType(id: event1.id, type: .save)
        let event2 = try setup.addModEvent(store: "store1", revision: 1)
        try setup.eventStore.updateEventType(id: event2.id, type: .incomplete)

        let events = try setup.eventStore.fetchCompleteEvents()
        #expect(events.count == 1)
        #expect(events.first?.type == .save)
    }

    @Test("Fetch non-baseline events")
    func fetchNonBaselineEvents() throws {
        let setup = try TestEventStoreSetup()
        let event1 = try setup.addModEvent(store: "store1", revision: 0, globalCount: 1, timestamp: 1)
        try setup.eventStore.updateEventType(id: event1.id, type: .save)
        let event2 = try setup.addModEvent(store: "store1", revision: 1, globalCount: 2, timestamp: 2)
        try setup.eventStore.updateEventType(id: event2.id, type: .baseline)

        let events = try setup.eventStore.fetchNonBaselineEvents()
        #expect(events.count == 1)
        #expect(events.first?.type == .save)
    }

    @Test("Fetch baseline events")
    func fetchBaselineEvent() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 0, globalCount: 1, timestamp: 1)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)

        let baseline = try setup.eventStore.fetchBaselineEvent()
        #expect(baseline != nil)
        #expect(baseline?.type == .baseline)
    }

    @Test("Set revision set for persistent store identifier")
    func setRevisionSet() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 0)
        var newRevSet = RevisionSet()
        newRevSet.addRevision(Revision(persistentStoreIdentifier: "store1", revisionNumber: 5, globalCount: 10))
        newRevSet.addRevision(Revision(persistentStoreIdentifier: "store2", revisionNumber: 3, globalCount: 8))
        try setup.eventStore.setRevisionSet(newRevSet, forEventId: event.id, eventStoreIdentifier: "store1")

        let revSet = try setup.eventStore.revisionSet(forEventId: event.id)
        #expect(revSet.numberOfRevisions == 2)
        #expect(revSet.revision(forPersistentStoreIdentifier: "store1")?.revisionNumber == 5)
        #expect(revSet.revision(forPersistentStoreIdentifier: "store2")?.revisionNumber == 3)
    }
}
