import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// Whether to upload a baseline is decided by comparing it with a listing of the cloud.
// On CloudKit that listing is a local cache, and a cache can be wrong: a customer's
// named both parts of his baseline although the server held neither, so the device
// concluded there was nothing to publish, sent nothing, and reported success. Every
// follower then synced "successfully" against a cloud with no baseline in it.
//
// Skipping the publication of this device's own baseline is too consequential to rest
// on a listing alone. Before skipping, the files are confirmed with the server.
@Suite("BaselinePublicationConfirmation", .serialized)
struct BaselinePublicationConfirmationTests {

    let setup: TestEventStoreSetup
    let cloudFS: ExistenceSpyFileSystem
    let cloudManager: CloudManager

    init() throws {
        let s = try TestEventStoreSetup(loadTestModel: true)
        let fs = ExistenceSpyFileSystem()
        setup = s
        cloudFS = fs
        cloudManager = CloudManager(eventStore: s.eventStore, cloudFileSystem: fs, managedObjectModel: s.testModel!)
    }

    private var remoteBaselinesDir: String { "/\(setup.eventStore.ensembleIdentifier)/baselines" }

    /// Adds this device's own baseline and returns the name its cloud file takes.
    private func addOwnBaseline() throws -> String {
        let storeId = setup.persistentStoreIdentifier
        let baseline = try setup.addEvents(type: .baseline, storeId: storeId, globalCounts: [0], revisions: [0]).last!
        return "0_\(baseline.uniqueIdentifier)_\(storeId.prefix(8)).cdeevent"
    }

    private func realBaselineNames() async throws -> [String] {
        try await cloudFS.inner.contentsOfDirectory(atPath: remoteBaselinesDir).map(\.name).sorted()
    }

    @Test("A baseline the listing claims is uploaded, but the server does not hold, is published")
    func phantomListingDoesNotSuppressPublication() async throws {
        let name = try addOwnBaseline()
        try await cloudManager.createRemoteDirectoryStructure()
        cloudFS.phantomNamesByDirectory[remoteBaselinesDir] = [name]

        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalBaseline()

        #expect(try await realBaselineNames() == [name], "the baseline was not published: the listing was believed")
        #expect(cloudFS.confirmFileExistsPaths.contains("\(remoteBaselinesDir)/\(name)"), "the server was never asked")
    }

    @Test("A baseline that really is in the cloud is confirmed once, and not uploaded again")
    func realBaselineIsConfirmedOnceAndNotReuploaded() async throws {
        let name = try addOwnBaseline()
        try await cloudManager.createRemoteDirectoryStructure()
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalBaseline()
        try #require(try await realBaselineNames() == [name])

        cloudFS.confirmFileExistsPaths = []
        for _ in 0..<3 {
            try await cloudManager.snapshotRemoteFiles()
            try await cloudManager.exportNewLocalBaseline()
        }

        let confirmations = cloudFS.confirmFileExistsPaths.filter { $0.hasSuffix(name) }
        #expect(confirmations.count == 1, "expected one server confirmation per baseline file per launch, got \(confirmations.count)")
        #expect(try await realBaselineNames() == [name])
    }

    @Test("Another device's baseline is not confirmed: only this device's own publication is at stake")
    func otherDevicesBaselinesAreNotConfirmed() async throws {
        _ = try addOwnBaseline()
        try await cloudManager.createRemoteDirectoryStructure()
        let theirs = "0_11111111-2222-3333-4444-555555555555_BBBBBBBB.cdeevent"
        await cloudFS.inner.createFile(atPath: "\(remoteBaselinesDir)/\(theirs)", data: Data())

        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.exportNewLocalBaseline()

        #expect(!cloudFS.confirmFileExistsPaths.contains { $0.hasSuffix(theirs) })
    }
}
