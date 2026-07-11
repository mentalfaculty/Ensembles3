import Testing
import Foundation
@_spi(Testing) import EnsemblesCloudKit

@Suite("CloudKitListingCache")
struct CloudKitListingCacheTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".cdecloudkitcache.v3")
    }

    private var sampleFiles: [String: CloudKitListingCache.Entry] {
        [
            "/store/data": .init(isDirectory: true, fileSize: 0),
            "/store/data/file1.cdeevent": .init(isDirectory: false, fileSize: 1234),
            "/store/empty": .init(isDirectory: true, fileSize: 0),
        ]
    }

    @Test("Round-trip preserves snapshot")
    func roundTrip() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = CloudKitListingCache.Snapshot(tokenData: Data([1, 2, 3]), files: sampleFiles)
        CloudKitListingCache.save(snapshot, to: url)
        let loaded = CloudKitListingCache.load(from: url)
        #expect(loaded == snapshot)
    }

    @Test("Wrong version fails load and removes the file")
    func wrongVersion() throws {
        let url = tempURL()
        var snapshot = CloudKitListingCache.Snapshot(tokenData: Data([1]), files: sampleFiles)
        snapshot.version = 2
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)
        #expect(CloudKitListingCache.load(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Corrupt data fails load and removes the file")
    func corruptData() throws {
        let url = tempURL()
        try Data("not json at all".utf8).write(to: url)
        #expect(CloudKitListingCache.load(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Empty token data fails load")
    func emptyToken() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = CloudKitListingCache.Snapshot(tokenData: Data(), files: sampleFiles)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url)
        #expect(CloudKitListingCache.load(from: url) == nil)
    }

    @Test("Missing file loads as nil without creating anything")
    func missingFile() {
        let url = tempURL()
        #expect(CloudKitListingCache.load(from: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Save overwrites an existing snapshot completely")
    func overwrite() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        CloudKitListingCache.save(.init(tokenData: Data([1]), files: sampleFiles), to: url)
        let second = CloudKitListingCache.Snapshot(tokenData: Data([9, 9]), files: ["/x": .init(isDirectory: false, fileSize: 7)])
        CloudKitListingCache.save(second, to: url)
        #expect(CloudKitListingCache.load(from: url) == second)
    }

    @Test("Rebuild wires children into their parent directories")
    func rebuildWiring() throws {
        let contents = CloudKitListingCache.rebuildContents(from: sampleFiles, rootDirectory: "/")
        let dataChildren = try #require(contents["/store/data"])
        #expect(dataChildren.count == 1)
        let file = try #require(dataChildren["/store/data/file1.cdeevent"] as? CloudFile)
        #expect(file.name == "file1.cdeevent")
        #expect(file.size == 1234)
        #expect(file.path == "store/data/file1.cdeevent")
        let storeChildren = try #require(contents["/store"])
        #expect(storeChildren.count == 2)
        #expect(storeChildren["/store/data"] is CloudDirectory)
        #expect(storeChildren["/store/empty"] is CloudDirectory)
    }

    @Test("Rebuild creates an empty slot for a childless directory")
    func rebuildEmptyDirectory() throws {
        let contents = CloudKitListingCache.rebuildContents(from: sampleFiles, rootDirectory: "/")
        let emptyChildren = try #require(contents["/store/empty"])
        #expect(emptyChildren.isEmpty)
    }

    @Test("Rebuild wires top-level entries into the root slot")
    func rebuildRootWiring() {
        let files: [String: CloudKitListingCache.Entry] = ["/top": .init(isDirectory: true, fileSize: 0)]
        let contents = CloudKitListingCache.rebuildContents(from: files, rootDirectory: "/")
        #expect(contents["/"]?["/top"] is CloudDirectory)
    }
}
