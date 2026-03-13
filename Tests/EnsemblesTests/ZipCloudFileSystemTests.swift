#if Zip
import Testing
import Foundation
@_spi(Testing) import Ensembles
import EnsemblesMemory
import EnsemblesZip

@Suite("ZipCloudFileSystem")
struct ZipCloudFileSystemTests {

    let memoryFS = MemoryCloudFileSystem()
    let tempDir: String

    init() throws {
        tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("ZipCloudFileSystemTests/\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    }

    private func tempFile(_ name: String = "test.dat") -> String {
        (tempDir as NSString).appendingPathComponent(name)
    }

    private func writeLocalFile(_ content: String, name: String = "test.dat") throws -> String {
        let path = tempFile(name)
        try Data(content.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - Round-trip

    @Test("Upload and download round-trips file content")
    func roundTrip() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)
        let content = "Hello, Ensembles Zip!"
        let localPath = try writeLocalFile(content)

        try await zipFS.uploadLocalFile(atPath: localPath, toPath: "data/file.json")

        // The inner FS should have the file with .cdezip extension
        let innerExistence = try await memoryFS.fileExists(atPath: "data/file.json.cdezip")
        #expect(innerExistence.exists)

        // The plain path should not exist
        let plainExistence = try await memoryFS.fileExists(atPath: "data/file.json")
        #expect(!plainExistence.exists)

        // Download through the zip FS
        let downloadPath = tempFile("downloaded.json")
        try await zipFS.downloadFile(atPath: "data/file.json", toLocalFile: downloadPath)

        let downloaded = try String(contentsOfFile: downloadPath, encoding: .utf8)
        #expect(downloaded == content)
    }

    @Test("fileExists finds .cdezip files")
    func fileExistsFindsZipped() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)
        let localPath = try writeLocalFile("data")

        try await zipFS.uploadLocalFile(atPath: localPath, toPath: "file.bin")

        let existence = try await zipFS.fileExists(atPath: "file.bin")
        #expect(existence.exists)
    }

    @Test("contentsOfDirectory strips .cdezip extension")
    func contentsStripsExtension() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)

        await memoryFS.createFile(atPath: "dir/a.json.cdezip", data: Data("zip".utf8))
        await memoryFS.createFile(atPath: "dir/b.txt", data: Data("plain".utf8))

        let contents = try await zipFS.contentsOfDirectory(atPath: "dir")
        let names = contents.map(\.name).sorted()

        #expect(names == ["a.json", "b.txt"])
    }

    @Test("removeItem removes both .cdezip and plain paths")
    func removeItemBoth() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)

        await memoryFS.createFile(atPath: "file.dat.cdezip", data: Data())
        await memoryFS.createFile(atPath: "file.dat", data: Data())

        try await zipFS.removeItem(atPath: "file.dat")

        let zipped = try await memoryFS.fileExists(atPath: "file.dat.cdezip")
        let plain = try await memoryFS.fileExists(atPath: "file.dat")
        #expect(!zipped.exists)
        #expect(!plain.exists)
    }

    @Test("Download falls back to uncompressed file")
    func downloadFallbackToPlain() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)
        let content = "plain content"

        // Put a plain file in the inner FS (no .cdezip)
        let localPath = try writeLocalFile(content, name: "source.dat")
        try await memoryFS.uploadLocalFile(atPath: localPath, toPath: "plain/file.dat")

        let downloadPath = tempFile("fallback.dat")
        try await zipFS.downloadFile(atPath: "plain/file.dat", toLocalFile: downloadPath)

        let downloaded = try String(contentsOfFile: downloadPath, encoding: .utf8)
        #expect(downloaded == content)
    }

    @Test("Delegate can prevent compression")
    func delegatePreventsCompression() async throws {
        let zipFS = ZipCloudFileSystem(cloudFileSystem: memoryFS)
        let noCompressDelegate = NoCompressDelegate()
        zipFS.delegate = noCompressDelegate

        let localPath = try writeLocalFile("no compress")
        try await zipFS.uploadLocalFile(atPath: localPath, toPath: "file.dat")

        // Should be stored without .cdezip
        let plainExists = try await memoryFS.fileExists(atPath: "file.dat")
        let zippedExists = try await memoryFS.fileExists(atPath: "file.dat.cdezip")
        #expect(plainExists.exists)
        #expect(!zippedExists.exists)
    }
}

private final class NoCompressDelegate: ZipCloudFileSystemDelegate, @unchecked Sendable {
    func zipCloudFileSystem(_ fileSystem: ZipCloudFileSystem, shouldCompressFileAtPath path: String) -> Bool {
        false
    }
}
#endif
