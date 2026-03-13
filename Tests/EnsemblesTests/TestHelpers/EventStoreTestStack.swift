import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

/// Thread-safe cache for NSManagedObjectModel instances.
/// Loading the same .momd concurrently into separate model instances causes CoreData
/// internal issues when tests run in parallel. This cache ensures each model URL is
/// loaded exactly once.
enum TestModelCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var models: [URL: NSManagedObjectModel] = [:]

    static func model(for url: URL) -> NSManagedObjectModel? {
        lock.withLock {
            if let cached = models[url] { return cached }
            guard let model = NSManagedObjectModel(contentsOf: url) else { return nil }
            models[url] = model
            return model
        }
    }
}

/// Helper to create an in-memory Core Data stack with the CDEEventStoreModel.
/// The model is bundled as a resource in the Ensembles target.
struct EventStoreTestStack: @unchecked Sendable {
    let context: NSManagedObjectContext
    let model: NSManagedObjectModel

    init() throws {
        guard let url = EventStore.eventStoreModelURL else {
            throw TestError("Could not find CDEEventStoreModel.momd resource")
        }
        guard let model = TestModelCache.model(for: url) else {
            throw TestError("Could not load managed object model from \(url)")
        }
        self.model = model

        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        try psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: options)
        let moc = NSManagedObjectContext(.privateQueue)
        moc.persistentStoreCoordinator = psc
        self.context = moc
    }

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

    // MARK: Property Change Value Helpers

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
}

struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Minimal ensemble that provides global identifiers for SaveMonitor and integrator tests.
final class TestEnsemble: EventBuilderEnsembleProtocol, EventIntegratorEnsembleProtocol, @unchecked Sendable {
    var managedObjectModels: [NSManagedObjectModel]?
    var modelVersionHash: String? { nil }
    var modelVersionIdentifier: String? { nil }
    var nonCriticalErrorCodes: Set<Int>?

    func globalIdentifiers(forManagedObjects objects: [NSManagedObject]) -> [String?] {
        objects.map { _ in ProcessInfo.processInfo.globallyUniqueString }
    }
}
