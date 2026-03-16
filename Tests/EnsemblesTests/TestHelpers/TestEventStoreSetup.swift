import Foundation
import CoreData
@_spi(Testing) import Ensembles

/// Creates a real `EventStore` backed by SQLite in a temp directory.
/// Used by tests that need a real `EventStore` (RevisionManager, BaselineConsolidator, Rebaser, etc.)
final class TestEventStoreSetup: @unchecked Sendable {
    let eventStore: EventStore
    let tempDirectory: String

    var persistentStoreIdentifier: String { eventStore.persistentStoreIdentifier! }

    /// The test app model (CDEStoreModificationEventTestsModel) and context.
    var testModel: NSManagedObjectModel?
    var testManagedObjectContext: NSManagedObjectContext?
    var testStoreURL: URL?

    init(useDiskTestStore: Bool = false, loadTestModel: Bool = false) throws {
        tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("EnsemblesTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true)

        // Pre-create the event store directory so removeEventStore() in prepareNewEventStore() doesn't fail
        let eventStoreDir = (tempDirectory as NSString).appendingPathComponent("test")
        try FileManager.default.createDirectory(atPath: eventStoreDir, withIntermediateDirectories: true)

        guard let store = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: tempDirectory) else {
            throw TestError("Could not create EventStore")
        }
        try store.prepareNewEventStore()
        self.eventStore = store

        if loadTestModel {
            guard let testModelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd") else {
                throw TestError("Could not find CDEStoreModificationEventTestsModel.momd")
            }
            guard let model = TestModelCache.model(for: testModelURL) else {
                throw TestError("Could not load test model")
            }
            self.testModel = model
            let psc = NSPersistentStoreCoordinator(managedObjectModel: model)

            if useDiskTestStore {
                let storeFile = (tempDirectory as NSString).appendingPathComponent("teststore.sql")
                testStoreURL = URL(fileURLWithPath: storeFile)
                try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: testStoreURL!, options: nil)
            } else {
                try psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
            }

            let moc = NSManagedObjectContext(.privateQueue)
            moc.performAndWait { moc.persistentStoreCoordinator = psc }
            self.testManagedObjectContext = moc
        }
    }

    deinit {
        testManagedObjectContext?.performAndWait { testManagedObjectContext?.reset() }
        eventStore.dismantle()
        try? FileManager.default.removeItem(atPath: tempDirectory)
    }

    // MARK: - Event Store Helpers

    @discardableResult
    func addEventRevision(store: String, revision: RevisionNumber, eventId: Int64) throws -> EventRevision {
        try eventStore.insertRevision(persistentStoreIdentifier: store, revisionNumber: revision, eventId: eventId, isEventRevision: false)
    }

    @discardableResult
    func addModEvent(store: String, revision: RevisionNumber, globalCount: GlobalCount = 0, timestamp: TimeInterval = 0) throws -> StoreModificationEvent {
        let event = try eventStore.insertEvent(
            uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
            type: .save,
            timestamp: timestamp,
            globalCount: globalCount
        )
        try eventStore.insertRevision(persistentStoreIdentifier: store, revisionNumber: revision, eventId: event.id, isEventRevision: true)
        return event
    }

    @discardableResult
    func addGlobalIdentifier(_ identifier: String, entity: String) throws -> GlobalIdentifier {
        try eventStore.insertGlobalIdentifier(globalIdentifier: identifier, nameOfEntity: entity, storeURI: nil)
    }

    @discardableResult
    func addObjectChange(type: ObjectChangeType, globalIdentifier: GlobalIdentifier, event: StoreModificationEvent, propertyChanges: [StoredPropertyChange]? = nil) throws -> ObjectChange {
        try eventStore.insertObjectChange(type: type, nameOfEntity: globalIdentifier.nameOfEntity, eventId: event.id, globalIdentifierId: globalIdentifier.id, propertyChanges: propertyChanges)
    }

    // MARK: - Property Change Value Helpers

    func attributeChange(name: String, value: Any?) -> PropertyChangeValue {
        let pcv = PropertyChangeValue(type: .attribute, propertyName: name)
        pcv.value = value as? NSObject
        return pcv
    }

    func toOneRelationshipChange(name: String, relatedIdentifier: Any?) -> PropertyChangeValue {
        let pcv = PropertyChangeValue(type: .toOneRelationship, propertyName: name)
        pcv.relatedIdentifier = relatedIdentifier as? NSObject
        return pcv
    }

    func toManyRelationshipChange(name: String, added: [AnyHashable], removed: [AnyHashable]) -> PropertyChangeValue {
        let pcv = PropertyChangeValue(type: .toManyRelationship, propertyName: name)
        pcv.addedIdentifiers = Set(added)
        pcv.removedIdentifiers = Set(removed)
        return pcv
    }

    // MARK: - Baseline Helpers

    @discardableResult
    func addBaselineEvents(storeId: String, globalCounts: [GlobalCount], revisions: [RevisionNumber]) throws -> [StoreModificationEvent] {
        var baselines: [StoreModificationEvent] = []
        for i in 0..<globalCounts.count {
            let event = try eventStore.insertEvent(
                uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
                type: .baseline,
                timestamp: 10.0,
                globalCount: globalCounts[i],
                modelVersion: "DEFAULT"
            )
            try eventStore.insertRevision(persistentStoreIdentifier: storeId, revisionNumber: revisions[i], eventId: event.id, isEventRevision: true)
            baselines.append(event)
        }
        return baselines
    }

    @discardableResult
    func addEvents(type: StoreModificationEventType, storeId: String, globalCounts: [GlobalCount], revisions: [RevisionNumber]) throws -> [StoreModificationEvent] {
        var events: [StoreModificationEvent] = []
        for i in 0..<globalCounts.count {
            let event = try eventStore.insertEvent(
                uniqueIdentifier: ProcessInfo.processInfo.globallyUniqueString,
                type: type,
                timestamp: 10.0,
                globalCount: globalCounts[i]
            )
            try eventStore.insertRevision(persistentStoreIdentifier: storeId, revisionNumber: revisions[i], eventId: event.id, isEventRevision: true)
            events.append(event)
        }
        return events
    }

    @discardableResult
    func objectChange(globalId: GlobalIdentifier, valuesByKey: [String: Any], event: StoreModificationEvent) throws -> ObjectChange {
        var storedChanges: [StoredPropertyChange] = []
        for (key, obj) in valuesByKey {
            let pcv = PropertyChangeValue(type: .attribute, propertyName: key)
            pcv.value = obj as? NSObject
            storedChanges.append(pcv.toStoredPropertyChange())
        }
        return try eventStore.insertObjectChange(type: .insert, nameOfEntity: globalId.nameOfEntity, eventId: event.id, globalIdentifierId: globalId.id, propertyChanges: storedChanges)
    }

    func fetchStoreModEvents() throws -> [StoreModificationEvent] {
        try eventStore.fetchCompleteEvents()
    }

    func fetchBaseline() throws -> StoreModificationEvent? {
        try eventStore.fetchBaselineEvent()
    }

    func addMissingFile(to event: StoreModificationEvent) throws {
        let globalId = try eventStore.insertGlobalIdentifier(globalIdentifier: "123", nameOfEntity: "Parent")
        let objChange = try eventStore.insertObjectChange(type: .insert, nameOfEntity: "Parent", eventId: event.id, globalIdentifierId: globalId.id)
        try eventStore.insertDataFile(filename: "filename", objectChangeId: objChange.id)
    }

    func addRevisionOfOtherStoreToBaseline(_ storeId: String) throws {
        let baseline = try eventStore.fetchBaselineEvent()!
        try eventStore.insertRevision(persistentStoreIdentifier: storeId, revisionNumber: 0, eventId: baseline.id, isEventRevision: false)
    }
}
