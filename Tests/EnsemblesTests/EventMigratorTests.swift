import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventMigrator", .serialized)
struct EventMigratorTests {

    let setup: TestEventStoreSetup
    let migrator: EventMigrator
    let eventID: NSManagedObjectID

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        let moc = s.context

        nonisolated(unsafe) var capturedEventID: NSManagedObjectID!
        moc.performAndWait {
            let modEvent = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: moc) as! StoreModificationEvent
            modEvent.timestamp = 123
            modEvent.type = StoreModificationEventType.merge.rawValue
            modEvent.globalCount = 0

            let revision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: s.persistentStoreIdentifier, revisionNumber: 0, in: moc)
            modEvent.eventRevision = revision

            let globalId1 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: moc) as! GlobalIdentifier
            globalId1.globalIdentifier = "123"
            globalId1.nameOfEntity = "Parent"

            let globalId2 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: moc) as! GlobalIdentifier
            globalId2.globalIdentifier = "1234"
            globalId2.nameOfEntity = "Child"

            let globalId3 = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: moc) as! GlobalIdentifier
            globalId3.globalIdentifier = "1234"
            globalId3.nameOfEntity = "Child"

            let objectChange1 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: moc) as! ObjectChange
            objectChange1.nameOfEntity = "Parent"
            objectChange1.objectChangeType = .insert
            objectChange1.storeModificationEvent = modEvent
            objectChange1.globalIdentifier = globalId1
            objectChange1.propertyChangeValues = [] as NSArray

            let objectChange2 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: moc) as! ObjectChange
            objectChange2.nameOfEntity = "Child"
            objectChange2.objectChangeType = .update
            objectChange2.storeModificationEvent = modEvent
            objectChange2.globalIdentifier = globalId2
            objectChange2.propertyChangeValues = [] as NSArray

            let objectChange3 = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: moc) as! ObjectChange
            objectChange3.nameOfEntity = "Child"
            objectChange3.objectChangeType = .delete
            objectChange3.storeModificationEvent = modEvent
            objectChange3.globalIdentifier = globalId3

            try! moc.save()
            capturedEventID = modEvent.objectID
        }

        setup = s
        migrator = EventMigrator(eventStore: s.eventStore, managedObjectModel: s.testModel!)
        eventID = capturedEventID
    }

    // MARK: - Helpers

    private func migrateToFile() async throws -> URL {
        let fileURLs = try await migrator.migrateStoreModificationEvent(withObjectID: eventID)
        return fileURLs.last!
    }

    private func exportedJSON(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func changesByEntity(from url: URL) throws -> [String: [[String: Any]]] {
        let json = try exportedJSON(from: url)
        return json["changesByEntity"] as? [String: [[String: Any]]] ?? [:]
    }

    // MARK: - Tests

    @Test("Migration to file generates file")
    func migrationToFileGeneratesFile() async throws {
        let url = try await migrateToFile()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Migration to file migrates events")
    func migrationToFileMigratesEvents() async throws {
        let url = try await migrateToFile()
        let json = try exportedJSON(from: url)
        #expect(json.count > 0)
    }

    @Test("Migration to file migrates event properties")
    func migrationToFileMigratesEventProperties() async throws {
        let url = try await migrateToFile()
        let json = try exportedJSON(from: url)
        let timestamp = Double(json["timestamp"] as? String ?? "0") ?? 0
        #expect(timestamp == 123)

        let changes = try changesByEntity(from: url)
        #expect(changes["Child"]?.count == 2)
        #expect(changes["Parent"]?.count == 1)
    }

    @Test("Migration of NaN")
    func migrationOfNaN() async throws {
        setup.context.performAndWait {
            let fetch = NSFetchRequest<ObjectChange>(entityName: "CDEObjectChange")
            fetch.predicate = NSPredicate(format: "nameOfEntity = 'Parent'")
            let changes = (try? setup.context.fetch(fetch)) ?? []
            let change = changes.first!
            let notANumberChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
            notANumberChange.value = NSNumber(value: Double.nan)
            change.propertyChangeValues = [notANumberChange] as NSArray
            try! setup.context.save()
        }

        let url = try await migrateToFile()
        let changes = try changesByEntity(from: url)
        let parentChanges = changes["Parent"]!
        let change = parentChanges.last!
        let properties = change["properties"] as! [[String: Any]]
        let property = properties.last!
        let value = property["value"] as! [Any]
        #expect(value[0] as? String == "number")
        #expect(value[1] as? String == "nan")
    }

    @Test("Migration of Infinity")
    func migrationOfInfinity() async throws {
        setup.context.performAndWait {
            let fetch = NSFetchRequest<ObjectChange>(entityName: "CDEObjectChange")
            fetch.predicate = NSPredicate(format: "nameOfEntity = 'Parent'")
            let changes = (try? setup.context.fetch(fetch)) ?? []
            let change = changes.first!
            let infChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
            infChange.value = NSNumber(value: Double.infinity)
            change.propertyChangeValues = [infChange] as NSArray
            try! setup.context.save()
        }

        let url = try await migrateToFile()
        let changes = try changesByEntity(from: url)
        let parentChanges = changes["Parent"]!
        let change = parentChanges.last!
        let properties = change["properties"] as! [[String: Any]]
        let property = properties.last!
        let value = property["value"] as! [Any]
        #expect(value[0] as? String == "number")
        #expect(value[1] as? String == "+inf")
    }

    @Test("Migration of negative Infinity")
    func migrationOfNegativeInfinity() async throws {
        setup.context.performAndWait {
            let fetch = NSFetchRequest<ObjectChange>(entityName: "CDEObjectChange")
            fetch.predicate = NSPredicate(format: "nameOfEntity = 'Parent'")
            let changes = (try? setup.context.fetch(fetch)) ?? []
            let change = changes.first!
            let negInfChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
            negInfChange.value = NSNumber(value: -Double.infinity)
            change.propertyChangeValues = [negInfChange] as NSArray
            try! setup.context.save()
        }

        let url = try await migrateToFile()
        let changes = try changesByEntity(from: url)
        let parentChanges = changes["Parent"]!
        let change = parentChanges.last!
        let properties = change["properties"] as! [[String: Any]]
        let property = properties.last!
        let value = property["value"] as! [Any]
        #expect(value[0] as? String == "number")
        #expect(value[1] as? String == "-inf")
    }

    @Test("Migration to file migrates object changes")
    func migrationToFileMigratesObjectChanges() async throws {
        let url = try await migrateToFile()
        let changes = try changesByEntity(from: url)
        let childChanges = changes["Child"]!
        #expect(childChanges.count == 2)
        let change = childChanges.last!
        #expect(change["globalIdentifier"] != nil)
    }

    @Test("Single event is migrated when multiple events exist")
    func singleEventMigratedWhenMultipleExist() async throws {
        // Add extra event sharing a global identifier
        setup.context.performAndWait {
            let extraEvent = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: setup.context) as! StoreModificationEvent
            extraEvent.timestamp = 124
            extraEvent.type = StoreModificationEventType.save.rawValue
            extraEvent.globalCount = 1

            let revision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: setup.persistentStoreIdentifier, revisionNumber: 1, in: setup.context)
            extraEvent.eventRevision = revision

            // Reuse existing globalId1
            let fetch = NSFetchRequest<GlobalIdentifier>(entityName: "CDEGlobalIdentifier")
            fetch.predicate = NSPredicate(format: "globalIdentifier = '123' AND nameOfEntity = 'Parent'")
            let globalId = (try? setup.context.fetch(fetch))?.first

            let objectChange = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: setup.context) as! ObjectChange
            objectChange.nameOfEntity = "Hello"
            objectChange.objectChangeType = .update
            objectChange.storeModificationEvent = extraEvent
            objectChange.globalIdentifier = globalId
            objectChange.propertyChangeValues = [] as NSArray

            try! setup.context.save()
        }

        let types: [StoreModificationEventType] = [.merge, .save]
        let fileURLs = try await migrator.migrateLocalEventToTemporaryFiles(forRevision: 0, allowedTypes: types)
        #expect(fileURLs.count == 1)

        let json = try exportedJSON(from: fileURLs.last!)
        #expect(json.count > 0)

        let revisions = json["revisionsByStoreIdentifier"] as? [String: NSNumber] ?? [:]
        #expect(revisions[setup.persistentStoreIdentifier] == NSNumber(value: 0))
    }

    @Test("Import from other store")
    func importFromOtherStore() async throws {
        let url = try await migrateToFile()
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        json["storeIdentifier"] = "otherstore"

        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        try modifiedData.write(to: url)

        let _ = try await migrator.migrateEventIn(from: [url])

        setup.context.performAndWait {
            let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
            let storeEvents = (try? setup.context.fetch(fetch)) ?? []
            #expect(storeEvents.count == 2)

            let newEvent = storeEvents.first { $0.eventRevision?.persistentStoreIdentifier == "otherstore" }
            #expect(newEvent != nil)
            #expect(newEvent?.objectChanges.count == 3)
        }
    }
}
