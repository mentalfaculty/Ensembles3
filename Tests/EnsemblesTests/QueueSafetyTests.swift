import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// Three entry points that reached shared state from outside the ensemble's serial
// operation queue, found by the sweep that followed the Studies launch crash
// (2026-10-20, see DeleteFilesSerializationTests):
//
// - `dismantle()` closed the event store at once, while a queued sync could still be
//   using it.
// - `alwaysMergeFileContent` wrote a dictionary that a running sync iterates.
// - `SaveMonitor` kept its per-context pre-save values in an NSMapTable with no lock,
//   although two contexts of one store can save at the same time on two threads.

extension SyncTests {
@Suite("QueueSafety", .serialized)
@MainActor
struct QueueSafetyTests {

    private let rootDir: String
    private let coordinator: NSPersistentStoreCoordinator
    private let context: NSManagedObjectContext
    private let fileSystem: GatedPrimingFileSystem
    private let ensemble: CoreDataEnsemble
    private let delegate = StubGlobalIDDelegate()

    init() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDEQueueSafety_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        rootDir = root

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!
        let storeURL = URL(fileURLWithPath: (root as NSString).appendingPathComponent("store.sql"))
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        coordinator = psc
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.persistentStoreCoordinator = psc
        context = ctx

        let fs = GatedPrimingFileSystem()
        fileSystem = fs
        let ens = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.queuesafety",
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: fs,
            localDataRootDirectoryURL: URL(fileURLWithPath: (root as NSString).appendingPathComponent("eventData"))
        )!
        ens.delegate = delegate
        ensemble = ens
    }

    private func tearDown() {
        ensemble.dismantle()
        context.performAndWait {
            context.reset()
            if let store = coordinator.persistentStores.first {
                try? coordinator.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: rootDir)
    }

    private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
        let started = Date()
        while !condition() {
            try #require(Date().timeIntervalSince(started) < 5, "timed out waiting for \(what)")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: - dismantle

    @Test("dismantle during a sync closes the event store only after the sync's work has ended")
    func dismantleWaitsForRunningSync() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()

        fileSystem.holdPriming = true
        let sync = Task { try await ensemble.sync() }
        try await fileSystem.waitForPriming(count: 2)

        // The sync is inside the file system. Dismantling now must not pull the
        // event store out from under it, and it must still be open while the sync
        // stays in there.
        ensemble.dismantle()
        await GatedPrimingFileSystem.pause(milliseconds: 200)
        #expect(ensemble.eventStore.database != nil, "event store closed while a sync was still running")
        #expect(ensemble.eventStore.database?.isOpen == true)

        // Released, the sync stops at its next phase boundary with `cancelled`, and
        // only then does the event store close.
        fileSystem.holdPriming = false
        let outcome = await sync.result
        #expect((outcome.failure as? EnsembleError) == .cancelled, "expected the running sync to stop with cancelled, got \(String(describing: outcome))")
        try await waitUntil("event store to close after the sync") { ensemble.eventStore.database == nil }
    }

    @Test("A sync queued behind a running one fails with cancelled at dismantle instead of hanging")
    func queuedSyncIsCancelledAtDismantle() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()

        fileSystem.holdPriming = true
        let running = Task { try await ensemble.sync() }
        try await fileSystem.waitForPriming(count: 2)
        let queued = Task { try await ensemble.sync() }
        await GatedPrimingFileSystem.pause(milliseconds: 100)

        ensemble.dismantle()
        fileSystem.holdPriming = false
        _ = await running.result

        // Bounded: before 3.0.14's fix the queued caller was never resumed.
        let outcome: Result<Void, Error>? = await withTaskGroup(of: Result<Void, Error>?.self) { group in
            group.addTask { await queued.result }
            group.addTask { try? await Task.sleep(nanoseconds: 5_000_000_000); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(outcome != nil, "the queued sync never returned")
        #expect((outcome?.failure as? EnsembleError) == .cancelled)
        // The queued sync never reached the file system: attach and the running sync
        // primed once each, nothing more.
        #expect(fileSystem.calls.filter { $0 == "primeForActivity" }.count == 2)
    }

    @Test("dismantle with nothing running closes the event store before it returns")
    func dismantleIdleClosesAtOnce() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()
        ensemble.dismantle()
        // A replacement ensemble for the same store must be able to open it at once.
        #expect(ensemble.eventStore.database == nil)
    }

    // MARK: - alwaysMergeFileContent

    @Test("A directory registered while a sync runs is merged by the next sync")
    func mergeDirectoryRegisteredDuringSync() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()

        let localDir = (rootDir as NSString).appendingPathComponent("attachments")
        try FileManager.default.createDirectory(atPath: localDir, withIntermediateDirectories: true)
        try Data([9]).write(to: URL(fileURLWithPath: (localDir as NSString).appendingPathComponent("a.bin")))

        fileSystem.holdPriming = true
        let sync = Task { try await ensemble.sync() }
        try await fileSystem.waitForPriming(count: 2)

        // Registered from another task while the sync is in flight. This cannot show
        // the unsynchronized write the lock now prevents; it proves the registration
        // is honoured and that nothing is lost across the overlap.
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "attachments")
        fileSystem.holdPriming = false
        try await sync.value

        try await ensemble.sync()
        let uploaded = try await fileSystem.inner.fileExists(atPath: "/\(ensemble.ensembleIdentifier)/files/attachments/a.bin")
        #expect(uploaded.exists)
    }

    // MARK: - Opening a store another connection still holds

    private var eventDatabasePath: String {
        (ensemble.eventStore.pathToEventStoreRootDirectory as NSString).appendingPathComponent("eventstore.db")
    }

    private func makeReplacementEnsemble() -> CoreDataEnsemble? {
        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        return CoreDataEnsemble(
            ensembleIdentifier: ensemble.ensembleIdentifier,
            persistentStoreURL: ensemble.persistentStoreURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: TestModelCache.model(for: modelURL)!,
            cloudFileSystem: fileSystem,
            localDataRootDirectoryURL: URL(fileURLWithPath: (rootDir as NSString).appendingPathComponent("eventData"))
        )
    }

    @Test("A replacement ensemble waits for a connection that still holds the event store, and keeps the local data")
    func replacementWaitsForHeldStore() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()
        ensemble.dismantle()

        // Another connection holds the write lock for a moment, as the old ensemble's
        // last phase does when it is dismantled mid-sync and replaced at once.
        let holder = try SQLiteDatabase(path: eventDatabasePath)
        try holder.execute("BEGIN EXCLUSIVE")
        let release = Task.detached {
            await GatedPrimingFileSystem.pause(milliseconds: 1000)
            _ = try? holder.execute("COMMIT")
            holder.close()
        }

        let replacement = makeReplacementEnsemble()
        _ = await release.result
        defer { replacement?.dismantle() }

        // Before 3.0.14 the open failed at once, the init "recovered" by deleting the
        // event data, and the replacement came up as a fresh, unattached store.
        #expect(replacement != nil)
        #expect(replacement?.isAttached == true, "the replacement lost the store's event data")
        #expect(FileManager.default.fileExists(atPath: eventDatabasePath))
    }

    @Test("A store locked for longer than the busy wait fails to open and keeps the local data")
    func lockedStoreFailsToOpenWithoutDeletingData() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()
        ensemble.dismantle()

        // Process-wide. No other test opens two connections to one database, so a
        // suite running in parallel cannot be hit by the short window.
        let previousTimeout = SQLiteDatabase.busyTimeoutMilliseconds
        SQLiteDatabase.busyTimeoutMilliseconds = 200
        defer { SQLiteDatabase.busyTimeoutMilliseconds = previousTimeout }

        let holder = try SQLiteDatabase(path: eventDatabasePath)
        try holder.execute("BEGIN EXCLUSIVE")
        defer { _ = try? holder.execute("COMMIT"); holder.close() }

        let metadataPath = (ensemble.eventStore.pathToEventStoreRootDirectory as NSString).appendingPathComponent("store-metadata.plist")
        try #require(FileManager.default.fileExists(atPath: metadataPath))

        let replacement = makeReplacementEnsemble()
        defer { replacement?.dismantle() }
        #expect(replacement == nil, "an ensemble must not come up on a store it could not open")
        #expect(FileManager.default.fileExists(atPath: eventDatabasePath), "the event database was deleted")
        #expect(FileManager.default.fileExists(atPath: metadataPath), "the store metadata was deleted")
    }

    // MARK: - SaveMonitor

    @Test("Saves on two contexts at the same time are all captured")
    func concurrentSavesAreCaptured() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()

        // Two private-queue contexts of the same store, each saving on its own
        // thread, so the monitor's will-save and did-save handlers run concurrently.
        let savesPerContext = 150
        let coordinator = self.coordinator
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    let ctx = NSManagedObjectContext(.privateQueue)
                    ctx.persistentStoreCoordinator = coordinator
                    for _ in 0..<savesPerContext {
                        ctx.performAndWait {
                            NSEntityDescription.insertNewObject(forEntityName: "Parent", into: ctx)
                            try? ctx.save()
                        }
                    }
                }
            }
        }

        try await ensemble.processPendingChanges()
        let saveEvents = try ensemble.eventStore.fetchEvents(types: [.save], persistentStoreIdentifier: nil)
        #expect(saveEvents.count == 2 * savesPerContext)
    }
}
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
