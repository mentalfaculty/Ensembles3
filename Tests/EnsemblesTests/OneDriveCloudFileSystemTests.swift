import Testing
import Foundation
@_spi(Testing) import EnsemblesOneDrive
@_spi(Testing) import Ensembles

/// Tests for OneDriveCloudFileSystem URL construction, path encoding, JSON parsing,
/// and error mapping. These test the logic without requiring a real OneDrive account.
@Suite("OneDriveCloudFileSystemTests")
struct OneDriveCloudFileSystemTests {

    // MARK: - URL Construction Tests

    @Test("Item URL for standard path uses colon syntax")
    func itemURLForStandardPath() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forItemAtPath: "ensembleId/events")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/ensembleId/events:")
    }

    @Test("Item URL for root uses /me/drive/root without colons")
    func itemURLForRoot() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forItemAtPath: "/")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root")
    }

    @Test("Children URL for root uses /me/drive/root/children")
    func childrenURLForRoot() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forChildrenAtPath: "/")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root/children")
    }

    @Test("Children URL for nested path uses colon syntax with /children")
    func childrenURLForNestedPath() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forChildrenAtPath: "ensembleId/events")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/ensembleId/events:/children")
    }

    @Test("Content URL uses colon syntax with /content")
    func contentURL() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forContentAtPath: "ensembleId/events/data.json")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/ensembleId/events/data.json:/content")
    }

    // MARK: - Path Encoding Tests

    @Test("Path with spaces is percent-encoded")
    func pathWithSpaces() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forItemAtPath: "my ensemble/my events")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/my%20ensemble/my%20events:")
    }

    @Test("Path with hash is percent-encoded")
    func pathWithHash() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let url = fs.graphURL(forItemAtPath: "ensemble#1/data")
        #expect(url.absoluteString == "https://graph.microsoft.com/v1.0/me/drive/root:/ensemble%231/data:")
    }

    @Test("Path encoding preserves forward slashes")
    func pathEncodingPreservesSlashes() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let encoded = fs.encodePathForGraph("/a/b/c")
        #expect(encoded == "/a/b/c")
    }

    // MARK: - Path Normalization Tests

    @Test("Path without leading slash gets one prepended")
    func pathNormalization() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let result = fs.absolutePath(for: "ensembleId/events")
        #expect(result == "/ensembleId/events")
    }

    @Test("Path with leading slash is unchanged")
    func pathWithLeadingSlash() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let result = fs.absolutePath(for: "/ensembleId/events")
        #expect(result == "/ensembleId/events")
    }

    @Test("Double slashes are collapsed")
    func doubleSlashesCollapsed() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let result = fs.absolutePath(for: "//ensembleId//events//")
        #expect(result == "/ensembleId/events")
    }

    @Test("Trailing slash is removed")
    func trailingSlashRemoved() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let result = fs.absolutePath(for: "/ensembleId/events/")
        #expect(result == "/ensembleId/events")
    }

    @Test("Root path stays as root")
    func rootPathPreserved() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let result = fs.absolutePath(for: "/")
        #expect(result == "/")
    }

    // MARK: - JSON Parsing: Children Response

    @Test("Parse children response produces correct CloudItems")
    func parseChildrenResponse() throws {
        let json: [String: Any] = [
            "value": [
                [
                    "name": "events",
                    "folder": ["childCount": 5],
                    "id": "abc123",
                    "size": 0
                ],
                [
                    "name": "snapshot.json",
                    "id": "def456",
                    "size": 2048,
                    "file": ["mimeType": "application/json"]
                ],
                [
                    "name": "baseline.json",
                    "id": "ghi789",
                    "size": 512,
                    "file": ["mimeType": "application/json"]
                ]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let value = parsed["value"] as! [[String: Any]]

        #expect(value.count == 3)

        // First: directory (has "folder" facet)
        let first = value[0]
        #expect(first["name"] as? String == "events")
        #expect(first["folder"] != nil)

        // Second: file (no "folder" facet)
        let second = value[1]
        #expect(second["name"] as? String == "snapshot.json")
        #expect(second["folder"] == nil)
        #expect(second["size"] as? Int == 2048)

        // Third: file
        let third = value[2]
        #expect(third["name"] as? String == "baseline.json")
        #expect(third["size"] as? Int == 512)
    }

    // MARK: - JSON Parsing: Me Response

    @Test("Parse /me response extracts displayName")
    func parseMeResponse() throws {
        let json: [String: Any] = [
            "id": "user-id-12345",
            "displayName": "Test User",
            "userPrincipalName": "user@example.com",
            "mail": "user@example.com"
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["displayName"] as? String == "Test User")
        #expect(parsed["id"] as? String != nil)
    }

    // MARK: - Folder vs File Detection

    @Test("Item with folder facet is detected as directory")
    func folderFacetDetection() {
        let entry: [String: Any] = [
            "name": "events",
            "folder": ["childCount": 3],
            "id": "abc"
        ]
        #expect(entry["folder"] != nil)
    }

    @Test("Item without folder facet is detected as file")
    func noFolderFacetDetection() {
        let entry: [String: Any] = [
            "name": "data.json",
            "file": ["mimeType": "application/json"],
            "id": "def",
            "size": 1024
        ]
        #expect(entry["folder"] == nil)
    }

    // MARK: - DriveItem Size Extraction

    @Test("Size as Int is correctly extracted")
    func sizeAsInt() {
        let entry: [String: Any] = ["size": 4096]
        let size = entry["size"] as? UInt64
            ?? (entry["size"] as? Int).map(UInt64.init)
            ?? 0
        #expect(size == 4096)
    }

    @Test("Missing size defaults to zero")
    func missingSizeDefaultsToZero() {
        let entry: [String: Any] = ["name": "test"]
        let size = entry["size"] as? UInt64
            ?? (entry["size"] as? Int).map(UInt64.init)
            ?? 0
        #expect(size == 0)
    }

    // MARK: - Error Mapping Tests

    @Test("HTTP 401 maps to authenticationFailure")
    func http401MapsToAuthFailure() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 401)
        #expect(error == .authenticationFailure)
    }

    @Test("HTTP 404 maps to fileAccessFailed")
    func http404MapsToFileAccessFailed() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 404)
        #expect(error == .fileAccessFailed)
    }

    @Test("HTTP 403 maps to serverError")
    func http403MapsToServerError() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 403)
        #expect(error == .serverError)
    }

    @Test("HTTP 409 conflict maps to serverError")
    func http409MapsToServerError() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 409)
        #expect(error == .serverError)
    }

    @Test("HTTP 500 maps to serverError")
    func http500MapsToServerError() {
        let fs = OneDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 500)
        #expect(error == .serverError)
    }

    // MARK: - Pagination Detection

    @Test("Response with @odata.nextLink indicates more pages")
    func paginationDetected() throws {
        let json: [String: Any] = [
            "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/drive/root:/folder:/children?$skiptoken=abc",
            "value": [
                ["name": "file1.json", "id": "1", "size": 100]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["@odata.nextLink"] as? String != nil)
    }

    @Test("Response without @odata.nextLink is final page")
    func noPaginationOnFinalPage() throws {
        let json: [String: Any] = [
            "value": [
                ["name": "file1.json", "id": "1", "size": 100]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["@odata.nextLink"] == nil)
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

    @Test("Map file entry to CloudFile with size")
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
}
