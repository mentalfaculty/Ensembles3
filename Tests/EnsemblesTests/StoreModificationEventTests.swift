import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("StoreModificationEvent")
struct StoreModificationEventTests {

    @Test("Event type round-trips through raw value")
    func eventTypeRoundTrip() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event = stack.addModEvent(store: "store1", revision: 0)
            event.storeModificationEventType = .merge
            #expect(event.storeModificationEventType == .merge)
            #expect(event.type == StoreModificationEventType.merge.rawValue)
        }
    }

    @Test("Revision set includes event revision and other stores")
    func revisionSetIncludesAll() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event = stack.addModEvent(store: "store1", revision: 3, globalCount: 10)
            var otherRevSet = RevisionSet()
            otherRevSet.addRevision(Revision(persistentStoreIdentifier: "store2", revisionNumber: 5, globalCount: 8))
            event.revisionSetOfOtherStoresAtCreation = otherRevSet

            let revSet = event.revisionSet
            #expect(revSet.numberOfRevisions == 2)
            #expect(revSet.revision(forPersistentStoreIdentifier: "store1")?.revisionNumber == 3)
            #expect(revSet.revision(forPersistentStoreIdentifier: "store2")?.revisionNumber == 5)
        }
    }

    @Test("Fetch complete events excludes incomplete events")
    func fetchCompleteEvents() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event1 = stack.addModEvent(store: "store1", revision: 0)
            event1.storeModificationEventType = .save
            let event2 = stack.addModEvent(store: "store1", revision: 1)
            event2.storeModificationEventType = .incomplete
            try! stack.context.save()

            let events = try! StoreModificationEvent.fetchCompleteEvents(in: stack.context)
            #expect(events.count == 1)
            #expect(events.first?.storeModificationEventType == .save)
        }
    }

    @Test("Fetch non-baseline events")
    func fetchNonBaselineEvents() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event1 = stack.addModEvent(store: "store1", revision: 0, globalCount: 1, timestamp: 1)
            event1.storeModificationEventType = .save
            let event2 = stack.addModEvent(store: "store1", revision: 1, globalCount: 2, timestamp: 2)
            event2.storeModificationEventType = .baseline
            try! stack.context.save()

            let events = try! StoreModificationEvent.fetchNonBaselineEvents(in: stack.context)
            #expect(events.count == 1)
            #expect(events.first?.storeModificationEventType == .save)
        }
    }

    @Test("Fetch baseline events")
    func fetchBaselineEvent() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event = stack.addModEvent(store: "store1", revision: 0, globalCount: 1, timestamp: 1)
            event.storeModificationEventType = .baseline
            try! stack.context.save()

            let baseline = try! StoreModificationEvent.fetchBaselineEvent(in: stack.context)
            #expect(baseline != nil)
            #expect(baseline?.storeModificationEventType == .baseline)
        }
    }

    @Test("Set revision set for persistent store identifier")
    func setRevisionSet() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event = stack.addModEvent(store: "store1", revision: 0)
            var newRevSet = RevisionSet()
            newRevSet.addRevision(Revision(persistentStoreIdentifier: "store1", revisionNumber: 5, globalCount: 10))
            newRevSet.addRevision(Revision(persistentStoreIdentifier: "store2", revisionNumber: 3, globalCount: 8))
            event.setRevisionSet(newRevSet, forPersistentStoreIdentifier: "store1")

            let revSet = event.revisionSet
            #expect(revSet.numberOfRevisions == 2)
            #expect(revSet.revision(forPersistentStoreIdentifier: "store1")?.revisionNumber == 5)
            #expect(revSet.revision(forPersistentStoreIdentifier: "store2")?.revisionNumber == 3)
        }
    }
}
