import Foundation
@_spi(Testing) import Ensembles
import EnsemblesMemory

/// Delegates to `MemoryCloudFileSystem` while logging every call, and holding
/// `primeForActivity` open on request, so a test can keep a sync inside the file
/// system and prove what does, or does not, happen in the meantime.
final class GatedPrimingFileSystem: CloudFileSystem, CloudFileSystemSetup, CloudFileSystemBatchOperations, @unchecked Sendable {
    let inner = MemoryCloudFileSystem()

    private let lock = NSLock()
    private var callLog: [String] = []
    private var primingHeld = false

    var calls: [String] { lock.withLock { callLog } }
    var holdPriming: Bool {
        get { lock.withLock { primingHeld } }
        set { lock.withLock { primingHeld = newValue } }
    }

    private func enter(_ name: String) {
        lock.withLock { callLog.append(name) }
    }

    /// Waits until `primeForActivity` has been entered `count` times, or fails after 5 s.
    func waitForPriming(count: Int) async throws {
        let started = Date()
        while calls.filter({ $0 == "primeForActivity" }).count < count {
            guard Date().timeIntervalSince(started) < 5 else {
                throw NSError(domain: "GatedPrimingFileSystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "priming \(count) never reached; calls: \(calls)"])
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    // MARK: CloudFileSystem

    var isConnected: Bool { true }

    func connect() async throws {
        enter("connect")
        try await inner.connect()
    }

    func fetchUserIdentity() async throws -> sending (any NSObjectProtocol & NSCoding & NSCopying)? {
        enter("fetchUserIdentity")
        return try await inner.fetchUserIdentity()
    }

    func fileExists(atPath path: String) async throws -> FileExistence {
        enter("fileExists")
        return try await inner.fileExists(atPath: path)
    }

    func createDirectory(atPath path: String) async throws {
        enter("createDirectory")
        try await inner.createDirectory(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) async throws -> [any CloudItem] {
        enter("contentsOfDirectory")
        return try await inner.contentsOfDirectory(atPath: path)
    }

    func removeItem(atPath path: String) async throws {
        enter("removeItem")
        try await inner.removeItem(atPath: path)
    }

    func uploadLocalFile(atPath localPath: String, toPath remotePath: String) async throws {
        enter("uploadLocalFile")
        try await inner.uploadLocalFile(atPath: localPath, toPath: remotePath)
    }

    func downloadFile(atPath remotePath: String, toLocalFile localPath: String) async throws {
        enter("downloadFile")
        try await inner.downloadFile(atPath: remotePath, toLocalFile: localPath)
    }

    // MARK: CloudFileSystemSetup

    func performInitialPreparation() async throws {}

    /// Stays inside the file system while `holdPriming` is set, as a long CloudKit
    /// zone fetch does. The wait ignores task cancellation, as a CloudKit operation
    /// in flight does, so a test can dismantle the ensemble while the sync is still
    /// in here. Bounded so a regression fails rather than hangs.
    func primeForActivity() async throws {
        enter("primeForActivity")
        let deadline = Date().addingTimeInterval(10)
        while holdPriming, Date() < deadline {
            await Self.pause(milliseconds: 10)
        }
    }

    /// A sleep that task cancellation does not cut short.
    static func pause(milliseconds: Int) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
                continuation.resume()
            }
        }
    }

    func directoryExists(atPath path: String) async throws -> Bool {
        let existence = try await fileExists(atPath: path)
        return existence.exists && existence.isDirectory
    }

    func repairEnsembleDirectory(atPath path: String) async throws {}

    func setLocalStoreDirectory(_ path: String?, discardingExistingCache: Bool) {}

    // MARK: CloudFileSystemBatchOperations

    func uploadLocalFiles(atPaths localPaths: [String], toPaths remotePaths: [String]) async throws {
        enter("uploadLocalFiles")
        for (local, remote) in zip(localPaths, remotePaths) {
            try await inner.uploadLocalFile(atPath: local, toPath: remote)
        }
    }

    func downloadFiles(atPaths remotePaths: [String], toLocalFiles localPaths: [String]) async throws {
        enter("downloadFiles")
        for (remote, local) in zip(remotePaths, localPaths) {
            try await inner.downloadFile(atPath: remote, toLocalFile: local)
        }
    }

    func removeItems(atPaths paths: [String]) async throws {
        enter("removeItems")
        for path in paths {
            try await inner.removeItem(atPath: path)
        }
    }
}
