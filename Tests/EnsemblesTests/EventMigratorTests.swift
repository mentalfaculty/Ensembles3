import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventMigrator", .serialized)
struct EventMigratorTests {

    let setup: TestEventStoreSetup
    let migrator: EventMigrator
    let eventId: Int64

    init() throws {
        let s = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)

        let modEvent = try s.eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .merge,
            timestamp: 123,
            globalCount: 0
        )
        try s.eventStore.insertRevision(persistentStoreIdentifier: s.persistentStoreIdentifier, revisionNumber: 0, eventId: modEvent.id, isEventRevision: true)

        let globalId1 = try s.eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")
        let globalId2 = try s.eventStore.insertGlobalIdentifier(globalIdentifier: "1234", nameOfEntity: "Child")
        let globalId3 = try s.eventStore.insertGlobalIdentifier(globalIdentifier: "1234", nameOfEntity: "Child")

        try s.eventStore.insertObjectChange(type: .insert, nameOfEntity: "Parent", eventId: modEvent.id, globalIdentifierId: globalId1.id, propertyChanges: [])
        try s.eventStore.insertObjectChange(type: .update, nameOfEntity: "Child", eventId: modEvent.id, globalIdentifierId: globalId2.id, propertyChanges: [])
        try s.eventStore.insertObjectChange(type: .delete, nameOfEntity: "Child", eventId: modEvent.id, globalIdentifierId: globalId3.id, propertyChanges: nil)

        setup = s
        migrator = EventMigrator(eventStore: s.eventStore, managedObjectModel: s.testModel!)
        eventId = modEvent.id
    }

    // MARK: - Helpers

    private func migrateToFile() async throws -> URL {
        let fileURLs = try await migrator.migrateStoreModificationEvent(withId: eventId)
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
        let changes = try setup.eventStore.fetchObjectChanges(eventId: eventId)
        let parentChange = changes.first { $0.nameOfEntity == "Parent" }!
        let notANumberChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
        notANumberChange.value = NSNumber(value: Double.nan)
        try setup.eventStore.updateObjectChangePropertyChanges(id: parentChange.id, propertyChanges: [notANumberChange.toStoredPropertyChange()])

        let url = try await migrateToFile()
        let changesByEnt = try changesByEntity(from: url)
        let parentChanges = changesByEnt["Parent"]!
        let change = parentChanges.last!
        let properties = change["properties"] as! [[String: Any]]
        let property = properties.last!
        let value = property["value"] as! [Any]
        #expect(value[0] as? String == "number")
        #expect(value[1] as? String == "nan")
    }

    @Test("Migration of Infinity")
    func migrationOfInfinity() async throws {
        let changes = try setup.eventStore.fetchObjectChanges(eventId: eventId)
        let parentChange = changes.first { $0.nameOfEntity == "Parent" }!
        let infChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
        infChange.value = NSNumber(value: Double.infinity)
        try setup.eventStore.updateObjectChangePropertyChanges(id: parentChange.id, propertyChanges: [infChange.toStoredPropertyChange()])

        let url = try await migrateToFile()
        let changesByEnt = try changesByEntity(from: url)
        let parentChanges = changesByEnt["Parent"]!
        let change = parentChanges.last!
        let properties = change["properties"] as! [[String: Any]]
        let property = properties.last!
        let value = property["value"] as! [Any]
        #expect(value[0] as? String == "number")
        #expect(value[1] as? String == "+inf")
    }

    @Test("Migration of negative Infinity")
    func migrationOfNegativeInfinity() async throws {
        let changes = try setup.eventStore.fetchObjectChanges(eventId: eventId)
        let parentChange = changes.first { $0.nameOfEntity == "Parent" }!
        let negInfChange = PropertyChangeValue(type: .attribute, propertyName: "someNumber")
        negInfChange.value = NSNumber(value: -Double.infinity)
        try setup.eventStore.updateObjectChangePropertyChanges(id: parentChange.id, propertyChanges: [negInfChange.toStoredPropertyChange()])

        let url = try await migrateToFile()
        let changesByEnt = try changesByEntity(from: url)
        let parentChanges = changesByEnt["Parent"]!
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
        let extraEvent = try setup.eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .save,
            timestamp: 124,
            globalCount: 1
        )
        try setup.eventStore.insertRevision(persistentStoreIdentifier: setup.persistentStoreIdentifier, revisionNumber: 1, eventId: extraEvent.id, isEventRevision: true)

        // Reuse existing globalId1
        let globalId = try setup.eventStore.fetchGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")

        if let globalId {
            try setup.eventStore.insertObjectChange(type: .update, nameOfEntity: "Hello", eventId: extraEvent.id, globalIdentifierId: globalId.id, propertyChanges: [])
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
        json["uniqueIdentifier"] = ProcessInfo.processInfo.globallyUniqueString

        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        try modifiedData.write(to: url)

        let newEventId = try await migrator.migrateEventIn(from: [url])

        #expect(newEventId != nil)

        let events = try setup.eventStore.fetchCompleteEvents()
        #expect(events.count == 2)

        let newEvent = events.first { event in
            let rev = try? setup.eventStore.fetchEventRevision(eventId: event.id)
            return rev?.persistentStoreIdentifier == "otherstore"
        }
        #expect(newEvent != nil)

        if let newEvent {
            let changes = try setup.eventStore.fetchObjectChanges(eventId: newEvent.id)
            #expect(changes.count == 3)
        }
    }
}
