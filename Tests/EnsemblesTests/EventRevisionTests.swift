import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("EventRevision")
struct EventRevisionTests {

    @Test("Insert and fetch event revision")
    func insertAndFetchRevision() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 5)
        let rev = try setup.eventStore.fetchEventRevision(eventId: event.id)!
        #expect(rev.persistentStoreIdentifier == "store1")
        #expect(rev.revisionNumber == 5)
    }

    @Test("Fetch persistent store identifiers")
    func fetchPersistentStoreIdentifiers() throws {
        let setup = try TestEventStoreSetup()
        try setup.addModEvent(store: "store1", revision: 0)
        try setup.addModEvent(store: "store2", revision: 1)
        let ids = try setup.eventStore.fetchPersistentStoreIdentifiers()
        #expect(ids == Set(["store1", "store2"]))
    }

    @Test("Revision value type from EventRevision")
    func revisionValueType() throws {
        let setup = try TestEventStoreSetup()
        let event = try setup.addModEvent(store: "store1", revision: 5, globalCount: 10)
        let rev = try setup.eventStore.fetchEventRevision(eventId: event.id)!
        let revision = rev.revision(globalCount: event.globalCount)
        #expect(revision.persistentStoreIdentifier == "store1")
        #expect(revision.revisionNumber == 5)
        #expect(revision.globalCount == 10)
    }
}
