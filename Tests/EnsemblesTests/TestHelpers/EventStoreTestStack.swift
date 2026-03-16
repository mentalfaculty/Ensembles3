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

/// Helper to create an EventStore backed by SQLite in a temp directory.
/// Used by tests that need an event store for creating events, revisions, etc.
struct EventStoreTestStack: @unchecked Sendable {
    let eventStore: EventStore
    let tempDirectory: String

    init() throws {
        tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("EnsemblesTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: tempDirectory, withIntermediateDirectories: true)

        let eventStoreDir = (tempDirectory as NSString).appendingPathComponent("test")
        try FileManager.default.createDirectory(atPath: eventStoreDir, withIntermediateDirectories: true)

        guard let store = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: tempDirectory) else {
            throw TestError("Could not create EventStore")
        }
        try store.prepareNewEventStore()
        self.eventStore = store
    }

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
