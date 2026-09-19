import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// A baseline that references external data is only usable once every data file it
// references is present. Until then it is held at `.baselineMissingDependencies`
// and retried each sync. That is a passing state by design: the file is in the
// cloud, so a later sync fetches it.
//
// It stops being a passing state if the file leaves the cloud. The end-of-sync
// cleanup removes every cloud data file that the SYNCING device cannot account
// for, and it accounts for them by listing two folders on disk
// (`EventStore.allDataFilenames`) — "files I happen to hold", not "files the
// history references". A device that does not hold a file another peer is still
// waiting for therefore deletes it, and that peer waits for ever: its baseline
// can never be satisfied, and every one of its syncs succeeds having integrated
// nothing.
private let starvationEnsembleID = "com.ensembles.datafilestarvation"

@MainActor
private final class StarvationDevice: NSObject, CoreDataEnsembleDelegate, @unchecked Sendable {
    let label: String
    let rootDir: String
    let context: NSManagedObjectContext
    let ensemble: CoreDataEnsemble

    init(label: String, cloud: MemoryCloudFileSystem) {
        self.label = label
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDEStarve_\(label)_\(ProcessInfo.processInfo.globallyUniqueString)")
        try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        rootDir = root

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!
        let storeURL = URL(fileURLWithPath: (root as NSString).appendingPathComponent("store.sql"))
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.persistentStoreCoordinator = psc
        context = ctx

        ensemble = CoreDataEnsemble(
            ensembleIdentifier: starvationEnsembleID,
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloud,
            localDataRootDirectoryURL: URL(fileURLWithPath: (root as NSString).appendingPathComponent("eventData"))
        )!
        super.init()
        ensemble.delegate = self
    }

    func destroy() {
        ensemble.dismantle()
        context.performAndWait {
            context.reset()
            if let store = context.persistentStoreCoordinator?.persistentStores.first {
                try? context.persistentStoreCoordinator?.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: rootDir)
    }

    /// Parents carrying blobs large enough to become external data files.
    func insertParentsWithData(count: Int) {
        context.performAndWait {
            for i in 0..<count {
                let p = NSEntityDescription.insertNewObject(forEntityName: "Parent", into: context)
                p.setValue("parent\(i)", forKey: "name")
                var bytes = Data(count: 12000)
                bytes[0] = UInt8(i + 1)
                bytes[11999] = UInt8(i + 1)
                p.setValue(bytes, forKey: "data")
            }
            try! context.save()
        }
    }

    func parentCount() -> Int {
        nonisolated(unsafe) var n = 0
        context.performAndWait {
            context.reset()
            n = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "Parent"))) ?? -1
        }
        return n
    }

    var heldBackBaselineCount: Int {
        let events = (try? ensemble.eventStore.fetchEvents(types: [.baselineMissingDependencies], persistentStoreIdentifier: nil)) ?? []
        return events.count
    }

    nonisolated func coreDataEnsemble(_ ensemble: CoreDataEnsemble, didSaveMergeChangesWith notification: Notification) {
        nonisolated(unsafe) let notif = notification
        context.performAndWait { context.mergeChanges(fromContextDidSave: notif) }
    }

    nonisolated func coreDataEnsemble(_ ensemble: CoreDataEnsemble, globalIdentifiersForManagedObjects objects: [NSManagedObject]) -> [String] {
        objects.map { ($0.value(forKey: "name") as? String) ?? $0.objectID.uriRepresentation().absoluteString }
    }
}

extension SyncTests {
@Suite("DataFileCleanupStarvation", .serialized)
@MainActor
struct DataFileCleanupStarvationTests {

    private func cloudDataFiles(_ cloud: MemoryCloudFileSystem) async -> [String] {
        let items = (try? await cloud.contentsOfDirectory(atPath: "/\(starvationEnsembleID)/data")) ?? []
        return items.map(\.name).sorted()
    }

    /// A follower holds a baseline it cannot yet use because one data file has not
    /// arrived. Another device then syncs. The cleanup must not remove the file the
    /// follower is still waiting for: nothing else can supply it, and the follower
    /// would be stranded permanently.
    @Test("A data file a peer is still waiting for survives another device's cleanup")
    func dataFileNeededByWaitingPeerIsNotDeleted() async throws {
        let cloud = MemoryCloudFileSystem()

        // Source publishes a baseline plus its data files.
        let source = StarvationDevice(label: "source", cloud: cloud)
        defer { source.destroy() }
        source.insertParentsWithData(count: 4)
        try await source.ensemble.attachPersistentStore()
        try await source.ensemble.sync()

        let published = await cloudDataFiles(cloud)
        try #require(published.count == 4, "expected four data files in the cloud")

        // A follower attaches while one file is briefly unavailable, so its baseline
        // is imported but held back.
        let withheld = published[0]
        let withheldCopy = (source.rootDir as NSString).appendingPathComponent("withheld")
        try await cloud.downloadFile(atPath: "/\(starvationEnsembleID)/data/\(withheld)", toLocalFile: withheldCopy)
        try await cloud.removeItem(atPath: "/\(starvationEnsembleID)/data/\(withheld)")

        let follower = StarvationDevice(label: "follower", cloud: cloud)
        defer { follower.destroy() }
        try await follower.ensemble.attachPersistentStore()
        try await follower.ensemble.sync()
        try #require(follower.heldBackBaselineCount == 1, "expected the follower to be holding the baseline back")
        try #require(follower.parentCount() == 0)

        // The file comes back: the follower's wait is legitimate and satisfiable.
        try await cloud.uploadLocalFile(atPath: withheldCopy, toPath: "/\(starvationEnsembleID)/data/\(withheld)")
        try #require(await cloudDataFiles(cloud).count == 4)

        // Now the SOURCE syncs again. Its own cleanup runs. It must not delete the
        // restored file, which the follower has not yet fetched.
        try await source.ensemble.sync()

        let afterCleanup = await cloudDataFiles(cloud)
        #expect(afterCleanup.contains(withheld), "the cleanup deleted a data file a peer was still waiting for")

        // And the follower must be able to finish.
        try await follower.ensemble.sync()
        #expect(follower.heldBackBaselineCount == 0, "the follower's baseline is still held back")
        #expect(follower.parentCount() == 4, "the follower never received the source's objects")
    }

    /// The same, from the other side: a device that has rebased past the history a
    /// peer is still catching up on must not strip the cloud of that peer's needs.
    @Test("A device that no longer holds a data file does not delete it from the cloud")
    func deviceWithoutFileDoesNotDeleteIt() async throws {
        let cloud = MemoryCloudFileSystem()

        let source = StarvationDevice(label: "source", cloud: cloud)
        defer { source.destroy() }
        source.insertParentsWithData(count: 3)
        try await source.ensemble.attachPersistentStore()
        try await source.ensemble.sync()
        let published = await cloudDataFiles(cloud)
        try #require(published.count == 3)

        // A second device attaches and receives everything.
        let peer = StarvationDevice(label: "peer", cloud: cloud)
        defer { peer.destroy() }
        try await peer.ensemble.attachPersistentStore()
        try await peer.ensemble.sync()
        try #require(peer.parentCount() == 3)

        // Simulate a device whose local copies are gone while the cloud still holds
        // them and another peer may still need them: delete the peer's local data
        // directory contents, then let it sync.
        let peerDataDir = (peer.rootDir as NSString).appendingPathComponent("eventData/\(starvationEnsembleID)/data")
        for f in (try? FileManager.default.contentsOfDirectory(atPath: peerDataDir)) ?? [] {
            try? FileManager.default.removeItem(atPath: (peerDataDir as NSString).appendingPathComponent(f))
        }

        try await peer.ensemble.sync()

        let after = await cloudDataFiles(cloud)
        #expect(after.count == published.count, "a device stripped the cloud of data files it no longer held locally: \(after) vs \(published)")
    }
}
}
