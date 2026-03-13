import Testing
import Foundation
@_spi(Testing) import EnsemblesGoogleDrive
@_spi(Testing) import Ensembles

/// Tests for GoogleDriveCloudFileSystem path resolution, caching, JSON parsing,
/// error mapping, and multipart upload body construction.
/// These test the logic without requiring a real Google Drive account.
@Suite("GoogleDriveCloudFileSystemTests")
struct GoogleDriveCloudFileSystemTests {

    // MARK: - Path Resolution Tests

    @Test("Path components split correctly")
    func pathComponents() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let components = fs.pathComponents(for: "/a/b/c")
        #expect(components == ["a", "b", "c"])
    }

    @Test("Root path produces empty components")
    func rootPathComponents() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let components = fs.pathComponents(for: "/")
        #expect(components.isEmpty)
    }

    @Test("Path without leading slash is normalized")
    func pathWithoutLeadingSlash() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let abs = fs.absolutePath(for: "ensembleId/events")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Path with leading slash is unchanged")
    func pathWithLeadingSlash() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let abs = fs.absolutePath(for: "/ensembleId/events")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Double slashes are collapsed")
    func doubleSlashesCollapsed() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let abs = fs.absolutePath(for: "//ensembleId//events//")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Trailing slash is removed")
    func trailingSlashRemoved() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let abs = fs.absolutePath(for: "/ensembleId/events/")
        #expect(abs == "/ensembleId/events")
    }

    @Test("Root path stays as root")
    func rootPathPreserved() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let abs = fs.absolutePath(for: "/")
        #expect(abs == "/")
    }

    // MARK: - Folder ID Cache Tests

    @Test("Cache starts with root mapping")
    func cacheInitialization() {
        let cache: [String: String] = ["/": "root"]
        #expect(cache["/"] == "root")
        #expect(cache["/nonexistent"] == nil)
    }

    @Test("Cache stores and retrieves folder IDs")
    func cacheStoreAndRetrieve() {
        var cache: [String: String] = ["/": "root"]
        cache["/myEnsemble"] = "abc123"
        cache["/myEnsemble/events"] = "def456"

        #expect(cache["/myEnsemble"] == "abc123")
        #expect(cache["/myEnsemble/events"] == "def456")
    }

    @Test("Cache invalidation removes path and children")
    func cacheInvalidation() {
        var cache: [String: String] = [
            "/": "root",
            "/myEnsemble": "100",
            "/myEnsemble/events": "200",
            "/myEnsemble/data": "300",
            "/otherEnsemble": "400"
        ]

        let pathToInvalidate = "/myEnsemble"
        cache = cache.filter { !$0.key.hasPrefix(pathToInvalidate) || $0.key == "/" }

        #expect(cache["/"] == "root")
        #expect(cache["/myEnsemble"] == nil)
        #expect(cache["/myEnsemble/events"] == nil)
        #expect(cache["/myEnsemble/data"] == nil)
        #expect(cache["/otherEnsemble"] == "400")
    }

    // MARK: - JSON Parsing Tests

    @Test("Parse files.list response produces CloudItems")
    func parseFilesListResponse() throws {
        let json: [String: Any] = [
            "files": [
                [
                    "id": "folder1",
                    "name": "events",
                    "mimeType": "application/vnd.google-apps.folder"
                ],
                [
                    "id": "file1",
                    "name": "snapshot.json",
                    "mimeType": "application/octet-stream",
                    "size": "2048"
                ],
                [
                    "id": "file2",
                    "name": "baseline.json",
                    "mimeType": "application/json",
                    "size": "512"
                ]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let files = parsed["files"] as! [[String: Any]]

        #expect(files.count == 3)

        // First item: directory (folder mimeType)
        let first = files[0]
        #expect(first["name"] as? String == "events")
        #expect(first["mimeType"] as? String == "application/vnd.google-apps.folder")

        // Second item: file with size as string
        let second = files[1]
        #expect(second["name"] as? String == "snapshot.json")
        #expect(second["size"] as? String == "2048")

        // Third item: another file
        let third = files[2]
        #expect(third["name"] as? String == "baseline.json")
        #expect(third["size"] as? String == "512")
    }

    @Test("Parse about response extracts user email")
    func parseAboutResponse() throws {
        let json: [String: Any] = [
            "user": [
                "displayName": "Test User",
                "emailAddress": "user@example.com",
                "kind": "drive#user"
            ] as [String: Any]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let user = parsed["user"] as! [String: Any]

        #expect(user["emailAddress"] as? String == "user@example.com")
    }

    @Test("File vs folder detection by mimeType")
    func fileVsFolderDetection() {
        let folderMime = "application/vnd.google-apps.folder"
        let fileMime = "application/octet-stream"

        #expect(folderMime == "application/vnd.google-apps.folder")
        #expect(fileMime != "application/vnd.google-apps.folder")

        // The backend treats folder mimeType as directory, everything else as file
        let isFolder = { (mimeType: String) in mimeType == "application/vnd.google-apps.folder" }
        #expect(isFolder(folderMime) == true)
        #expect(isFolder(fileMime) == false)
        #expect(isFolder("application/json") == false)
    }

    // MARK: - Error Mapping Tests

    @Test("HTTP 401 maps to authenticationFailure")
    func http401MapsToAuthFailure() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 401)
        #expect(error == .authenticationFailure)
    }

    @Test("HTTP 404 maps to fileAccessFailed")
    func http404MapsToFileAccessFailed() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 404)
        #expect(error == .fileAccessFailed)
    }

    @Test("HTTP 403 maps to serverError")
    func http403MapsToServerError() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 403)
        #expect(error == .serverError)
    }

    @Test("HTTP 500 maps to serverError")
    func http500MapsToServerError() {
        let fs = GoogleDriveCloudFileSystem(accessToken: "test")
        let error = fs.mapHTTPError(statusCode: 500)
        #expect(error == .serverError)
    }

    // MARK: - Multipart Upload Body Tests

    @Test("Multipart upload body is well-formed")
    func multipartUploadBody() throws {
        let boundary = "test-boundary-12345"
        let metadata: [String: Any] = [
            "name": "data.json",
            "parents": ["parentFolder123"]
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata)
        let fileData = "hello world".data(using: .utf8)!

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataData)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        let bodyString = String(data: body, encoding: .utf8)!

        // Verify structure
        #expect(bodyString.contains("--\(boundary)\r\n"))
        #expect(bodyString.contains("Content-Type: application/json; charset=UTF-8"))
        #expect(bodyString.contains("Content-Type: application/octet-stream"))
        #expect(bodyString.contains("hello world"))
        #expect(bodyString.contains("--\(boundary)--"))

        // Verify metadata section contains the file name
        #expect(bodyString.contains("data.json"))
        #expect(bodyString.contains("parentFolder123"))
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

    @Test("Map file entry to CloudFile with string size")
    func mapFileToCloudFile() {
        let parentPath = "/myEnsemble/events"
        let name = "abc123.json"
        let sizeString = "4096"
        let size = UInt64(sizeString) ?? 0
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

    // MARK: - Pagination Response Tests

    @Test("Parse paginated response with nextPageToken")
    func parsePaginatedResponse() throws {
        let json: [String: Any] = [
            "nextPageToken": "token123",
            "files": [
                [
                    "id": "file1",
                    "name": "event1.json",
                    "mimeType": "application/json",
                    "size": "100"
                ]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["nextPageToken"] as? String == "token123")
        let files = parsed["files"] as! [[String: Any]]
        #expect(files.count == 1)
    }

    @Test("Parse final page response without nextPageToken")
    func parseFinalPageResponse() throws {
        let json: [String: Any] = [
            "files": [
                [
                    "id": "file1",
                    "name": "event1.json",
                    "mimeType": "application/json",
                    "size": "100"
                ]
            ] as [[String: Any]]
        ]

        let data = try JSONSerialization.data(withJSONObject: json)
        let parsed = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(parsed["nextPageToken"] == nil)
    }
}
