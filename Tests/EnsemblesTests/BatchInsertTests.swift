import Testing
import Foundation
@_spi(Testing) import Ensembles

@Suite("BatchInsert", .serialized)
struct BatchInsertTests {

    let setup: TestEventStoreSetup
    let eventId: Int64

    init() throws {
        let s = try TestEventStoreSetup()
        let event = try s.eventStore.insertEvent(
            uniqueIdentifier: "test-event",
            type: .save,
            timestamp: Date().timeIntervalSinceReferenceDate,
            globalCount: 1
        )
        setup = s
        eventId = event.id
    }

    // MARK: - insertObjectChanges

    @Test("Batch insert object changes returns correct IDs")
    func batchInsertObjectChangesReturnsCorrectIDs() throws {
        let gid = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g1", nameOfEntity: "Parent")
        let changes: [(type: ObjectChangeType, nameOfEntity: String, eventId: Int64, globalIdentifierId: Int64, propertyChanges: [StoredPropertyChange]?)] = [
            (type: .insert, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: nil),
            (type: .update, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: nil),
            (type: .delete, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: nil),
        ]
        let ids = try setup.eventStore.insertObjectChanges(changes)
        #expect(ids.count == 3)
        #expect(ids[0] < ids[1])
        #expect(ids[1] < ids[2])
    }

    @Test("Batch insert object changes with property changes")
    func batchInsertWithPropertyChanges() throws {
        let gid = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g2", nameOfEntity: "Parent")
        let props = [
            StoredPropertyChange(type: 0, propertyName: "name", value: .string("hello")),
            StoredPropertyChange(type: 0, propertyName: "date", value: .date(1000.0)),
        ]
        let changes: [(type: ObjectChangeType, nameOfEntity: String, eventId: Int64, globalIdentifierId: Int64, propertyChanges: [StoredPropertyChange]?)] = [
            (type: .insert, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: props),
        ]
        let ids = try setup.eventStore.insertObjectChanges(changes)
        #expect(ids.count == 1)

        let fetched = try setup.eventStore.fetchObjectChange(id: ids[0])
        #expect(fetched != nil)
        #expect(fetched?.type == .insert)
        #expect(fetched?.nameOfEntity == "Parent")
        #expect(fetched?.propertyChangeValues?.count == 2)
        #expect(fetched?.propertyChangeValues?[0].propertyName == "name")
        #expect(fetched?.propertyChangeValues?[1].propertyName == "date")
    }

    @Test("Batch insert with nil property changes")
    func batchInsertWithNilPropertyChanges() throws {
        let gid = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g3", nameOfEntity: "Child")
        let changes: [(type: ObjectChangeType, nameOfEntity: String, eventId: Int64, globalIdentifierId: Int64, propertyChanges: [StoredPropertyChange]?)] = [
            (type: .delete, nameOfEntity: "Child", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: nil),
        ]
        let ids = try setup.eventStore.insertObjectChanges(changes)
        let fetched = try setup.eventStore.fetchObjectChange(id: ids[0])
        #expect(fetched?.type == .delete)
        #expect(fetched?.propertyChangeValues == nil)
    }

    @Test("Batch insert more than one chunk (>100 rows)")
    func batchInsertMultipleChunks() throws {
        let gid = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g4", nameOfEntity: "Parent")
        let count = 250
        var changes: [(type: ObjectChangeType, nameOfEntity: String, eventId: Int64, globalIdentifierId: Int64, propertyChanges: [StoredPropertyChange]?)] = []
        for _ in 0..<count {
            changes.append((type: .insert, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid.id, propertyChanges: nil))
        }
        let ids = try setup.eventStore.insertObjectChanges(changes)
        #expect(ids.count == count)
        // IDs should be sequential
        for i in 1..<ids.count {
            #expect(ids[i] == ids[i - 1] + 1)
        }
    }

    @Test("Batch insert empty array returns empty")
    func batchInsertEmptyArray() throws {
        let ids = try setup.eventStore.insertObjectChanges([])
        #expect(ids.isEmpty)
    }

    @Test("Batch inserted changes are fetchable by event")
    func batchInsertedChangesFetchableByEvent() throws {
        let gid1 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g5", nameOfEntity: "Parent")
        let gid2 = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "g6", nameOfEntity: "Child")
        let changes: [(type: ObjectChangeType, nameOfEntity: String, eventId: Int64, globalIdentifierId: Int64, propertyChanges: [StoredPropertyChange]?)] = [
            (type: .insert, nameOfEntity: "Parent", eventId: eventId, globalIdentifierId: gid1.id, propertyChanges: nil),
            (type: .insert, nameOfEntity: "Child", eventId: eventId, globalIdentifierId: gid2.id, propertyChanges: nil),
        ]
        _ = try setup.eventStore.insertObjectChanges(changes)
        let fetched = try setup.eventStore.fetchObjectChanges(eventId: eventId)
        #expect(fetched.count == 2)
    }

    // MARK: - insertGlobalIdentifiers

    @Test("Batch insert global identifiers returns correct IDs")
    func batchInsertGlobalIdentifiersReturnsCorrectIDs() throws {
        let entries: [(globalIdentifier: String, nameOfEntity: String, storeURI: String?)] = [
            (globalIdentifier: "id1", nameOfEntity: "Parent", storeURI: nil),
            (globalIdentifier: "id2", nameOfEntity: "Child", storeURI: "x-coredata://store/Child/p1"),
            (globalIdentifier: "id3", nameOfEntity: "Parent", storeURI: nil),
        ]
        let ids = try setup.eventStore.insertGlobalIdentifiers(entries)
        #expect(ids.count == 3)
        #expect(ids[0] < ids[1])
        #expect(ids[1] < ids[2])
    }

    @Test("Batch insert global identifiers are fetchable")
    func batchInsertGlobalIdentifiersAreFetchable() throws {
        let entries: [(globalIdentifier: String, nameOfEntity: String, storeURI: String?)] = [
            (globalIdentifier: "fetch1", nameOfEntity: "Parent", storeURI: "uri1"),
            (globalIdentifier: "fetch2", nameOfEntity: "Child", storeURI: nil),
        ]
        let ids = try setup.eventStore.insertGlobalIdentifiers(entries)

        let gid1 = try setup.eventStore.fetchGlobalIdentifier(id: ids[0])
        #expect(gid1?.globalIdentifier == "fetch1")
        #expect(gid1?.nameOfEntity == "Parent")
        #expect(gid1?.storeURI == "uri1")

        let gid2 = try setup.eventStore.fetchGlobalIdentifier(id: ids[1])
        #expect(gid2?.globalIdentifier == "fetch2")
        #expect(gid2?.nameOfEntity == "Child")
        #expect(gid2?.storeURI == nil)
    }

    @Test("Batch insert global identifiers more than one chunk")
    func batchInsertGlobalIdentifiersMultipleChunks() throws {
        let count = 250
        var entries: [(globalIdentifier: String, nameOfEntity: String, storeURI: String?)] = []
        for i in 0..<count {
            entries.append((globalIdentifier: "bulk_\(i)", nameOfEntity: "Parent", storeURI: nil))
        }
        let ids = try setup.eventStore.insertGlobalIdentifiers(entries)
        #expect(ids.count == count)
        for i in 1..<ids.count {
            #expect(ids[i] == ids[i - 1] + 1)
        }
    }

    @Test("Batch insert global identifiers with duplicates falls back to individual")
    func batchInsertGlobalIdentifiersWithDuplicates() throws {
        // Pre-insert one
        let existing = try setup.eventStore.insertGlobalIdentifier(globalIdentifier: "dup1", nameOfEntity: "Parent")

        let entries: [(globalIdentifier: String, nameOfEntity: String, storeURI: String?)] = [
            (globalIdentifier: "dup1", nameOfEntity: "Parent", storeURI: nil), // duplicate
            (globalIdentifier: "dup2", nameOfEntity: "Child", storeURI: nil),  // new
        ]
        let ids = try setup.eventStore.insertGlobalIdentifiers(entries)
        #expect(ids.count == 2)
        #expect(ids[0] == existing.id) // should return existing ID
    }

    @Test("Batch insert global identifiers empty array returns empty")
    func batchInsertGlobalIdentifiersEmpty() throws {
        let ids = try setup.eventStore.insertGlobalIdentifiers([])
        #expect(ids.isEmpty)
    }
}
