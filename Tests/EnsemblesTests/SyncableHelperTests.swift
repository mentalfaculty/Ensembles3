import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// MARK: - Test Model Classes

@objc(SyncableHelperItem)
final class SyncableHelperItem: NSManagedObject, Syncable {
    static let globalIdentifierKey = "uniqueID"
}

@objc(SyncableHelperComputed)
final class SyncableHelperComputed: NSManagedObject, Syncable {
    static func globalIdentifier(from instance: SyncableHelperComputed) -> String {
        let first = instance.value(forKey: "firstName") as? String ?? ""
        let last = instance.value(forKey: "lastName") as? String ?? ""
        return "\(first).\(last)"
    }
}

// MARK: - Tests

/// Covers `CoreDataEnsemble.syncableGlobalIdentifiers(forManagedObjects:)`, the
/// helper that lets a direct-ensemble delegate forward to `Syncable` in one
/// line. Uses a programmatic model: the shared test model's entity hashes must
/// not change, and it has no `Syncable` classes.
///
/// Nested in `SyncTests` because the ensemble's `SaveMonitor` observes save
/// notifications with `object: nil` — running in parallel with other sync
/// suites causes cross-talk.
extension SyncTests {
@Suite("SyncableHelper", .serialized)
@MainActor
struct SyncableHelperTests {

    let rootDir: String
    let context: NSManagedObjectContext
    let ensemble: CoreDataEnsemble

    static func makeModel() -> NSManagedObjectModel {
        func attribute(_ name: String) -> NSAttributeDescription {
            let attr = NSAttributeDescription()
            attr.name = name
            attr.attributeType = .stringAttributeType
            attr.isOptional = true
            return attr
        }

        let item = NSEntityDescription()
        item.name = "Item"
        item.managedObjectClassName = "SyncableHelperItem"
        item.properties = [attribute("uniqueID")]

        let computed = NSEntityDescription()
        computed.name = "Computed"
        computed.managedObjectClassName = "SyncableHelperComputed"
        computed.properties = [attribute("firstName"), attribute("lastName")]

        let plain = NSEntityDescription()
        plain.name = "Plain"
        plain.properties = [attribute("name")]

        let model = NSManagedObjectModel()
        model.entities = [item, computed, plain]
        return model
    }

    init() throws {
        let root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("SyncableHelperTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        self.rootDir = root

        let model = Self.makeModel()
        let storeURL = URL(fileURLWithPath: (root as NSString).appendingPathComponent("store.sqlite"))
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)

        let moc = NSManagedObjectContext(.mainQueue)
        moc.persistentStoreCoordinator = psc
        self.context = moc

        let ens = CoreDataEnsemble(
            ensembleIdentifier: "syncablehelper",
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModel: model,
            managedObjectModels: [model],
            cloudFileSystem: MemoryCloudFileSystem(),
            localDataRootDirectoryURL: URL(fileURLWithPath: (root as NSString).appendingPathComponent("eventData"))
        )!
        self.ensemble = ens
    }

    @Test("Derives key-based and computed identifiers in order")
    func derivesIdentifiers() {
        let ctx = context
        nonisolated(unsafe) var ids: [String] = []
        context.performAndWait {
            let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: ctx)
            item.setValue("id-123", forKey: "uniqueID")
            let computed = NSEntityDescription.insertNewObject(forEntityName: "Computed", into: ctx)
            computed.setValue("Ada", forKey: "firstName")
            computed.setValue("Lovelace", forKey: "lastName")
            ids = ensemble.syncableGlobalIdentifiers(forManagedObjects: [item, computed])
        }
        #expect(ids == ["id-123", "Ada.Lovelace"])
        ensemble.dismantle()
        cleanup()
    }

    @Test("A batch containing a non-Syncable entity fails closed")
    func nonSyncableFailsClosed() {
        let ctx = context
        nonisolated(unsafe) var ids: [String] = ["sentinel"]
        context.performAndWait {
            let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: ctx)
            item.setValue("id-123", forKey: "uniqueID")
            let plain = NSEntityDescription.insertNewObject(forEntityName: "Plain", into: ctx)
            plain.setValue("no conformance", forKey: "name")
            ids = ensemble.syncableGlobalIdentifiers(forManagedObjects: [item, plain])
        }
        #expect(ids.isEmpty)
        ensemble.dismantle()
        cleanup()
    }

    @Test("A one-line forwarding delegate carries Syncable identifiers into the event store")
    func forwardingDelegateEndToEnd() async throws {
        let delegate = ForwardingDelegate()
        ensemble.delegate = delegate

        try await ensemble.attachPersistentStore()

        let ctx = context
        nonisolated(unsafe) var objectID: NSManagedObjectID!
        context.performAndWait {
            let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: ctx)
            item.setValue("id-e2e", forKey: "uniqueID")
            try! ctx.save()
            try! ctx.obtainPermanentIDs(for: [item])
            objectID = item.objectID
        }

        try await ensemble.sync()

        let stored = try ensemble.eventStore.fetchGlobalIdentifiers(forObjectIDs: [objectID])
        #expect(stored.compactMap { $0?.globalIdentifier } == ["id-e2e"])

        ensemble.dismantle()
        cleanup()
    }

    private func cleanup() {
        let ctx = context
        context.performAndWait {
            ctx.reset()
            if let store = ctx.persistentStoreCoordinator?.persistentStores.first {
                try? ctx.persistentStoreCoordinator?.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: rootDir)
    }
}
}

// MARK: - Delegate

private final class ForwardingDelegate: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {}

    func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String] {
        ensemble.syncableGlobalIdentifiers(forManagedObjects: objects)
    }
}
