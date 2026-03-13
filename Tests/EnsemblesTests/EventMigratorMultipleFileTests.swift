import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventMigrator Multiple Files", .serialized)
struct EventMigratorMultipleFileTests {

    let setup: TestEventStoreSetup
    let migrator: EventMigrator
    let eventID: NSManagedObjectID
    let testModel: NSManagedObjectModel

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        let model = s.testModel!
        let moc = s.context

        nonisolated(unsafe) var capturedEventID: NSManagedObjectID!
        moc.performAndWait {
            let modEvent = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: moc) as! StoreModificationEvent
            modEvent.timestamp = 123
            modEvent.type = StoreModificationEventType.merge.rawValue
            modEvent.globalCount = 0

            let revision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: s.persistentStoreIdentifier, revisionNumber: 0, in: moc)
            modEvent.eventRevision = revision

            for _ in 0..<100 {
                let globalId = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: moc) as! GlobalIdentifier
                globalId.globalIdentifier = ProcessInfo.processInfo.globallyUniqueString
                globalId.nameOfEntity = "Parent"

                let objectChange = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: moc) as! ObjectChange
                objectChange.nameOfEntity = "Parent"
                objectChange.objectChangeType = .insert
                objectChange.storeModificationEvent = modEvent
                objectChange.globalIdentifier = globalId
                objectChange.propertyChangeValues = [] as NSArray
            }

            try! moc.save()
            capturedEventID = modEvent.objectID
        }

        setup = s
        migrator = EventMigrator(eventStore: s.eventStore, managedObjectModel: model)
        eventID = capturedEventID
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
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)
        #expect(fileURLs.count == 1)
    }

    @Test("Exporting two equal batches")
    func exportingTwoEqualBatches() async throws {
        setBatchSize(50)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)
        #expect(fileURLs.count == 2)

        let json1 = jsonFromURL(fileURLs[0])
        let json2 = jsonFromURL(fileURLs[1])
        #expect(json1 != nil)
        #expect(json2 != nil)
    }

    @Test("Exporting small third batch")
    func exportingSmallThirdBatch() async throws {
        setBatchSize(49)
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)
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
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)
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
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)

        // Delete event from event store
        setup.context.performAndWait {
            let event = try! setup.context.existingObject(with: eventID) as! StoreModificationEvent
            setup.context.delete(event)
            try! setup.context.save()

            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            let events = (try? setup.context.fetch(fetch)) ?? []
            #expect(events.count == 0)
        }

        // Reimport
        let newEventID = try await migrator.migrateEventIn(from: fileURLs)

        setup.context.performAndWait {
            #expect(newEventID != nil)

            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            let events = (try? setup.context.fetch(fetch)) ?? []
            #expect(events.count == 1)

            let event = events.last!
            #expect(event.objectID == newEventID)
            #expect(event.objectChanges.count == 100)

            let globalIdStrings = Set(event.objectChanges.compactMap { $0.globalIdentifier?.globalIdentifier })
            #expect(globalIdStrings.count == 100)
        }
    }
}
