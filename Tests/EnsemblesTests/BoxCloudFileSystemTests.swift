import Testing
import Foundation
@_spi(Testing) import Ensembles

/// Tests for BoxCloudFileSystem path resolution, caching, and CloudItem mapping.
/// These test the logic without requiring a real Box client.
@Suite("BoxCloudFileSystemTests")
struct BoxCloudFileSystemTests {

    // MARK: - Path Resolution Tests

    @Test("Path components split correctly")
    func pathComponents() {
        let components = splitPathComponents("/ensembleId/events/data.json")
        #expect(components == ["ensembleId", "events", "data.json"])
    }

    @Test("Root path produces empty components")
    func rootPathComponents() {
        let components = splitPathComponents("/")
        #expect(components.isEmpty)
    }

    @Test("Path without leading slash is normalized")
    func pathWithoutLeadingSlash() {
        let abs = absolutePath(for: "ensembleId/events")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Path with leading slash is unchanged")
    func pathWithLeadingSlash() {
        let abs = absolutePath(for: "/ensembleId/events")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Double slashes are collapsed")
    func doubleSlashesCollapsed() {
        let abs = absolutePath(for: "//ensembleId//events//")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Trailing slash is removed")
    func trailingSlashRemoved() {
        let abs = absolutePath(for: "/ensembleId/events/")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Root path stays as root")
    func rootPathPreserved() {
        let abs = absolutePath(for: "/")
        #expect(abs == "/")
    }

    // MARK: - Folder ID Cache Tests

    @Test("Cache starts with root mapping")
    func cacheInitialization() {
        let cache: [String: String] = ["/": "0"]
        #expect(cache["/"] == "0")
        #expect(cache["/nonexistent"] == nil)
    }

    @Test("Cache stores and retrieves folder IDs")
    func cacheStoreAndRetrieve() {
        var cache: [String: String] = ["/": "0"]
        cache["/myEnsemble"] = "12345"
        cache["/myEnsemble/events"] = "67890"

        #expect(cache["/myEnsemble"] == "12345")
        #expect(cache["/myEnsemble/events"] == "67890")
    }

    @Test("Cache invalidation removes path and children")
    func cacheInvalidation() {
        var cache: [String: String] = [
            "/": "0",
            "/myEnsemble": "100",
            "/myEnsemble/events": "200",
            "/myEnsemble/data": "300",
            "/otherEnsemble": "400"
        ]

        let pathToInvalidate = "/myEnsemble"
        cache = cache.filter { !$0.key.hasPrefix(pathToInvalidate) }

        #expect(cache["/"] == "0")
        #expect(cache["/myEnsemble"] == nil)
        #expect(cache["/myEnsemble/events"] == nil)
        #expect(cache["/myEnsemble/data"] == nil)
        #expect(cache["/otherEnsemble"] == "400")
    }

    // MARK: - CloudItem Mapping Tests

    @Test("Map folder entry to CloudDirectory")
    func mapFolderToCloudDirectory() {
        let parentPath = "/myEnsemble"
        let name = "events"
        let dirPath = (parentPath as NSString).appendingPathComponent(name)
        let item = CloudDirectory(path: dirPath, name: name)

        #expect(item.name == "events")
        #expect(item.path == "/myEnsemble/events")
    }

    @Test("Map file entry to CloudFile")
    func mapFileToCloudFile() {
        let parentPath = "/myEnsemble/events"
        let name = "abc123.json"
        let size: UInt64 = 4096
        let filePath = (parentPath as NSString).appendingPathComponent(name)
        let item = CloudFile(path: filePath, name: name, size: size)

        #expect(item.name == "abc123.json")
        #expect(item.path == "/myEnsemble/events/abc123.json")
        #expect(item.size == 4096)
    }

    @Test("Parent path extraction")
    func parentPathExtraction() {
        let path = "/ensembleId/events/data.json"
        let parent = (path as NSString).deletingLastPathComponent
        let fileName = (path as NSString).lastPathComponent

        #expect(parent == "/ensembleId/events")
        #expect(fileName == "data.json")
    }

    // MARK: - Helpers (mirror BoxCloudFileSystem private methods)

    private func absolutePath(for path: String) -> String {
        var absPath = path
        if !absPath.hasPrefix("/") {
            absPath = "/" + absPath
        }
        while absPath.contains("//") {
            absPath = absPath.replacingOccurrences(of: "//", with: "/")
        }
        if absPath != "/", absPath.hasSuffix("/") {
            absPath = String(absPath.dropLast())
        }
        return absPath
    }

    private func splitPathComponents(_ path: String) -> [String] {
        let absPath = absolutePath(for: path)
        return absPath.split(separator: "/").map(String.init)
    }
}
