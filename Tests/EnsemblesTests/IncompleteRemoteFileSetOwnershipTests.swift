import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

// A sync removes remote file sets that are incomplete AND were produced by this
// device: a half-uploaded set is this device's own litter. Deciding whose they are
// is the whole safety of that step. Files belonging to another peer are that peer's
// only copy until it finishes uploading them, and deleting one destroys data.
//
// A baseline filename never carries a store identifier, only an 8-character store
// prefix, and a legacy two-component name carries neither. `hasPrefix("")` is true
// in Swift, so an absent prefix used to match every device. Ensembles 2 was not
// exposed to this: `-[NSString hasPrefix:nil]` is NO.
@Suite("IncompleteRemoteFileSetOwnership", .serialized)
struct IncompleteRemoteFileSetOwnershipTests {

    let setup: TestEventStoreSetup
    let cloudFS: MemoryCloudFileSystem
    let cloudManager: CloudManager

    init() throws {
        let s = try TestEventStoreSetup(loadTestModel: true)
        let fs = MemoryCloudFileSystem()
        setup = s
        cloudFS = fs
        cloudManager = CloudManager(eventStore: s.eventStore, cloudFileSystem: fs, managedObjectModel: s.testModel!)
    }

    private var remoteBaselinesDir: String { "/\(setup.eventStore.ensembleIdentifier)/baselines" }

    /// The 8-character prefix of this device's own store identifier, as it appears
    /// in the names of baselines this device uploads.
    private var localPrefix: String { String(setup.persistentStoreIdentifier.prefix(8)) }

    private func putBaselineFile(named name: String) async throws {
        try await cloudManager.createRemoteDirectoryStructure()
        let local = (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
        try Data("baseline part".utf8).write(to: URL(fileURLWithPath: local))
        defer { try? FileManager.default.removeItem(atPath: local) }
        try await cloudFS.uploadLocalFile(atPath: local, toPath: remoteBaselinesDir + "/\(name)")
    }

    private func baselineFilenames() async throws -> [String] {
        try await cloudFS.contentsOfDirectory(atPath: remoteBaselinesDir).map(\.name).sorted()
    }

    /// One sweep, taking the listing first, exactly as a sync does.
    private func sweep() async throws {
        try await cloudManager.snapshotRemoteFiles()
        try await cloudManager.removeLocallyProducedIncompleteRemoteFileSets()
    }

    /// A two-part baseline from another device, of which only one part is listed.
    /// Incomplete, but not ours: only that device can finish it.
    @Test("An incomplete baseline from another store is left alone")
    func incompleteBaselineOfAnotherStoreIsKept() async throws {
        let theirs = "0_11111111-2222-3333-4444-555555555555_BBBBBBBB_1of2.cdeevent"
        try await putBaselineFile(named: theirs)

        try await sweep()

        #expect(try await baselineFilenames() == [theirs], "another store's incomplete baseline was deleted")
    }

    /// A name with no store prefix at all. This is what `hasPrefix("")` waved through.
    @Test("An incomplete baseline with no store prefix is left alone")
    func incompleteBaselineWithoutPrefixIsKept() async throws {
        let noPrefix = "0_11111111-2222-3333-4444-555555555555_1of2.cdeevent"
        try await putBaselineFile(named: noPrefix)

        try await sweep()

        #expect(try await baselineFilenames() == [noPrefix], "a baseline with no store prefix was deleted")
    }

    /// A device with no store identifier of its own has produced nothing, so it owns
    /// nothing. A baseline filename never carries a store identifier either, so both
    /// sides read as "" and the equality test matched every baseline in the cloud.
    @Test("A device with no store identifier claims nothing")
    func deviceWithoutStoreIdentifierDeletesNothing() async throws {
        let theirs = "0_11111111-2222-3333-4444-555555555555_BBBBBBBB_1of2.cdeevent"
        try await putBaselineFile(named: theirs)

        // Simulate the detached state: the store identifier is gone, the directories remain.
        setup.eventStore.dismantle()

        try await sweep()

        #expect(try await baselineFilenames() == [theirs], "a device with no store identifier deleted another store's baseline")
    }

    /// The behaviour the sweep exists for. It must survive the fix.
    @Test("This device's own incomplete baseline is still removed")
    func ownIncompleteBaselineIsRemoved() async throws {
        let mine = "0_11111111-2222-3333-4444-555555555555_\(localPrefix)_1of2.cdeevent"
        try await putBaselineFile(named: mine)

        try await sweep()

        #expect(try await baselineFilenames().isEmpty, "this device's own incomplete baseline was not cleaned up")
    }

    /// A complete set is never litter, whoever made it.
    @Test("A complete baseline of this device is kept")
    func completeOwnBaselineIsKept() async throws {
        let part1 = "0_11111111-2222-3333-4444-555555555555_\(localPrefix)_1of2.cdeevent"
        let part2 = "0_11111111-2222-3333-4444-555555555555_\(localPrefix)_2of2.cdeevent"
        try await putBaselineFile(named: part1)
        try await putBaselineFile(named: part2)

        try await sweep()

        #expect(try await baselineFilenames() == [part1, part2], "a complete baseline was deleted")
    }
}
