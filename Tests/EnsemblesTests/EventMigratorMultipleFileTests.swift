import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventMigrator Multiple Files", .serialized)
struct EventMigratorMultipleFileTests {

    let setup: TestEventStoreSetup
    let migrator: EventMigrator
    let eventId: Int64
    let testModel: NSManagedObjectModel

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        let model = s.testModel!

        let modEvent = try s.eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .merge,
            timestamp: 123,
            globalCount: 0
        )
        try s.eventStore.insertRevision(persistentStoreIdentifier: s.persistentStoreIdentifier, revisionNumber: 0, eventId: modEvent.id, isEventRevision: true)

        for _ in 0..<100 {
            let globalId = try s.eventStore.insertGlobalIdentifier(
                globalIdentifier: ProcessInfo.processInfo.globallyUniqueString,
                nameOfEntity: "Parent"
            )
            try s.eventStore.insertObjectChange(
                type: .insert,
                nameOfEntity: "Parent",
                eventId: modEvent.id,
                globalIdentifierId: globalId.id,
                propertyChanges: []
            )
        }

        setup = s
        migrator = EventMigrator(eventStore: s.eventStore, managedObjectModel: model)
        eventId = modEvent.id
        testModel = model
    }

    private func setBatchSize(_ size: Int) {
        let parentEntity = testModel.entitiesByName["Parent"]!
        var mutableInfo = parentEntity.userInfo ?? [:]
        mutableInfo[ModelUserInfoKeys.migrationBatchSize] = "\(size)"
        parentEntity.userInfo = mutableInfo
    }

    private func jsonFromURL(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test("Exporting single file")
    func exportingSingleFile() async throws {
        setBatchSize(100)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)
        #expect(fileURLs.count == 1)
    }

    @Test("Exporting two equal batches")
    func exportingTwoEqualBatches() async throws {
        setBatchSize(50)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)
        #expect(fileURLs.count == 2)

        let json1 = jsonFromURL(fileURLs[0])
        let json2 = jsonFromURL(fileURLs[1])
        #expect(json1 != nil)
        #expect(json2 != nil)
    }

    @Test("Exporting small third batch")
    func exportingSmallThirdBatch() async throws {
        setBatchSize(49)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)
        #expect(fileURLs.count == 3)

        let json0 = jsonFromURL(fileURLs[0])!
        let json1 = jsonFromURL(fileURLs[1])!
        let json2 = jsonFromURL(fileURLs[2])!

        let changes0 = (json0["changesByEntity"] as? [String: [[String: Any]]])?["Parent"]
        #expect(changes0?.count == 49)

        let changes1 = (json1["changesByEntity"] as? [String: [[String: Any]]])?["Parent"]
        #expect(changes1?.count == 49)

        let changes2 = (json2["changesByEntity"] as? [String: [[String: Any]]])?["Parent"]
        #expect(changes2?.count == 2)
    }

    @Test("Files contain distinct object changes")
    func filesContainDistinctObjectChanges() async throws {
        setBatchSize(51)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)
        #expect(fileURLs.count == 2)

        var globalIds = Set<String>()

        let json0 = jsonFromURL(fileURLs[0])!
        let changes0 = (json0["changesByEntity"] as? [String: [[String: Any]]])?["Parent"] ?? []
        for change in changes0 {
            if let gid = change["globalIdentifier"] as? String { globalIds.insert(gid) }
        }

        let json1 = jsonFromURL(fileURLs[1])!
        let changes1 = (json1["changesByEntity"] as? [String: [[String: Any]]])?["Parent"] ?? []
        for change in changes1 {
            if let gid = change["globalIdentifier"] as? String { globalIds.insert(gid) }
        }

        #expect(globalIds.count == 100)
    }

    @Test("Export and reimport")
    func exportAndReimport() async throws {
        setBatchSize(50)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)

        // Delete event from event store
        try setup.eventStore.deleteEvent(id: eventId)

        let remainingEvents = try setup.eventStore.fetchCompleteEvents()
        #expect(remainingEvents.count == 0)

        // Reimport
        let newEventId = try await migrator.migrateEventIn(from: fileURLs)

        #expect(newEventId != nil)

        let events = try setup.eventStore.fetchCompleteEvents()
        #expect(events.count == 1)

        let event = events.last!
        #expect(event.id == newEventId)

        let changes = try setup.eventStore.fetchObjectChanges(eventId: event.id)
        #expect(changes.count == 100)

        let globalIdStrings = Set(try changes.compactMap { change -> String? in
            let gid = try setup.eventStore.fetchGlobalIdentifier(id: change.globalIdentifierId)
            return gid?.globalIdentifier
        })
        #expect(globalIdStrings.count == 100)
    }
}
