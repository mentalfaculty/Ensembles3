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

        nonisolated(unsafe) var event: StoreModificationEvent!
        s.context.performAndWait {
            event = s.addModEvent(store: sid, revision: 0, globalCount: 99, timestamp: 124)
            event.storeModificationEventType = .baseline
        }

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
    func maximumGlobalCountMultipleEvents() {
        setup.context.performAndWait {
            _ = setup.addModEvent(store: "store2", revision: 0, globalCount: 150, timestamp: 124)
        }
        #expect(revisionManager.maximumGlobalCount() == 150)
    }

    @Test("Maximum global count for empty store")
    func maximumGlobalCountEmptyStore() {
        setup.context.performAndWait {
            setup.context.delete(modEvent)
        }
        #expect(revisionManager.maximumGlobalCount() == -1)
    }

    @Test("Maximum global count for store with baseline")
    func maximumGlobalCountWithBaseline() {
        setup.context.performAndWait {
            setup.context.delete(modEvent)
            let event = setup.addModEvent(store: storeId, revision: 5, globalCount: 78, timestamp: 124)
            event.storeModificationEventType = .baseline
        }
        #expect(revisionManager.maximumGlobalCount() == 78)
    }

    @Test("Recent revisions")
    func recentRevisions() {
        setup.context.performAndWait {
            let event = setup.addModEvent(store: storeId, revision: 0, globalCount: 99, timestamp: 124)
            event.storeModificationEventType = .baseline
            event.eventRevision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: storeId, revisionNumber: 0, in: setup.context)
            modEvent.storeModificationEventType = .save
            setup.context.processPendingChanges()
        }

        let set = revisionManager.revisionSetOfMostRecentIntegrableEvents()
        #expect(set != nil)
        #expect(set!.numberOfRevisions == 1)
        let rev = set!.revision(forPersistentStoreIdentifier: storeId)
        #expect(rev?.revisionNumber == 0)
    }

    @Test("Recent revisions for discontinuous revision")
    func recentRevisionsDiscontinuous() {
        setup.context.performAndWait {
            let eventRevision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: storeId, revisionNumber: 0, in: setup.context)
            modEvent.eventRevision = eventRevision
            setup.context.processPendingChanges()
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
        setup.context.performAndWait {
            let event = setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
            event.storeModificationEventType = .baseline
            modEvent.storeModificationEventType = .save
        }

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching uncommitted events with other store events")
    func fetchUncommittedWithOtherStoreEvents() throws {
        setup.context.performAndWait {
            let event = setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
            event.storeModificationEventType = .baseline
            _ = setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
            _ = setup.addModEvent(store: "otherstore", revision: 2, timestamp: 1234)
            modEvent.storeModificationEventType = .save
        }

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 3)
    }

    @Test("Fetching uncommitted events with discontinuity")
    func fetchUncommittedWithDiscontinuity() throws {
        setup.context.performAndWait {
            let event = setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
            event.storeModificationEventType = .baseline
            _ = setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
            _ = setup.addModEvent(store: "otherstore", revision: 2, timestamp: 1234)
            _ = setup.addModEvent(store: "otherstore", revision: 4, timestamp: 1234)
            modEvent.storeModificationEventType = .save
        }

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 4)
    }

    @Test("Fetching uncommitted events with previous merge")
    func fetchUncommittedWithPreviousMerge() throws {
        setup.context.performAndWait {
            _ = setup.addModEvent(store: "otherstore", revision: 0, timestamp: 1234)
            _ = setup.addModEvent(store: "otherstore", revision: 1, timestamp: 1234)
            // Create a merge event for local store to simulate lastMergeRevisionSaved = 0
            let merge = setup.addModEvent(store: storeId, revision: 0, timestamp: 1234)
            merge.storeModificationEventType = .merge
            // Give the merge event knowledge of otherstore up to revision -1 (i.e., no knowledge)
        }

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
        setup.context.performAndWait {
            modEvent.eventRevisionsOfOtherStores = Set([setup.addEventRevision(store: "abc", revision: 4)])
            _ = setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)
            _ = setup.addModEvent(store: "abc", revision: 2, timestamp: 1234) // Precedes baseline, so ignored
            _ = setup.addModEvent(store: "abc", revision: 4, timestamp: 1234) // Equal to baseline, so ignored
        }

        let events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching uncommitted events with baseline and last merge")
    func fetchUncommittedWithBaselineAndLastMerge() throws {
        setup.context.performAndWait {
            modEvent.eventRevision?.revisionNumber = 4
            modEvent.eventRevisionsOfOtherStores = Set([setup.addEventRevision(store: "otherstore", revision: 2)])

            let merge = setup.addModEvent(store: storeId, revision: 5, timestamp: 1234)
            merge.storeModificationEventType = .merge
            try? setup.context.save()
        }

        // lastMergeRevisionSaved is now 5 (computed from saved merge event)
        var events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 0)

        setup.context.performAndWait {
            _ = setup.addModEvent(store: storeId, revision: 6, timestamp: 1234)
            try? setup.context.save()
        }
        events = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(events.count == 1)
    }

    @Test("Fetching concurrent events for multiple events")
    func fetchConcurrentEventsMultiple() throws {
        nonisolated(unsafe) var event: StoreModificationEvent!
        setup.context.performAndWait {
            modEvent.eventRevisionsOfOtherStores = Set([setup.addEventRevision(store: "abc", revision: 4)])
            event = setup.addModEvent(store: storeId, revision: 1, timestamp: 1234)
            _ = setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)
            _ = setup.addModEvent(store: "abc", revision: 5, timestamp: 1234)
        }

        let events = try revisionManager.fetchStoreModificationEventsConcurrent(with: [event])
        #expect(events.count == 3)
    }

    @Test("Sorting of events")
    func sortingEvents() throws {
        setup.context.performAndWait {
            _ = setup.addModEvent(store: "otherstore", revision: 1, globalCount: 110, timestamp: 1200)
            _ = setup.addModEvent(store: "thirdstore", revision: 0, globalCount: 100, timestamp: 1234)
            // Create a merge event so lastMergeRevisionSaved = 0
            let merge = setup.addModEvent(store: storeId, revision: 0, timestamp: 1234)
            merge.storeModificationEventType = .merge
        }

        let uncommitted = try revisionManager.fetchUncommittedStoreModificationEvents()
        #expect(uncommitted.count >= 2)
        let events = RevisionManager.sortStoreModificationEvents(uncommitted)
        if events.count >= 2 {
            #expect(events[0].globalCount <= events[1].globalCount)
        }
    }

    @Test("Integrable events with failing integrity")
    func integrableEventsFailingIntegrity() throws {
        setup.context.performAndWait {
            let event = setup.addModEvent(store: storeId, revision: 1, timestamp: 1234)

            let eventMissingFile = setup.addModEvent(store: storeId, revision: 2, timestamp: 1234)
            setup.addMissingFile(to: eventMissingFile)

            _ = setup.addModEvent(store: storeId, revision: 3, timestamp: 1234)

            let result = try! revisionManager.integrableEvents(from: [event, eventMissingFile])
            #expect(result.events.count == 1)
        }
    }

    @Test("Integrable events with failing integrity for other store")
    func integrableEventsFailingIntegrity2() throws {
        setup.context.performAndWait {
            setup.addRevisionOfOtherStoreToBaseline("otherStore")

            let event = setup.addModEvent(store: "otherStore", revision: 1, timestamp: 1234)

            let eventMissingFile = setup.addModEvent(store: "otherStore", revision: 2, timestamp: 1234)
            setup.addMissingFile(to: eventMissingFile)

            _ = setup.addModEvent(store: "otherStore", revision: 3, timestamp: 1234)

            let result = try! revisionManager.integrableEvents(from: [event, eventMissingFile])
            #expect(result.events.count == 1)
        }
    }

    @Test("Integrable events with failing integrity corner case")
    func integrableEventsFailingIntegrityCornerCase() throws {
        setup.context.performAndWait {
            setup.addRevisionOfOtherStoreToBaseline("otherStore")

            let eventMissingFile = setup.addModEvent(store: "otherStore", revision: 1, timestamp: 1234)
            setup.addMissingFile(to: eventMissingFile)

            let event = setup.addModEvent(store: "otherStore", revision: 2, timestamp: 1234)
            _ = setup.addModEvent(store: "otherStore", revision: 3, timestamp: 1234)

            let result = try! revisionManager.integrableEvents(from: [event, eventMissingFile])
            #expect(result.events.count == 0)
        }
    }
}
