import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// Where the file-content APIs put files in the cloud. Ensembles 2 resolved every
// relative cloud path inside the ensemble's files directory (`/<ensemble>/files/`).
// Ensembles 3.0.0 to 3.0.13 did the same for `mergeFileContent` and `deleteFiles` but
// resolved `alwaysMergeFileContent` registrations from the cloud root; 3.0.14 moved
// them under the files directory and doubled a path that already named it. 3.0.15:
// the files directory for all three, a path that already starts with
// `<ensemble>/files/` is used as it is, and files left at the old root location by
// earlier Ensembles 3 versions are still downloaded so nothing is stranded.

extension SyncTests {
@Suite("FileContentLocation", .serialized)
@MainActor
struct FileContentLocationTests {

    private let rootDir: String
    private let context: NSManagedObjectContext
    private let cloud: MemoryCloudFileSystem
    private let ensemble: CoreDataEnsemble
    private let delegate = StubGlobalIDDelegate()
    private let ensembleID = "com.ensembles.filecontent"

    init() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("CDEFileContent_\(ProcessInfo.processInfo.globallyUniqueString)")
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
        let fs = MemoryCloudFileSystem()
        cloud = fs
        let ens = CoreDataEnsemble(
            ensembleIdentifier: ensembleID,
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

    private func makeLocalDirectory(_ name: String, files: [String]) throws -> String {
        let dir = (rootDir as NSString).appendingPathComponent(name)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for file in files {
            try Data([1]).write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(file)))
        }
        return dir
    }

    private func cloudHas(_ path: String) async throws -> Bool {
        try await cloud.fileExists(atPath: path).exists
    }

    @Test("A short name registered with alwaysMergeFileContent lands in the ensemble's files directory, as in Ensembles 2")
    func shortNameGoesToFilesDirectory() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: ["a.bin"])
        try await ensemble.attachPersistentStore()
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "media")
        try await ensemble.sync()
        #expect(try await cloudHas("/\(ensembleID)/files/media/a.bin"))
        #expect(!(try await cloudHas("/media/a.bin")))
    }

    @Test("A path that already names the files directory is not doubled")
    func fullPathIsNotDoubled() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: ["a.bin"])
        try await ensemble.attachPersistentStore()
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "\(ensembleID)/files/media")
        try await ensemble.sync()
        #expect(try await cloudHas("/\(ensembleID)/files/media/a.bin"))
        #expect(!(try await cloudHas("/\(ensembleID)/files/\(ensembleID)/files/media/a.bin")))
    }

    @Test("Files left at the old root location by earlier Ensembles 3 versions are still downloaded")
    func legacyRootLocationIsRead() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: ["new.bin"])
        // A device on 3.0.13 put this file at the cloud root.
        try await cloud.createDirectory(atPath: "/media")
        await cloud.createFile(atPath: "/media/old.bin", data: Data([2]))
        try await ensemble.attachPersistentStore()
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "media")
        try await ensemble.sync()

        #expect(FileManager.default.fileExists(atPath: (localDir as NSString).appendingPathComponent("old.bin")), "the old-location file was not downloaded")
        // Read only: the old location is left as it is for devices still writing there.
        #expect(try await cloudHas("/media/old.bin"))
        #expect(!(try await cloudHas("/media/new.bin")), "nothing is uploaded to the old location")
        #expect(try await cloudHas("/\(ensembleID)/files/media/new.bin"))
    }

    @Test("A registered name equal to the ensemble identifier never reads the ensemble's own directory as a legacy location")
    func legacyReadSkipsEnsembleDirectory() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: [])
        try await ensemble.attachPersistentStore()
        try await ensemble.sync()
        // Registered with the ensemble's own identifier: the "old location" would be
        // the ensemble directory itself (stores, events, baselines, data).
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: ensembleID)
        try await ensemble.sync()
        let downloaded = try FileManager.default.contentsOfDirectory(atPath: localDir)
        #expect(downloaded.isEmpty, "pulled the ensemble's own directories: \(downloaded)")
    }

    @Test("Subdirectories at the old location are skipped, files are downloaded")
    func legacyReadSkipsSubdirectories() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: [])
        try await cloud.createDirectory(atPath: "/media")
        try await cloud.createDirectory(atPath: "/media/sub")
        await cloud.createFile(atPath: "/media/sub/inner.bin", data: Data([4]))
        await cloud.createFile(atPath: "/media/old.bin", data: Data([2]))
        try await ensemble.attachPersistentStore()
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "media")
        try await ensemble.sync()
        let downloaded = Set(try FileManager.default.contentsOfDirectory(atPath: localDir))
        #expect(downloaded == ["old.bin"], "got \(downloaded)")
    }

    @Test("deleteFiles also removes the copy at the old root location, so it does not come back")
    func deleteFilesRemovesLegacyCopy() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: ["x.bin"])
        try await cloud.createDirectory(atPath: "/media")
        await cloud.createFile(atPath: "/media/x.bin", data: Data([5]))
        try await ensemble.attachPersistentStore()
        ensemble.alwaysMergeFileContent(inLocalDirectory: localDir, withCloudDirectory: "media")
        try await ensemble.sync()
        try #require(try await cloudHas("/\(ensembleID)/files/media/x.bin"))

        try await ensemble.deleteFiles(["x.bin"], inLocalDirectory: localDir, cloudDirectory: "media")
        #expect(!(try await cloudHas("/\(ensembleID)/files/media/x.bin")))
        #expect(!(try await cloudHas("/media/x.bin")))

        try await ensemble.sync()
        #expect(!FileManager.default.fileExists(atPath: (localDir as NSString).appendingPathComponent("x.bin")), "the deleted file came back")
    }

    @Test("deleteFiles with a path that already names the files directory deletes the right cloud file")
    func deleteFilesFullPathIsNotDoubled() async throws {
        defer { tearDown() }
        let localDir = try makeLocalDirectory("media", files: ["gone.bin"])
        try await ensemble.attachPersistentStore()
        try await cloud.createDirectory(atPath: "/\(ensembleID)/files/media")
        await cloud.createFile(atPath: "/\(ensembleID)/files/media/gone.bin", data: Data([3]))
        try await ensemble.deleteFiles(["gone.bin"], inLocalDirectory: localDir, cloudDirectory: "\(ensembleID)/files/media")
        #expect(!(try await cloudHas("/\(ensembleID)/files/media/gone.bin")))
    }
}
}
