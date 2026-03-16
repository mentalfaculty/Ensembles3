import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

@Suite("CloudManagerTests", .serialized)
struct CloudManagerTests {

    let setup: TestEventStoreSetup
    let cloudFS: MemoryCloudFileSystem
    let cloudManager: CloudManager

    init() throws {
        let s = try TestEventStoreSetup(loadTestModel: true)
        let fs = MemoryCloudFileSystem()
        let cm = CloudManager(eventStore: s.eventStore, cloudFileSystem: fs, managedObjectModel: s.testModel!)
        self.setup = s
        self.cloudFS = fs
        self.cloudManager = cm
    }

    private var ensembleId: String { setup.eventStore.ensembleIdentifier }
    private var remoteEventsDir: String { "/\(ensembleId)/events" }
    private var remoteBaselinesDir: String { "/\(ensembleId)/baselines" }
    private var remoteStoresDir: String { "/\(ensembleId)/stores" }
    private var remoteDataDir: String { "/\(ensembleId)/data" }

    // MARK: - Directory Creation

    @Test("Create remote event directory")
    func createRemoteEventDirectory() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        let existence = try await cloudFS.fileExists(atPath: remoteEventsDir)
        #expect(existence.exists)
        #expect(existence.isDirectory)
    }

    @Test("Create remote event directory idempotent")
    func createRemoteEventDirectoryIdempotent() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.createRemoteDirectoryStructure()
        let existence = try await cloudFS.fileExists(atPath: remoteEventsDir)
        #expect(existence.exists)
        #expect(existence.isDirectory)
    }

    @Test("Create remote stores directory")
    func createRemoteStoresDirectory() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        let existence = try await cloudFS.fileExists(atPath: remoteStoresDir)
        #expect(existence.exists)
    }

    @Test("Create remote baselines directory")
    func createRemoteBaselinesDirectory() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        let existence = try await cloudFS.fileExists(atPath: remoteBaselinesDir)
        #expect(existence.exists)
    }

    @Test("Create remote data directory")
    func createRemoteDataDirectory() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        let existence = try await cloudFS.fileExists(atPath: remoteDataDir)
        #expect(existence.exists)
    }

    // MARK: - Import/Export

    @Test("Import with no data")
    func importWithNoData() async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.importNewRemoteNonBaselineEvents()
    }

    @Test("Import with invalid data")
    func importWithInvalidData() async throws {
        try await cloudManager.createRemoteDirectoryStructure()

        // Upload an invalid file to the events directory
        let invalidData = "Test data".data(using: .utf8)!
        await cloudFS.createFile(atPath: "\(remoteEventsDir)/0_store1_0.cdeevent", data: invalidData)

        try await cloudManager.snapshotRemoteFiles()
        await #expect(throws: (any Error).self) {
            try await cloudManager.importNewRemoteNonBaselineEvents()
        }
    }

    @Test("Export populates cloud")
    func exportPopulatesCloud() async throws {
        let storeId = setup.persistentStoreIdentifier
        try setup.addModEvent(store: storeId, revision: 0, globalCount: 0, timestamp: 0.0)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalNonBaselineEvents()

        let expectedPath = "\(remoteEventsDir)/0_\(storeId)_0.cdeevent"
        let existence = try await cloudFS.fileExists(atPath: expectedPath)
        #expect(existence.exists)
        #expect(!existence.isDirectory)
    }

    @Test("Export cleans up transit cache")
    func exportCleansUpTransitCache() async throws {
        let storeId = setup.persistentStoreIdentifier
        try setup.addModEvent(store: storeId, revision: 1, globalCount: 2, timestamp: 0.0)
        try setup.addModEvent(store: storeId, revision: 4, globalCount: 7, timestamp: 0.1)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalNonBaselineEvents()

        let uploadDir = setup.eventStore.pathToEventDataRootDirectory + "/transitcache/\(ensembleId)/upload"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: uploadDir)) ?? []
        #expect(files.count == 0)
    }

    @Test("Export populates cloud with correct file count")
    func exportPopulatesTransitCache() async throws {
        let storeId = setup.persistentStoreIdentifier
        try setup.addModEvent(store: storeId, revision: 1, globalCount: 2, timestamp: 0.0)
        try setup.addModEvent(store: storeId, revision: 4, globalCount: 7, timestamp: 0.1)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalNonBaselineEvents()

        let contents = try await cloudFS.contentsOfDirectory(atPath: remoteEventsDir)
        #expect(contents.count == 2)
    }

    @Test("Migrate from cloud populates event store")
    func migrateFromCloudPopulatesEventStore() async throws {
        // Export an event to cloud
        let storeId = setup.persistentStoreIdentifier
        let event = try setup.addModEvent(store: storeId, revision: 1, globalCount: 2, timestamp: 0.0)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalNonBaselineEvents()

        // Delete the event from the local event store
        try setup.eventStore.deleteEvent(id: event.id)

        // Verify it's gone
        let fetched1 = try setup.eventStore.fetchNonBaselineEvent(forPersistentStoreIdentifier: storeId, revisionNumber: 1)
        #expect(fetched1 == nil)

        // Import from cloud into the same cloud manager
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.importNewRemoteNonBaselineEvents()

        // Verify the event is back
        let fetched2 = try setup.eventStore.fetchNonBaselineEvent(forPersistentStoreIdentifier: storeId, revisionNumber: 1)
        #expect(fetched2 != nil)
    }

    // MARK: - Removal

    @Test("Remove out of date event files")
    func removeOutOfDateEventFiles() async throws {
        let storeId = setup.persistentStoreIdentifier
        try setup.addModEvent(store: storeId, revision: 2, globalCount: 12, timestamp: 0.0)
        try setup.addModEvent(store: "abc", revision: 2, globalCount: 12, timestamp: 0.0)

        let path1 = "\(remoteEventsDir)/12_\(storeId)_2.cdeevent"
        let path2 = "\(remoteEventsDir)/11_\(storeId)_3_1of2.cdeevent"
        let path3 = "\(remoteEventsDir)/11_\(storeId)_3_2of2.cdeevent"
        let path4 = "\(remoteEventsDir)/12_abc_2_1of2.cdeevent"
        let path5 = "\(remoteEventsDir)/12_abc_2_2of2.cdeevent"
        let path6 = "\(remoteEventsDir)/13_abc_3_1of2.cdeevent"
        let path7 = "\(remoteEventsDir)/unknown.cdeevent"

        let emptyData = Data()
        await cloudFS.createFile(atPath: path1, data: emptyData)
        await cloudFS.createFile(atPath: path2, data: emptyData)
        await cloudFS.createFile(atPath: path3, data: emptyData)
        await cloudFS.createFile(atPath: path4, data: emptyData)
        await cloudFS.createFile(atPath: path5, data: emptyData)
        await cloudFS.createFile(atPath: path6, data: emptyData)
        await cloudFS.createFile(atPath: path7, data: emptyData)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.removeOutdatedRemoteFiles()

        // path1: should be kept (event exists in store)
        #expect((try await cloudFS.fileExists(atPath: path1)).exists)
        // path2, path3: should be removed (outdated, superseded by revision 2)
        #expect(!(try await cloudFS.fileExists(atPath: path2)).exists)
        #expect(!(try await cloudFS.fileExists(atPath: path3)).exists)
        // path4, path5: should be kept (event exists in store for "abc")
        #expect((try await cloudFS.fileExists(atPath: path4)).exists)
        #expect((try await cloudFS.fileExists(atPath: path5)).exists)
        // path6: should be kept (incomplete set from other device)
        #expect((try await cloudFS.fileExists(atPath: path6)).exists)
        // path7: should be kept (unknown format)
        #expect((try await cloudFS.fileExists(atPath: path7)).exists)
    }

    @Test("Remove out of date baseline files")
    func removeOutOfDateBaselineFiles() async throws {
        let baseline = try setup.eventStore.insertEvent(
            uniqueIdentifier: "123",
            type: .baseline,
            timestamp: 0.0,
            globalCount: 12
        )
        try setup.eventStore.insertRevision(persistentStoreIdentifier: "store1", revisionNumber: 2, eventId: baseline.id, isEventRevision: true)

        let path1 = "\(remoteBaselinesDir)/12_123_store1_1of2.cdeevent"
        let path2 = "\(remoteBaselinesDir)/12_123_store1_2of2.cdeevent"
        let path3 = "\(remoteBaselinesDir)/13_123_store1.cdeevent"
        let path4 = "\(remoteBaselinesDir)/14_123_store1_1of2.cdeevent"

        let emptyData = Data()
        await cloudFS.createFile(atPath: path1, data: emptyData)
        await cloudFS.createFile(atPath: path2, data: emptyData)
        await cloudFS.createFile(atPath: path3, data: emptyData)
        await cloudFS.createFile(atPath: path4, data: emptyData)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.removeOutdatedRemoteFiles()

        // path1, path2: should be kept (complete multipart set matching baseline)
        #expect((try await cloudFS.fileExists(atPath: path1)).exists)
        #expect((try await cloudFS.fileExists(atPath: path2)).exists)
        // path3: should be removed (outdated single-part, superseded by multipart)
        #expect(!(try await cloudFS.fileExists(atPath: path3)).exists)
        // path4: should be kept (incomplete set, not deleted)
        #expect((try await cloudFS.fileExists(atPath: path4)).exists)
    }

    @Test("Remove locally produced incomplete file sets")
    func removeLocallyProducedIncompleteFileSets() async throws {
        let storeId = setup.persistentStoreIdentifier

        let path1 = "\(remoteEventsDir)/12_\(storeId)_2.cdeevent"
        let path2 = "\(remoteEventsDir)/11_\(storeId)_3_1of2.cdeevent"
        let path3 = "\(remoteEventsDir)/11_\(storeId)_3_2of2.cdeevent"
        let path4 = "\(remoteEventsDir)/12_abc_2_1of2.cdeevent"
        let path5 = "\(remoteEventsDir)/12_\(storeId)_2_1of2.cdeevent"
        let path6 = "\(remoteEventsDir)/unknown.cdeevent"
        let path7 = "\(remoteBaselinesDir)/14_123_abc_1of2.cdeevent"
        let path8 = "\(remoteBaselinesDir)/14_123_\(storeId)_1of2.cdeevent"
        let path9 = "\(remoteBaselinesDir)/14_123_\(storeId)_2of2.cdeevent"
        let path10 = "\(remoteBaselinesDir)/13_123_\(storeId)_2of2.cdeevent"

        let emptyData = Data()
        await cloudFS.createFile(atPath: path1, data: emptyData)
        await cloudFS.createFile(atPath: path2, data: emptyData)
        await cloudFS.createFile(atPath: path3, data: emptyData)
        await cloudFS.createFile(atPath: path4, data: emptyData)
        await cloudFS.createFile(atPath: path5, data: emptyData)
        await cloudFS.createFile(atPath: path6, data: emptyData)
        await cloudFS.createFile(atPath: path7, data: emptyData)
        await cloudFS.createFile(atPath: path8, data: emptyData)
        await cloudFS.createFile(atPath: path9, data: emptyData)
        await cloudFS.createFile(atPath: path10, data: emptyData)

        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.removeLocallyProducedIncompleteRemoteFileSets()

        // path1: kept (single part, complete)
        #expect((try await cloudFS.fileExists(atPath: path1)).exists)
        // path2, path3: kept (complete multipart)
        #expect((try await cloudFS.fileExists(atPath: path2)).exists)
        #expect((try await cloudFS.fileExists(atPath: path3)).exists)
        // path4: kept (from other device "abc")
        #expect((try await cloudFS.fileExists(atPath: path4)).exists)
        // path5: removed (incomplete multipart from local store)
        #expect(!(try await cloudFS.fileExists(atPath: path5)).exists)
        // path6: kept (unknown format)
        #expect((try await cloudFS.fileExists(atPath: path6)).exists)
        // path7: kept (baseline from another device)
        #expect((try await cloudFS.fileExists(atPath: path7)).exists)
        // path8, path9: kept (complete baseline multipart)
        #expect((try await cloudFS.fileExists(atPath: path8)).exists)
        #expect((try await cloudFS.fileExists(atPath: path9)).exists)
        // path10: removed (incomplete baseline multipart from local store)
        #expect(!(try await cloudFS.fileExists(atPath: path10)).exists)
    }

    // MARK: - Incomplete File Handling

    @Test("Incomplete remote file set does not trigger error")
    func incompleteRemoteFileSetDoesNotTriggerError() async throws {
        try await cloudManager.createRemoteDirectoryStructure()

        // Upload only an incomplete multipart set (1 of 2 parts)
        await cloudFS.createFile(atPath: "\(remoteEventsDir)/12_abc_2_1of2.cdeevent", data: Data([0x01]))

        // Snapshot and import should succeed — incomplete sets are skipped
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.importNewRemoteNonBaselineEvents()

        // The incomplete file should not have been downloaded to the transit cache
        let downloadDir = setup.eventStore.pathToEventDataRootDirectory + "/transitcache/\(ensembleId)/download"
        let incompleteFile = (downloadDir as NSString).appendingPathComponent("12_abc_2_1of2.cdeevent")
        #expect(!FileManager.default.fileExists(atPath: incompleteFile))
    }

    @Test("Incomplete remote sets ignored when uploading")
    func incompleteRemoteSetsIgnoredWhenUploading() async throws {
        let storeId = setup.persistentStoreIdentifier
        let event = try setup.eventStore.insertEvent(
            uniqueIdentifier: "123",
            type: .save,
            timestamp: 0.0,
            globalCount: 12
        )
        try setup.eventStore.insertRevision(persistentStoreIdentifier: storeId, revisionNumber: 2, eventId: event.id, isEventRevision: true)

        try await cloudManager.createRemoteDirectoryStructure()

        // Pre-populate with an incomplete set from another device
        await cloudFS.createFile(atPath: "\(remoteEventsDir)/12_abc_2_1of2.cdeevent", data: Data([0x01]))

        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalNonBaselineEvents()

        // The local event should have been exported
        let expectedPath = "\(remoteEventsDir)/12_\(storeId)_2.cdeevent"
        let existence = try await cloudFS.fileExists(atPath: expectedPath)
        #expect(existence.exists)
    }

    // MARK: - Sorting

    @Test("Sort filenames by global count")
    func sortFilenamesByGlobalCount() {
        let files = ["10_store1_0", "9_store1_3", "8_aaa_8"]
        let sorted = cloudManager.sortFilenamesByGlobalCount(files)
        #expect(sorted[0] == "8_aaa_8")
        #expect(sorted[1] == "9_store1_3")
        #expect(sorted[2] == "10_store1_0")
    }
}
