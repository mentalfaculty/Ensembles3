import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("RevisionManager")
struct RevisionManagerTests {

    let setup: TestEventStoreSetup
    let revisionManager: RevisionManager
    let modEvent: StoreModificationEvent
    let storeId: String

    init() throws {
        let s = try TestEventStoreSetup(loadTestModel: true)
        let sid = s.persistentStoreIdentifier
        let rm = RevisionManager(eventStore: s.eventStore)
        if let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd") {
            rm.managedObjectModels = CoreDataEnsemble.loadAllModelVersions(from: modelURL)
        }

        var event = try s.addModEvent(store: sid, revision: 0, globalCount: 99, timestamp: 124)
        try s.eventStore.updateEventType(id: event.id, type: .baseline)
        event.type = .baseline

        setup = s
        storeId = sid
        revisionManager = rm
        modEvent = event
    }

    @Test("Maximum global count")
    func maximumGlobalCount() {
        #expect(revisionManager.maximumGlobalCount() == 99)
    }

    @Test("Maximum global count for multiple events")
    func maximumGlobalCountMultipleEvents() throws {
        try setup.addModEvent(store: "store2", revision: 0, globalCount: 150, timestamp: 124)
        #expect(revisionManager.maximumGlobalCount() == 150)
    }

    @Test("Maximum global count for empty store")
    func maximumGlobalCountEmptyStore() throws {
        try setup.eventStore.deleteEvent(id: modEvent.id)
        #expect(revisionManager.maximumGlobalCount() == -1)
    }

    @Test("Maximum global count for store with baseline")
    func maximumGlobalCountWithBaseline() throws {
        try setup.eventStore.deleteEvent(id: modEvent.id)
        let event = try setup.addModEvent(store: storeId, revision: 5, globalCount: 78, timestamp: 124)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)
        #expect(revisionManager.maximumGlobalCount() == 78)
    }

    @Test("Recent revisions")
    func recentRevisions() throws {
        let event = try setup.addModEvent(store: storeId, revision: 0, globalCount: 99, timestamp: 124)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)
        try setup.eventStore.insertRevision(persistentStoreIdentifier: storeId, revisionNumber: 0, eventId: event.id, isEventRevision: true)
        try setup.eventStore.updateEventType(id: modEvent.id, type: .save)

        let set = revisionManager.revisionSetOfMostRecentIntegrableEvents()
        #expect(set != nil)
        #expect(set!.numberOfRevisions == 1)
        let rev = set!.revision(forPersistentStoreIdentifier: storeId)
        #expect(rev?.revisionNumber == 0)
    }

    @Test("Recent revisions for discontinuous revision")
    func recentRevisionsDiscontinuous() throws {
        // The baseline event already has an event revision from addModEvent.
        // We just need to ensure the revision is set to 0.
        let eventRevision = try setup.eventStore.fetchEventRevision(eventId: modEvent.id)
        if let eventRevision {
            try setup.eventStore.updateRevisionNumber(id: eventRevision.id, revisionNumber: 0)
        }

        let set = revisionManager.revisionSetOfMostRecentIntegrableEvents()
        #expect(set != nil)
        #expect(set!.numberOfRevisions == 1)
        let rev = set!.revision(forPersistentStoreIdentifier: storeId)
        #expect(rev?.revisionNumber == 0)
    }

    @Test("Fetching uncommitted events with only current store event")
    func fetchUncommittedWithOnlyCurrentStore() throws {
        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 0)
    }

    @Test("Fetching uncommitted events with other store baseline")
    func fetchUncommittedWithOtherStoreBaseline() throws {
        let event = try setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)
        try setup.eventStore.updateEventType(id: modEvent.id, type: .save)

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching uncommitted events with other store events")
    func fetchUncommittedWithOtherStoreEvents() throws {
        let event = try setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)
        try setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
        try setup.addModEvent(store: "otherstore", revision: 2, timestamp: 1234)
        try setup.eventStore.updateEventType(id: modEvent.id, type: .save)

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 3)
    }

    @Test("Fetching uncommitted events with discontinuity")
    func fetchUncommittedWithDiscontinuity() throws {
        let event = try setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
        try setup.eventStore.updateEventType(id: event.id, type: .baseline)
        try setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
        try setup.addModEvent(store: "otherstore", revision: 2, timestamp: 1234)
        try setup.addModEvent(store: "otherstore", revision: 4, timestamp: 1234)
        try setup.eventStore.updateEventType(id: modEvent.id, type: .save)

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 4)
    }

    @Test("Fetching uncommitted events with previous merge")
    func fetchUncommittedWithPreviousMerge() throws {
        try setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
        try setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
        // Create a merge event for local store to simulate lastMergeRevisionSaved = 0
        let merge = try setup.addModEvent(store: storeId, revision: 0, timestamp: 1234)
        try setup.eventStore.updateEventType(id: merge.id, type: .merge)

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 2)
    }

    @Test("Fetching no uncommitted events with baseline")
    func fetchNoUncommittedWithBaseline() throws {
        // baseline already exists, no merge events => lastMergeRevisionSaved = -1
        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 0)
    }

    @Test("Fetching uncommitted events with extra store")
    func fetchUncommittedWithExtraStore() throws {
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "abc", revisionNumber: 4, eventId: modEvent.id, isEventRevision: false)
        try setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)
        try setup.addModEvent(store: "abc", revision: 2, timestamp: 1234) // Precedes baseline, so ignored
        try setup.addModEvent(store: "abc", revision: 4, timestamp: 1234) // Equal to baseline, so ignored

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching uncommitted events with baseline and last merge")
    func fetchUncommittedWithBaselineAndLastMerge() throws {
        let eventRevision = try setup.eventStore.fetchEventRevision(eventId: modEvent.id)!
        try setup.eventStore.updateRevisionNumber(id: eventRevision.id, revisionNumber: 4)
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "otherstore", revisionNumber: 2, eventId: modEvent.id, isEventRevision: false)

        let merge = try setup.addModEvent(store: storeId, revision: 5, timestamp: 1234)
        try setup.eventStore.updateEventType(id: merge.id, type: .merge)

        // lastMergeRevisionSaved is now 5 (computed from saved merge event)
        var events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 0)

        try setup.addModEvent(store: storeId, revision: 6, timestamp: 1234)
        events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching concurrent events for multiple events")
    func fetchConcurrentEventsMultiple() throws {
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "abc", revisionNumber: 4, eventId: modEvent.id, isEventRevision: false)
        let event = try setup.addModEvent(store: storeId, revision: 1, timestamp: 1234)
        try setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)
        try setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)

        let events = try revisionManager.fetchStoreModificationEventsConcurrent(with: [event])
        #expect(events.count == 3)
    }

    @Test("Sorting of events")
    func sortingEvents() throws {
        try setup.addModEvent(store: "otherstore", revision: 1, globalCount: 110, timestamp: 1200)
        try setup.addModEvent(store: "thirdstore", revision: 0, globalCount: 100, timestamp: 1234)
        // Create a merge event so lastMergeRevisionSaved = 0
        let merge = try setup.addModEvent(store: storeId, revision: 0, timestamp: 1234)
        try setup.eventStore.updateEventType(id: merge.id, type: .merge)

        let uncommitted = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(uncommitted.count >= 2)
        let events = RevisionManager.sortStoreModificationEvents(uncommitted)
        if events.count >= 2 {
            #expect(events[0].globalCount <= events[1].globalCount)
        }
    }

    @Test("Integrable events with failing integrity")
    func integrableEventsFailingIntegrity() throws {
        let event = try setup.addModEvent(store: storeId, revision: 1, timestamp: 1234)

        let eventMissingFile = try setup.addModEvent(store: storeId, revision: 2, timestamp: 1234)
        try setup.addMissingFile(to: eventMissingFile)

        try setup.addModEvent(store: storeId, revision: 3, timestamp: 1234)

        let result = try revisionManager.integrableEvents(from: [event, eventMissingFile])
        #expect(result.events.count == 1)
    }

    @Test("Integrable events with failing integrity for other store")
    func integrableEventsFailingIntegrity2() throws {
        try setup.addRevisionOfOtherStoreToBaseline("otherStore")

        let event = try setup.addModEvent(store: "otherStore", revision: 1, timestamp: 1234)

        let eventMissingFile = try setup.addModEvent(store: "otherStore", revision: 2, timestamp: 1234)
        try setup.addMissingFile(to: eventMissingFile)

        try setup.addModEvent(store: "otherStore", revision: 3, timestamp: 1234)

        let result = try revisionManager.integrableEvents(from: [event, eventMissingFile])
        #expect(result.events.count == 1)
    }

    @Test("Integrable events with failing integrity corner case")
    func integrableEventsFailingIntegrityCornerCase() throws {
        try setup.addRevisionOfOtherStoreToBaseline("otherStore")

        let eventMissingFile = try setup.addModEvent(store: "otherStore", revision: 1, timestamp: 1234)
        try setup.addMissingFile(to: eventMissingFile)

        let event = try setup.addModEvent(store: "otherStore", revision: 2, timestamp: 1234)
        try setup.addModEvent(store: "otherStore", revision: 3, timestamp: 1234)

        let result = try revisionManager.integrableEvents(from: [event, eventMissingFile])
        #expect(result.events.count == 0)
    }
}
