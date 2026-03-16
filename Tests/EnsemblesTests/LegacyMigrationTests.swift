import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("LegacyMigration", .serialized)
struct LegacyMigrationTests {

    let setup: TestEventStoreSetup

    init() throws {
        setup = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
    }

    // MARK: - Helpers

    /// Creates an event with object changes in the SQLite store, exports to legacy
    /// Core Data format via PersistentStoreEventExport, then imports back into a fresh
    /// SQLite store via PersistentStoreEventImport. Returns the imported store.
    private func roundTrip(
        eventType: StoreModificationEventType = .save,
        objectChanges: [(type: ObjectChangeType, entityName: String, propertyChanges: [StoredPropertyChange]?)]
    ) throws -> EventStore {
        let eventStore = setup.eventStore

        // Create the event
        let event = try eventStore.insertEvent(
            uniqueIdentifier: "roundtrip-\(UUID().uuidString)",
            type: eventType,
            timestamp: 12345.0,
            globalCount: 42
        )
        try eventStore.insertRevision(
            persistentStoreIdentifier: setup.persistentStoreIdentifier,
            revisionNumber: 7,
            eventId: event.id,
            isEventRevision: true
        )
        try eventStore.insertRevision(
            persistentStoreIdentifier: "other-store-id",
            revisionNumber: 3,
            eventId: event.id,
            isEventRevision: false
        )

        // Add global identifiers and object changes
        for (i, change) in objectChanges.enumerated() {
            let gid = try eventStore.insertGlobalIdentifier(
                globalIdentifier: "gid_\(i)",
                nameOfEntity: change.entityName,
                storeURI: "x-coredata://store/\(change.entityName)/p\(i)"
            )
            try eventStore.insertObjectChange(
                type: change.type,
                nameOfEntity: change.entityName,
                eventId: event.id,
                globalIdentifierId: gid.id,
                propertyChanges: change.propertyChanges
            )
        }

        // Export to legacy Core Data format
        guard let exporter = PersistentStoreEventExport(eventStore: eventStore, eventId: event.id, managedObjectModel: setup.testModel!) else {
            throw TestError("Could not create PersistentStoreEventExport")
        }
        try exporter.run()
        let fileURLs = exporter.fileURLs
        #expect(!fileURLs.isEmpty)

        // Create a fresh SQLite event store
        let importDir = (setup.tempDirectory as NSString).appendingPathComponent("import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: importDir, withIntermediateDirectories: true)
        let importEventStoreDir = (importDir as NSString).appendingPathComponent("test")
        try FileManager.default.createDirectory(atPath: importEventStoreDir, withIntermediateDirectories: true)
        guard let importStore = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: importDir) else {
            throw TestError("Could not create import EventStore")
        }
        try importStore.prepareNewEventStore()

        // Import the legacy files
        let importer = PersistentStoreEventImport(eventStore: importStore, importURLs: fileURLs)
        try importer.run()

        return importStore
    }

    // MARK: - Model Loading

    @Test("Legacy Core Data model can be loaded")
    func legacyCoreDataModelCanBeLoaded() {
        let model = EventStore.loadEventStoreModel()
        #expect(model != nil)
        let entityNames = model?.entities.map(\.name) ?? []
        #expect(entityNames.contains("CDEStoreModificationEvent"))
        #expect(entityNames.contains("CDEObjectChange"))
        #expect(entityNames.contains("CDEGlobalIdentifier"))
        #expect(entityNames.contains("CDEEventRevision"))
    }

    @Test("Event store model URL is valid")
    func eventStoreModelURLIsValid() {
        let url = EventStore.eventStoreModelURL
        #expect(url != nil)
        #expect(FileManager.default.fileExists(atPath: url!.path))
    }

    // MARK: - Round-Trip Tests

    @Test("Round-trip preserves event metadata")
    func roundTripPreservesEventMetadata() throws {
        let importStore = try roundTrip(
            eventType: .save,
            objectChanges: [
                (type: .insert, entityName: "Parent", propertyChanges: nil),
            ]
        )
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        #expect(events.count == 1)
        let event = events[0]
        #expect(event.type == .save)
        #expect(event.timestamp == 12345.0)
        #expect(event.globalCount == 42)
    }

    @Test("Round-trip preserves event revisions")
    func roundTripPreservesEventRevisions() throws {
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: nil),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let event = events[0]

        let eventRev = try importStore.fetchEventRevision(eventId: event.id)
        #expect(eventRev != nil)
        #expect(eventRev?.revisionNumber == 7)
        #expect(eventRev?.persistentStoreIdentifier == setup.persistentStoreIdentifier)

        let otherRevs = try importStore.fetchOtherStoreRevisions(eventId: event.id)
        #expect(otherRevs.count == 1)
        #expect(otherRevs[0].persistentStoreIdentifier == "other-store-id")
        #expect(otherRevs[0].revisionNumber == 3)
    }

    @Test("Round-trip preserves object change types")
    func roundTripPreservesObjectChangeTypes() throws {
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: nil),
            (type: .update, entityName: "Parent", propertyChanges: nil),
            (type: .delete, entityName: "Child", propertyChanges: nil),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        #expect(changes.count == 3)

        let types = Set(changes.map(\.type))
        #expect(types.contains(ObjectChangeType.insert))
        #expect(types.contains(ObjectChangeType.update))
        #expect(types.contains(ObjectChangeType.delete))
    }

    @Test("Round-trip preserves attribute property changes")
    func roundTripPreservesAttributePropertyChanges() throws {
        let props = [
            StoredPropertyChange(type: 0, propertyName: "name", value: .string("TestName")),
            StoredPropertyChange(type: 0, propertyName: "date", value: .date(1000.5)),
            StoredPropertyChange(type: 0, propertyName: "count", value: .int(42)),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        #expect(changes.count == 1)

        let imported = changes[0].propertyChangeValues
        #expect(imported != nil)
        #expect(imported?.count == 3)

        let byName = Dictionary(imported!.map { ($0.propertyName, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byName["name"]?.value == .string("TestName"))
        #expect(byName["date"]?.value == .date(1000.5))
        #expect(byName["count"]?.value == .int(42))
    }

    @Test("Round-trip preserves relationship property changes")
    func roundTripPreservesRelationshipPropertyChanges() throws {
        let props = [
            StoredPropertyChange(type: 1, propertyName: "parent", relatedIdentifier: "parent-gid-123"),
            StoredPropertyChange(type: 2, propertyName: "children",
                                 addedIdentifiers: ["child1", "child2"],
                                 removedIdentifiers: ["child3"]),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let imported = changes[0].propertyChangeValues!

        let byName = Dictionary(imported.map { ($0.propertyName, $0) }, uniquingKeysWith: { a, _ in a })

        let parentChange = byName["parent"]
        #expect(parentChange?.type == 1)
        #expect(parentChange?.relatedIdentifier == "parent-gid-123")

        let childrenChange = byName["children"]
        #expect(childrenChange?.type == 2)
        #expect(childrenChange?.addedIdentifiers?.sorted() == ["child1", "child2"])
        #expect(childrenChange?.removedIdentifiers == ["child3"])
    }

    @Test("Round-trip preserves global identifier entity names")
    func roundTripPreservesGlobalIdentifierEntityNames() throws {
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: nil),
            (type: .insert, entityName: "Child", propertyChanges: nil),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let entityNames = Set(changes.map(\.nameOfEntity))
        #expect(entityNames == ["Parent", "Child"])
    }

    // MARK: - Precision & Type-Specific Tests

    @Test("Round-trip preserves timestamp precision")
    func roundTripPreservesTimestampPrecision() throws {
        let eventStore = setup.eventStore

        // Use a precise timestamp that would lose precision if mishandled
        let preciseTimestamp = 793742399.123456789
        let event = try eventStore.insertEvent(
            uniqueIdentifier: "timestamp-precision-\(UUID().uuidString)",
            type: .save,
            timestamp: preciseTimestamp,
            globalCount: 1
        )
        try eventStore.insertRevision(
            persistentStoreIdentifier: setup.persistentStoreIdentifier,
            revisionNumber: 1,
            eventId: event.id,
            isEventRevision: true
        )
        let gid = try eventStore.insertGlobalIdentifier(
            globalIdentifier: "ts_gid",
            nameOfEntity: "Parent",
            storeURI: "x-coredata://store/Parent/p1"
        )
        try eventStore.insertObjectChange(
            type: .insert,
            nameOfEntity: "Parent",
            eventId: event.id,
            globalIdentifierId: gid.id,
            propertyChanges: nil
        )

        // Export to legacy format
        guard let exporter = PersistentStoreEventExport(eventStore: eventStore, eventId: event.id, managedObjectModel: setup.testModel!) else {
            throw TestError("Could not create exporter")
        }
        try exporter.run()

        // Import into fresh store
        let importDir = (setup.tempDirectory as NSString).appendingPathComponent("ts_import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: importDir, withIntermediateDirectories: true)
        let importStoreDir = (importDir as NSString).appendingPathComponent("test")
        try FileManager.default.createDirectory(atPath: importStoreDir, withIntermediateDirectories: true)
        guard let importStore = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: importDir) else {
            throw TestError("Could not create import EventStore")
        }
        try importStore.prepareNewEventStore()
        defer { importStore.dismantle() }

        let importer = PersistentStoreEventImport(eventStore: importStore, importURLs: exporter.fileURLs)
        try importer.run()

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        #expect(events.count == 1)
        // Core Data NSDate has ~millisecond precision, so check within a small epsilon
        let importedTimestamp = events[0].timestamp
        #expect(abs(importedTimestamp - preciseTimestamp) < 0.001,
                "Timestamp \(importedTimestamp) differs from \(preciseTimestamp) by more than 1ms")
    }

    @Test("Round-trip preserves large globalCount")
    func roundTripPreservesLargeGlobalCount() throws {
        let eventStore = setup.eventStore
        let largeCount: Int64 = 9_999_999_999

        let event = try eventStore.insertEvent(
            uniqueIdentifier: "gc-test-\(UUID().uuidString)",
            type: .save,
            timestamp: 100.0,
            globalCount: largeCount
        )
        try eventStore.insertRevision(
            persistentStoreIdentifier: setup.persistentStoreIdentifier,
            revisionNumber: 1,
            eventId: event.id,
            isEventRevision: true
        )
        let gid = try eventStore.insertGlobalIdentifier(
            globalIdentifier: "gc_gid",
            nameOfEntity: "Parent",
            storeURI: nil
        )
        try eventStore.insertObjectChange(
            type: .insert,
            nameOfEntity: "Parent",
            eventId: event.id,
            globalIdentifierId: gid.id,
            propertyChanges: nil
        )

        guard let exporter = PersistentStoreEventExport(eventStore: eventStore, eventId: event.id, managedObjectModel: setup.testModel!) else {
            throw TestError("Could not create exporter")
        }
        try exporter.run()

        let importDir = (setup.tempDirectory as NSString).appendingPathComponent("gc_import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: importDir, withIntermediateDirectories: true)
        let importStoreDir = (importDir as NSString).appendingPathComponent("test")
        try FileManager.default.createDirectory(atPath: importStoreDir, withIntermediateDirectories: true)
        guard let importStore = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: importDir) else {
            throw TestError("Could not create import EventStore")
        }
        try importStore.prepareNewEventStore()
        defer { importStore.dismantle() }

        let importer = PersistentStoreEventImport(eventStore: importStore, importURLs: exporter.fileURLs)
        try importer.run()

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        #expect(events[0].globalCount == largeCount)
    }

    @Test("Round-trip preserves save and merge event types")
    func roundTripPreservesSaveAndMergeEventTypes() throws {
        for eventType in [StoreModificationEventType.save, .merge] {
            let importStore = try roundTrip(
                eventType: eventType,
                objectChanges: [
                    (type: .insert, entityName: "Parent", propertyChanges: nil),
                ]
            )
            defer { importStore.dismantle() }

            let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
            #expect(events[0].type == eventType, "Event type \(eventType) not preserved")
        }
    }

    @Test("Round-trip preserves date StoredValue precision")
    func roundTripPreservesDateStoredValuePrecision() throws {
        let preciseDate = 793742399.123456789
        let props = [
            StoredPropertyChange(type: 0, propertyName: "dateField", value: .date(preciseDate)),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let imported = changes[0].propertyChangeValues!
        #expect(imported[0].value == .date(preciseDate),
                "Date StoredValue precision lost: got \(String(describing: imported[0].value))")
    }

    @Test("Round-trip preserves decimal StoredValue")
    func roundTripPreservesDecimalStoredValue() throws {
        let props = [
            StoredPropertyChange(type: 0, propertyName: "price", value: .decimal("99999.99999")),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let imported = changes[0].propertyChangeValues!
        #expect(imported[0].value == .decimal("99999.99999"))
    }

    @Test("Round-trip preserves special number StoredValues")
    func roundTripPreservesSpecialNumberStoredValues() throws {
        let props = [
            StoredPropertyChange(type: 0, propertyName: "nanField", value: .specialNumber("nan")),
            StoredPropertyChange(type: 0, propertyName: "posInf", value: .specialNumber("+inf")),
            StoredPropertyChange(type: 0, propertyName: "negInf", value: .specialNumber("-inf")),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let imported = changes[0].propertyChangeValues!

        let byName = Dictionary(imported.map { ($0.propertyName, $0) }, uniquingKeysWith: { a, _ in a })
        #expect(byName["nanField"]?.value == .specialNumber("nan"))
        #expect(byName["posInf"]?.value == .specialNumber("+inf"))
        #expect(byName["negInf"]?.value == .specialNumber("-inf"))
    }

    @Test("Round-trip preserves ordered to-many relationship with moved identifiers")
    func roundTripPreservesOrderedToMany() throws {
        let props = [
            StoredPropertyChange(
                type: PropertyChangeType.orderedToManyRelationship.rawValue,
                propertyName: "orderedItems",
                addedIdentifiers: ["a", "b", "c"],
                removedIdentifiers: ["d"],
                movedIdentifiersByIndex: ["0": "a", "1": "b", "2": "c"]
            ),
        ]
        let importStore = try roundTrip(objectChanges: [
            (type: .insert, entityName: "Parent", propertyChanges: props),
        ])
        defer { importStore.dismantle() }

        let events = try importStore.fetchEvents(types: nil, persistentStoreIdentifier: nil)
        let changes = try importStore.fetchObjectChanges(eventId: events[0].id)
        let imported = changes[0].propertyChangeValues![0]
        #expect(imported.type == PropertyChangeType.orderedToManyRelationship.rawValue)
        #expect(imported.addedIdentifiers?.sorted() == ["a", "b", "c"])
        #expect(imported.removedIdentifiers == ["d"])
        #expect(imported.movedIdentifiersByIndex == ["0": "a", "1": "b", "2": "c"])
    }
}
