import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// `deleteFiles(_:inLocalDirectory:cloudDirectory:)` talks to the cloud file system
// (connect, prime, remove). Before 3.0.14 it did so on the caller's task, outside the
// ensemble's serial operation queue, so it could run while a sync was inside the same
// file system. Backends keep unsynchronized state on the strength of that queue:
// `CloudKitFileSystem` updates its listing cache from CloudKit's callback thread
// during priming, and `deleteFiles` replaced the cache dictionaries underneath that
// callback. Studies iOS 2.0 (TestFlight 201 and 203, 2026-10-19/20) crashed at launch
// this way, in `fetchZoneChanges`, every time a large library's first sync overlapped
// the app's obsolete-media cleanup.

extension SyncTests {
@Suite("DeleteFilesSerialization", .serialized)
@MainActor
struct DeleteFilesSerializationTests {

    private let rootDir: String
    private let context: NSManagedObjectContext
    private let fileSystem: GatedPrimingFileSystem
    private let ensemble: CoreDataEnsemble
    private let delegate = StubGlobalIDDelegate()

    init() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDEDeleteFiles_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        rootDir = root

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!
        let storeURL = URL(fileURLWithPath: (root as NSString).appendingPathComponent("store.sql"))
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let ctx = NSManagedObjectContext(.mainQueue)
        ctx.persistentStoreCoordinator = psc
        context = ctx

        let fs = GatedPrimingFileSystem()
        fileSystem = fs
        let ens = CoreDataEnsemble(
            ensembleIdentifier: "com.ensembles.deletefiles",
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
            if let store = context.persistentStoreCoordinator?.persistentStores.first {
                try? context.persistentStoreCoordinator?.remove(store)
            }
        }
        try? FileManager.default.removeItem(atPath: rootDir)
    }

    @Test("deleteFiles waits for a running sync before touching the cloud file system")
    func deleteFilesWaitsForSync() async throws {
        defer { tearDown() }
        try await ensemble.attachPersistentStore()

        // A local file to delete, and its cloud twin at the path deleteFiles will use.
        let localDir = (rootDir as NSString).appendingPathComponent("media")
        try FileManager.default.createDirectory(atPath: localDir, withIntermediateDirectories: true)
        let filename = "obsolete.png"
        try Data([1, 2, 3]).write(to: URL(fileURLWithPath: (localDir as NSString).appendingPathComponent(filename)))
        let cloudPath = "/\(ensemble.ensembleIdentifier)/files/media/" + filename
        await fileSystem.inner.createFile(atPath: cloudPath, data: Data([1, 2, 3]))

        // Hold the sync inside priming, as a long CloudKit zone fetch would.
        fileSystem.holdPriming = true
        let sync = Task { try await ensemble.sync() }
        // Attach primed once already; the sync's priming is the second call.
        try await fileSystem.waitForPriming(count: 2)
        let callsBeforeDelete = fileSystem.calls.count

        // While the sync is held, deleteFiles must delete locally and then wait.
        let delete = Task { try await ensemble.deleteFiles([filename], inLocalDirectory: localDir, cloudDirectory: "media") }
        let deleteStarted = Date()
        while FileManager.default.fileExists(atPath: (localDir as NSString).appendingPathComponent(filename)) {
            try #require(Date().timeIntervalSince(deleteStarted) < 5, "local delete never happened")
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(fileSystem.calls.count == callsBeforeDelete, "deleteFiles reached the cloud file system while a sync was inside it: \(fileSystem.calls)")

        // Release the sync; the cloud deletion then runs after it.
        fileSystem.holdPriming = false
        try await sync.value
        try await delete.value

        #expect(fileSystem.calls.contains("removeItems"))
        let gone = try await fileSystem.inner.fileExists(atPath: cloudPath)
        #expect(!gone.exists)
    }
}
}
