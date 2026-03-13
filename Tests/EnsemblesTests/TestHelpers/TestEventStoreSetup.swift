import Foundation
import CoreData
@_spi(Testing) import Ensembles

/// Creates a real `EventStore` backed by SQLite in a temp directory.
/// Used by tests that need a real `EventStore` (RevisionManager, BaselineConsolidator, Rebaser, etc.)
final class TestEventStoreSetup: @unchecked Sendable {
    let eventStore: EventStore
    let tempDirectory: String

    var context: NSManagedObjectContext { eventStore.managedObjectContext! }
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

    // MARK: - Event Store MOC Helpers

    func addEventRevision(store: String, revision: RevisionNumber) -> EventRevision {
        EventRevision.makeEventRevision(forPersistentStoreIdentifier: store, revisionNumber: revision, in: context)
    }

    func addModEvent(store: String, revision: RevisionNumber, globalCount: GlobalCount = 0, timestamp: TimeInterval = 0) -> StoreModificationEvent {
        let event = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: context) as! StoreModificationEvent
        event.storeModificationEventType = .save
        event.timestamp = timestamp
        event.globalCount = globalCount
        event.eventRevision = addEventRevision(store: store, revision: revision)
        return event
    }

    func addGlobalIdentifier(_ identifier: String, entity: String) -> GlobalIdentifier {
        let gid = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: context) as! GlobalIdentifier
        gid.globalIdentifier = identifier
        gid.nameOfEntity = entity
        gid.storeURI = nil
        return gid
    }

    func addObjectChange(type: ObjectChangeType, globalIdentifier: GlobalIdentifier, event: StoreModificationEvent) -> ObjectChange {
        let change = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: context) as! ObjectChange
        change.nameOfEntity = globalIdentifier.nameOfEntity
        change.objectChangeType = type
        change.storeModificationEvent = event
        change.globalIdentifier = globalIdentifier
        return change
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
    func addBaselineEvents(storeId: String, globalCounts: [GlobalCount], revisions: [RevisionNumber]) -> [StoreModificationEvent] {
        nonisolated(unsafe) var baselines: [StoreModificationEvent] = []
        context.performAndWait {
            for i in 0..<globalCounts.count {
                let event = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: context) as! StoreModificationEvent
                event.storeModificationEventType = .baseline
                event.globalCount = globalCounts[i]
                event.timestamp = 10.0
                event.modelVersion = "DEFAULT"
                let rev = EventRevision.makeEventRevision(forPersistentStoreIdentifier: storeId, revisionNumber: revisions[i], in: context)
                event.eventRevision = rev
                baselines.append(event)
            }
            try? context.save()
        }
        return baselines
    }

    @discardableResult
    func addEvents(type: StoreModificationEventType, storeId: String, globalCounts: [GlobalCount], revisions: [RevisionNumber]) -> [StoreModificationEvent] {
        nonisolated(unsafe) var events: [StoreModificationEvent] = []
        context.performAndWait {
            for i in 0..<globalCounts.count {
                let event = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: context) as! StoreModificationEvent
                event.storeModificationEventType = type
                event.globalCount = globalCounts[i]
                event.timestamp = 10.0
                let rev = EventRevision.makeEventRevision(forPersistentStoreIdentifier: storeId, revisionNumber: revisions[i], in: context)
                event.eventRevision = rev
                events.append(event)
            }
            try? context.save()
        }
        return events
    }

    func objectChange(globalId: GlobalIdentifier, valuesByKey: [String: Any]) -> ObjectChange {
        let change = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: context) as! ObjectChange
        change.objectChangeType = .insert
        change.globalIdentifier = globalId
        change.nameOfEntity = globalId.nameOfEntity

        var values: [PropertyChangeValue] = []
        for (key, obj) in valuesByKey {
            let pcv = PropertyChangeValue(type: .attribute, propertyName: key)
            pcv.value = obj as? NSObject
            values.append(pcv)
        }
        change.propertyChangeValues = values as NSArray
        return change
    }

    func fetchStoreModEvents() -> [StoreModificationEvent] {
        let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
        return (try? context.fetch(fetch)) ?? []
    }

    func fetchBaseline() -> StoreModificationEvent? {
        let fetch = NSFetchRequest<StoreModificationEvent>(entityName: "CDEStoreModificationEvent")
        fetch.predicate = NSPredicate(format: "type = %d", StoreModificationEventType.baseline.rawValue)
        return (try? context.fetch(fetch))?.last
    }

    func addMissingFile(to event: StoreModificationEvent) {
        let globalId = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: context) as! GlobalIdentifier
        globalId.globalIdentifier = "123"
        globalId.nameOfEntity = "Parent"

        let objChange = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: context) as! ObjectChange
        objChange.storeModificationEvent = event
        objChange.objectChangeType = .insert
        objChange.nameOfEntity = "Parent"
        objChange.globalIdentifier = globalId

        let dataFile = NSEntityDescription.insertNewObject(forEntityName: "CDEDataFile", into: context) as! DataFile
        dataFile.objectChange = objChange
        dataFile.filename = "filename"
    }

    func addRevisionOfOtherStoreToBaseline(_ storeId: String) {
        let baseline = try! StoreModificationEvent.fetchBaselineEvent(in: context)!
        baseline.eventRevisionsOfOtherStores = Set([addEventRevision(store: storeId, revision: 0)])
    }
}
