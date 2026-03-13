#if Multipeer
import Testing
import Foundation
import ZIPFoundation
@_spi(Testing) import Ensembles
import EnsemblesMultipeer

// MARK: - Mock MultipeerConnection

fileprivate final class MockMultipeerConnection: MultipeerConnection, @unchecked Sendable {
    var sentData: [(data: Data, peerID: AnyObject)] = []
    var sentFiles: [(url: URL, peerID: AnyObject)] = []
    var newDataPeerIDs: [AnyObject] = []
    var noFilesPeerIDs: [AnyObject] = []

    func sendData(_ data: Data, toPeerWithID peerID: AnyObject) -> Bool {
        sentData.append((data, peerID))
        return true
    }

    func sendAndDiscardFile(at url: URL, toPeerWithID peerID: AnyObject) -> Bool {
        sentFiles.append((url, peerID))
        return true
    }

    func newDataWasAdded(onPeerWithID peerID: AnyObject) {
        newDataPeerIDs.append(peerID)
    }

    func fileRetrievalRequestCompletedWithNoFiles(fromPeerWithID peerID: AnyObject) {
        noFilesPeerIDs.append(peerID)
    }
}

// MARK: - Tests

@Suite("MultipeerCloudFileSystem")
struct MultipeerCloudFileSystemTests {

    let rootDir: String
    let tempDir: String
    fileprivate let connection: MockMultipeerConnection
    let fs: MultipeerCloudFileSystem

    init() throws {
        let base = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("MultipeerCloudFileSystemTests/\(ProcessInfo.processInfo.globallyUniqueString)")
        rootDir = (base as NSString).appendingPathComponent("cloud")
        tempDir = (base as NSString).appendingPathComponent("temp")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)

        connection = MockMultipeerConnection()
        fs = MultipeerCloudFileSystem(rootDirectory: rootDir, multipeerConnection: connection)
    }

    private func writeLocalFile(_ content: String, name: String = "test.dat") throws -> String {
        let path = (tempDir as NSString).appendingPathComponent(name)
        let parentDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - Connection

    @Test("isConnected always returns true")
    func alwaysConnected() {
        #expect(fs.isConnected)
    }

    @Test("connect succeeds")
    func connectSucceeds() async throws {
        try await fs.connect()
    }

    @Test("fetchUserIdentity returns User")
    func fetchUserIdentity() async throws {
        let identity = try await fs.fetchUserIdentity()
        #expect((identity as? NSString) == "User")
    }

    // MARK: - Local File Operations

    @Test("Upload and download file")
    func uploadDownload() async throws {
        try await fs.createDirectory(atPath: "data")
        let localPath = try writeLocalFile("hello", name: "upload.dat")
        try await fs.uploadLocalFile(atPath: localPath, toPath: "data/file.dat")

        let existence = try await fs.fileExists(atPath: "data/file.dat")
        #expect(existence.exists)
        #expect(!existence.isDirectory)

        let downloadPath = (tempDir as NSString).appendingPathComponent("download.dat")
        try await fs.downloadFile(atPath: "data/file.dat", toLocalFile: downloadPath)

        let content = try String(contentsOfFile: downloadPath, encoding: .utf8)
        #expect(content == "hello")
    }

    @Test("fileExists returns false for missing file")
    func fileNotExists() async throws {
        let existence = try await fs.fileExists(atPath: "nonexistent.dat")
        #expect(!existence.exists)
    }

    @Test("fileExists returns isDirectory for directory")
    func fileExistsDirectory() async throws {
        try await fs.createDirectory(atPath: "subdir")
        let existence = try await fs.fileExists(atPath: "subdir")
        #expect(existence.exists)
        #expect(existence.isDirectory)
    }

    @Test("contentsOfDirectory lists files and directories")
    func contentsOfDirectory() async throws {
        try await fs.createDirectory(atPath: "parent")
        try await fs.createDirectory(atPath: "parent/child")
        let localPath = try writeLocalFile("data", name: "f.dat")
        try await fs.uploadLocalFile(atPath: localPath, toPath: "parent/file.dat")

        let contents = try await fs.contentsOfDirectory(atPath: "parent")
        let names = contents.map(\.name).sorted()
        #expect(names == ["child", "file.dat"])

        let dirs = contents.compactMap { $0 as? CloudDirectory }
        #expect(dirs.count == 1)

        let files = contents.compactMap { $0 as? CloudFile }
        #expect(files.count == 1)
    }

    @Test("createDirectory and removeItem")
    func createAndRemoveDirectory() async throws {
        try await fs.createDirectory(atPath: "toremove")
        var existence = try await fs.fileExists(atPath: "toremove")
        #expect(existence.exists)

        try await fs.removeItem(atPath: "toremove")
        existence = try await fs.fileExists(atPath: "toremove")
        #expect(!existence.exists)
    }

    @Test("removeAllFiles removes root directory")
    func removeAllFiles() async throws {
        try await fs.createDirectory(atPath: "dir1")
        let localPath = try writeLocalFile("x", name: "x.dat")
        try await fs.uploadLocalFile(atPath: localPath, toPath: "dir1/x.dat")

        fs.removeAllFiles()
        #expect(!FileManager.default.fileExists(atPath: rootDir))
    }

    // MARK: - Peer Retrieval Request

    @Test("retrieveFiles sends file retrieval request with local paths")
    func retrieveFilesSendsRequest() async throws {
        // Put a file in the local cache
        try await fs.createDirectory(atPath: "events")
        let localPath = try writeLocalFile("event data", name: "ev.dat")
        try await fs.uploadLocalFile(atPath: localPath, toPath: "events/ev.dat")

        let peerID = "peer1" as NSString
        fs.retrieveFiles(fromPeersWithIDs: [peerID])

        #expect(connection.sentData.count == 1)

        let data = connection.sentData[0].data
        let decoded = try JSONDecoder().decode(TestPeerMessage.self, from: data)
        #expect(decoded.messageType == 1) // fileRetrievalRequest
        #expect(decoded.filePaths != nil)
        #expect(decoded.filePaths!.contains("events/ev.dat"))
    }

    // MARK: - File Retrieval Response

    @Test("Receiving a retrieval request sends missing files as zip")
    func receivingRetrievalRequestSendsZip() async throws {
        // Put files in local cache
        try await fs.createDirectory(atPath: "data")
        let localPath1 = try writeLocalFile("file1", name: "f1.dat")
        try await fs.uploadLocalFile(atPath: localPath1, toPath: "data/f1.dat")
        let localPath2 = try writeLocalFile("file2", name: "f2.dat")
        try await fs.uploadLocalFile(atPath: localPath2, toPath: "data/f2.dat")

        // Simulate peer that already has f1.dat but not f2.dat
        let requestMessage = TestPeerMessage(messageType: 1, filePaths: Set(["data/f1.dat"]))
        let requestData = try JSONEncoder().encode(requestMessage)

        let peerID = "peer2" as NSString
        fs.receiveData(requestData, fromPeerWithID: peerID)

        // Should have sent a file (zip archive)
        #expect(connection.sentFiles.count == 1)
    }

    @Test("Receiving a retrieval request with all files sends no-files response")
    func retrievalRequestAllFilesPresent() async throws {
        // Put a file in local cache
        try await fs.createDirectory(atPath: "data")
        let localPath = try writeLocalFile("content", name: "c.dat")
        try await fs.uploadLocalFile(atPath: localPath, toPath: "data/c.dat")

        // Peer already has the same file
        let requestMessage = TestPeerMessage(messageType: 1, filePaths: Set(["data/c.dat"]))
        let requestData = try JSONEncoder().encode(requestMessage)

        let peerID = "peer3" as NSString
        fs.receiveData(requestData, fromPeerWithID: peerID)

        // Should have sent a no-files data message, not a file
        #expect(connection.sentFiles.count == 0)
        #expect(connection.sentData.count == 1)

        let responseData = connection.sentData[0].data
        let decoded = try JSONDecoder().decode(TestPeerMessage.self, from: responseData)
        #expect(decoded.messageType == 2) // fileRetrievalResponseNoFiles
    }

    // MARK: - New Data Notification

    @Test("sendNotificationOfNewlyAvailableData sends correct message")
    func sendNewDataNotification() throws {
        let peerID = "peer4" as NSString
        fs.sendNotificationOfNewlyAvailableData(toPeersWithIDs: [peerID])

        #expect(connection.sentData.count == 1)
        let data = connection.sentData[0].data
        let decoded = try JSONDecoder().decode(TestPeerMessage.self, from: data)
        #expect(decoded.messageType == 3) // newDataAvailable
    }

    @Test("Receiving new data available message calls callback")
    func receiveNewDataAvailable() throws {
        let message = TestPeerMessage(messageType: 3)
        let data = try JSONEncoder().encode(message)

        let peerID = "peer5" as NSString
        fs.receiveData(data, fromPeerWithID: peerID)

        #expect(connection.newDataPeerIDs.count == 1)
    }

    @Test("Receiving no-files response calls callback")
    func receiveNoFilesResponse() throws {
        let message = TestPeerMessage(messageType: 2)
        let data = try JSONEncoder().encode(message)

        let peerID = "peer6" as NSString
        fs.receiveData(data, fromPeerWithID: peerID)

        #expect(connection.noFilesPeerIDs.count == 1)
    }

    // MARK: - Resource Import

    @Test("receiveResource extracts zip and imports files")
    func receiveResourceImportsFiles() async throws {
        // Create a zip archive with a file that should be imported
        let archiveContentDir = (tempDir as NSString).appendingPathComponent("archiveContent")
        try FileManager.default.createDirectory(atPath: archiveContentDir, withIntermediateDirectories: true)

        let eventDir = (archiveContentDir as NSString).appendingPathComponent("events")
        try FileManager.default.createDirectory(atPath: eventDir, withIntermediateDirectories: true)

        let eventFile = (eventDir as NSString).appendingPathComponent("event1.dat")
        try Data("imported event".utf8).write(to: URL(fileURLWithPath: eventFile))

        // Create the zip without the parent directory (matches makeArchive behavior)
        let zipPath = (tempDir as NSString).appendingPathComponent("transfer.zip")
        let zipURL = URL(fileURLWithPath: zipPath)
        try FileManager.default.zipItem(at: URL(fileURLWithPath: archiveContentDir), to: zipURL, shouldKeepParent: false)

        // Ensure root directory's events subdirectory exists
        try await fs.createDirectory(atPath: "events")

        let peerID = "peer7" as NSString
        fs.receiveResource(at: zipURL, fromPeerWithID: peerID)

        // Verify the file was imported into rootDirectory
        let importedPath = (rootDir as NSString).appendingPathComponent("events/event1.dat")
        #expect(FileManager.default.fileExists(atPath: importedPath))

        let content = try String(contentsOfFile: importedPath, encoding: .utf8)
        #expect(content == "imported event")
    }

    @Test("receiveResource posts notification on success")
    func receiveResourcePostsNotification() async throws {
        // Create a simple zip with one file
        let archiveContentDir = (tempDir as NSString).appendingPathComponent("notifyContent")
        try FileManager.default.createDirectory(atPath: archiveContentDir, withIntermediateDirectories: true)

        let filePath = (archiveContentDir as NSString).appendingPathComponent("file.dat")
        try Data("notify".utf8).write(to: URL(fileURLWithPath: filePath))

        let zipPath = (tempDir as NSString).appendingPathComponent("notify.zip")
        try FileManager.default.zipItem(at: URL(fileURLWithPath: archiveContentDir), to: URL(fileURLWithPath: zipPath), shouldKeepParent: false)

        nonisolated(unsafe) var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .multipeerCloudFileSystemDidImportFiles,
            object: fs,
            queue: nil
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        fs.receiveResource(at: URL(fileURLWithPath: zipPath), fromPeerWithID: "peer8" as NSString)

        #expect(notificationReceived)
    }

    @Test("receiveResource cleans up archive and temp directory")
    func receiveResourceCleansUp() async throws {
        let archiveContentDir = (tempDir as NSString).appendingPathComponent("cleanupContent")
        try FileManager.default.createDirectory(atPath: archiveContentDir, withIntermediateDirectories: true)

        let filePath = (archiveContentDir as NSString).appendingPathComponent("cleanup.dat")
        try Data("cleanup".utf8).write(to: URL(fileURLWithPath: filePath))

        let zipPath = (tempDir as NSString).appendingPathComponent("cleanup.zip")
        let zipURL = URL(fileURLWithPath: zipPath)
        try FileManager.default.zipItem(at: URL(fileURLWithPath: archiveContentDir), to: zipURL, shouldKeepParent: false)

        fs.receiveResource(at: zipURL, fromPeerWithID: "peer9" as NSString)

        // Archive should be removed
        #expect(!FileManager.default.fileExists(atPath: zipPath))
    }
}

// MARK: - Test Helper

/// Mirrors the internal PeerMessage struct for test decoding.
private struct TestPeerMessage: Codable {
    let messageType: Int
    var filePaths: Set<String>?
}
#endif
