import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventRevision")
struct EventRevisionTests {

    @Test("Make event revision")
    func makeEventRevision() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let rev = EventRevision.makeEventRevision(
                forPersistentStoreIdentifier: "store1",
                revisionNumber: 5,
                in: stack.context
            )
            #expect(rev.persistentStoreIdentifier == "store1")
            #expect(rev.revisionNumber == 5)
        }
    }

    @Test("Fetch persistent store identifiers")
    func fetchPersistentStoreIdentifiers() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            _ = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "store1", revisionNumber: 0, in: stack.context)
            _ = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "store2", revisionNumber: 1, in: stack.context)
            let ids = try! EventRevision.fetchPersistentStoreIdentifiers(in: stack.context)
            #expect(ids == Set(["store1", "store2"]))
        }
    }

    @Test("Revision value type from EventRevision")
    func revisionValueType() throws {
        let stack = try EventStoreTestStack()
        stack.context.performAndWait {
            let event = stack.addModEvent(store: "store1", revision: 5, globalCount: 10)
            let rev = event.eventRevision!.revision
            #expect(rev.persistentStoreIdentifier == "store1")
            #expect(rev.revisionNumber == 5)
            #expect(rev.globalCount == 10)
        }
    }
}
