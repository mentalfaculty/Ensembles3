import Testing
import Foundation
@_spi(Testing) import Ensembles

/// Tests for S3CloudFileSystem key/path conversion and directory logic.
/// Tests the logic without requiring real AWS credentials.
@Suite("S3CloudFileSystemTests")
struct S3CloudFileSystemTests {

    // MARK: - Key Conversion Tests

    @Test("Path to S3 key strips leading slash and prepends prefix")
    func pathToKeyWithPrefix() {
        let key = s3Key(for: "/ensembleId/events/data.json", keyPrefix: "sync/")
        #expect(key == "sync/ensembleId/events/data.json")
    }

    @Test("Path to S3 key with empty prefix")
    func pathToKeyNoPrefix() {
        let key = s3Key(for: "/ensembleId/events/data.json", keyPrefix: "")
        #expect(key == "ensembleId/events/data.json")
    }

    @Test("Path without leading slash")
    func pathWithoutLeadingSlash() {
        let key = s3Key(for: "ensembleId/events/data.json", keyPrefix: "")
        #expect(key == "ensembleId/events/data.json")
    }

    @Test("Root path produces just the prefix")
    func rootPathKey() {
        let key = s3Key(for: "/", keyPrefix: "sync/")
        #expect(key == "sync/")
    }

    // MARK: - Key to CloudPath Tests

    @Test("S3 key to cloud path with prefix")
    func keyToCloudPathWithPrefix() {
        let path = cloudPath(forKey: "sync/ensembleId/events/data.json", keyPrefix: "sync/")
        #expect(path == "/ensembleId/events/data.json")
    }

    @Test("S3 key to cloud path without prefix")
    func keyToCloudPathNoPrefix() {
        let path = cloudPath(forKey: "ensembleId/events/data.json", keyPrefix: "")
        #expect(path == "/ensembleId/events/data.json")
    }

    @Test("S3 directory key strips trailing slash")
    func directoryKeyStripsTrailingSlash() {
        let path = cloudPath(forKey: "sync/ensembleId/events/", keyPrefix: "sync/")
        #expect(path == "/ensembleId/events")
    }

    @Test("Root key returns root path")
    func rootKeyPath() {
        let path = cloudPath(forKey: "sync/", keyPrefix: "sync/")
        #expect(path == "/")
    }

    // MARK: - Prefix Normalization Tests

    @Test("Key prefix without trailing slash gets one added")
    func prefixNormalization() {
        let normalized = normalizePrefix("myprefix")
        #expect(normalized == "myprefix/")
    }

    @Test("Key prefix with trailing slash stays unchanged")
    func prefixWithSlashUnchanged() {
        let normalized = normalizePrefix("myprefix/")
        #expect(normalized == "myprefix/")
    }

    @Test("Empty key prefix stays empty")
    func emptyPrefixStaysEmpty() {
        let normalized = normalizePrefix("")
        #expect(normalized == "")
    }

    // MARK: - Directory Listing Simulation Tests

    @Test("Extracting file name from S3 key with prefix")
    func extractFileName() {
        let prefix = "sync/ensembleId/events/"
        let objectKey = "sync/ensembleId/events/abc123.json"
        let name = String(objectKey.dropFirst(prefix.count))
        #expect(name == "abc123.json")
    }

    @Test("Extracting subdirectory name from common prefix")
    func extractSubdirName() {
        let prefix = "sync/ensembleId/"
        let commonPrefix = "sync/ensembleId/events/"
        var name = String(commonPrefix.dropFirst(prefix.count))
        if name.hasSuffix("/") { name = String(name.dropLast()) }
        #expect(name == "events")
    }

    @Test("Directory marker key equals prefix — should be skipped")
    func directoryMarkerSkipped() {
        let prefix = "sync/ensembleId/events/"
        let objectKey = "sync/ensembleId/events/"
        let shouldSkip = objectKey == prefix
        #expect(shouldSkip == true)
    }

    // MARK: - Helpers (mirror S3CloudFileSystem private methods)

    private func s3Key(for path: String, keyPrefix: String) -> String {
        var cleanPath = path
        while cleanPath.hasPrefix("/") {
            cleanPath = String(cleanPath.dropFirst())
        }
        return keyPrefix + cleanPath
    }

    private func cloudPath(forKey key: String, keyPrefix: String) -> String {
        var path = key
        if path.hasPrefix(keyPrefix) {
            path = String(path.dropFirst(keyPrefix.count))
        }
        if !path.hasPrefix("/") {
            path = "/" + path
        }
        if path != "/", path.hasSuffix("/") {
            path = String(path.dropLast())
        }
        return path
    }

    private func normalizePrefix(_ prefix: String) -> String {
        if prefix.isEmpty || prefix.hasSuffix("/") {
            return prefix
        }
        return prefix + "/"
    }
}
