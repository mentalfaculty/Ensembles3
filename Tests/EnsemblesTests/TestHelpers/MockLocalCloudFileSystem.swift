import Foundation
import Ensembles
import EnsemblesLocalFile

/// A mock cloud file system that wraps `LocalCloudFileSystem` but allows
/// overriding the identity token. Since `LocalCloudFileSystem` is `final`
/// and cannot be subclassed, this wrapper delegates all `CloudFileSystem`
/// methods to the underlying local FS while providing a settable identity.
final class MockLocalCloudFileSystem: CloudFileSystem, @unchecked Sendable {
    let localFS: LocalCloudFileSystem
    var identityToken: (any NSObjectProtocol & NSCoding & NSCopying)?

    init(rootDirectory: String, identityToken: (any NSObjectProtocol & NSCoding & NSCopying)? = "default" as NSString) {
        self.localFS = LocalCloudFileSystem(rootDirectory: rootDirectory)
        self.identityToken = identityToken
    }

    var isConnected: Bool { localFS.isConnected }

    func connect() async throws {
        try await localFS.connect()
    }

    func fetchUserIdentity() async throws -> sending (any NSObjectProtocol & NSCoding & NSCopying)? {
        nonisolated(unsafe) let token = identityToken
        return token
    }

    func fileExists(atPath path: String) async throws -> FileExistence {
        try await localFS.fileExists(atPath: path)
    }

    func createDirectory(atPath path: String) async throws {
        try await localFS.createDirectory(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) async throws -> [any CloudItem] {
        try await localFS.contentsOfDirectory(atPath: path)
    }

    func removeItem(atPath path: String) async throws {
        try await localFS.removeItem(atPath: path)
    }

    func uploadLocalFile(atPath localPath: String, toPath remotePath: String) async throws {
        try await localFS.uploadLocalFile(atPath: localPath, toPath: remotePath)
    }

    func downloadFile(atPath remotePath: String, toLocalFile localPath: String) async throws {
        try await localFS.downloadFile(atPath: remotePath, toLocalFile: localPath)
    }
}
