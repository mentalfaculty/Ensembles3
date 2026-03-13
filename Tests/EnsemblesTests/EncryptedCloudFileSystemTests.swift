import Testing
import Foundation
@_spi(Testing) import Ensembles
import EnsemblesMemory
import EnsemblesEncrypted

@Suite("EncryptedCloudFileSystem")
struct EncryptedCloudFileSystemTests {

    let tempDir: String

    init() throws {
        EnsemblesLicense.activate("eyJlbWFpbCI6InRlc3RAZW5zZW1ibGVzLmRldiIsImV4cGlyZXMiOiIyMDk5LTEyLTMxIiwiaXNzdWVkIjoiMjAyNi0wMy0wNCIsInR5cGUiOiJzdWJzY3JpcHRpb24ifQ==.oizBZYgXZsGwctLUj6eDTABM5v7ZUBh7zANPCha3fySB1RvmGpifd0CUhDP+wzh++FQcBuYFQXILcJ60hzDs8w==")
        tempDir = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("EncryptedCloudFileSystemTests/\(ProcessInfo.processInfo.globallyUniqueString)")
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

    // MARK: - FileEncryptor

    @Test("Modern encrypt/decrypt round-trip")
    func modernRoundTrip() throws {
        let plaintext = Data("Hello, modern encryption!".utf8)
        let encrypted = try FileEncryptor.encrypt(data: plaintext, password: "secret", format: .modern)

        // Version byte should be 4
        #expect(encrypted[0] == 4)

        let decrypted = try FileEncryptor.decrypt(data: encrypted, password: "secret")
        #expect(decrypted == plaintext)
    }

    @Test("Legacy encrypt/decrypt round-trip")
    func legacyRoundTrip() throws {
        let plaintext = Data("Hello, legacy encryption!".utf8)
        let encrypted = try FileEncryptor.encrypt(data: plaintext, password: "secret", format: .legacy)

        // Version byte should be 3
        #expect(encrypted[0] == 3)
        // Options byte should be 1 (uses password)
        #expect(encrypted[1] == 1)

        let decrypted = try FileEncryptor.decrypt(data: encrypted, password: "secret")
        #expect(decrypted == plaintext)
    }

    @Test("Legacy format has correct byte layout")
    func legacyByteLayout() throws {
        let plaintext = Data("test".utf8)
        let encrypted = try FileEncryptor.encrypt(data: plaintext, password: "pass", format: .legacy)

        // RNCryptor v3 layout: version(1) + options(1) + encSalt(8) + hmacSalt(8) + IV(16) + ciphertext + HMAC(32)
        // Minimum size: 34 (header) + 16 (one AES block with padding) + 32 (HMAC) = 82
        #expect(encrypted.count >= 66) // header(34) + HMAC(32)
        #expect(encrypted[0] == 3) // version
        #expect(encrypted[1] == 1) // options: uses password
    }

    @Test("Auto-detect format on decrypt")
    func autoDetectFormat() throws {
        let plaintext = Data("auto-detect test".utf8)

        let modernEncrypted = try FileEncryptor.encrypt(data: plaintext, password: "pw", format: .modern)
        let legacyEncrypted = try FileEncryptor.encrypt(data: plaintext, password: "pw", format: .legacy)

        // Both should auto-detect and decrypt correctly
        let modernDecrypted = try FileEncryptor.decrypt(data: modernEncrypted, password: "pw")
        let legacyDecrypted = try FileEncryptor.decrypt(data: legacyEncrypted, password: "pw")

        #expect(modernDecrypted == plaintext)
        #expect(legacyDecrypted == plaintext)
    }

    @Test("Wrong password fails with legacy format")
    func wrongPasswordLegacy() throws {
        let plaintext = Data("secret data".utf8)
        let encrypted = try FileEncryptor.encrypt(data: plaintext, password: "correct", format: .legacy)

        #expect(throws: EncryptionError.self) {
            try FileEncryptor.decrypt(data: encrypted, password: "wrong")
        }
    }

    @Test("Wrong password fails with modern format")
    func wrongPasswordModern() throws {
        let plaintext = Data("secret data".utf8)
        let encrypted = try FileEncryptor.encrypt(data: plaintext, password: "correct", format: .modern)

        #expect(throws: (any Error).self) {
            try FileEncryptor.decrypt(data: encrypted, password: "wrong")
        }
    }

    @Test("Empty password throws")
    func emptyPasswordThrows() {
        #expect(throws: EncryptionError.emptyPassword) {
            try FileEncryptor.encrypt(data: Data("x".utf8), password: "")
        }
    }

    @Test("Encrypt empty data")
    func encryptEmptyData() throws {
        let encrypted = try FileEncryptor.encrypt(data: Data(), password: "pw", format: .modern)
        let decrypted = try FileEncryptor.decrypt(data: encrypted, password: "pw")
        #expect(decrypted == Data())
    }

    // MARK: - VaultInfo

    @Test("VaultInfo path derivation is deterministic")
    func vaultPathDeterministic() {
        let info1 = VaultInfo(password: "mypassword")
        let info2 = VaultInfo(password: "mypassword")
        #expect(info1 != nil)
        #expect(info1!.passwordDependentPath == info2!.passwordDependentPath)
    }

    @Test("VaultInfo path has correct format")
    func vaultPathFormat() {
        let info = VaultInfo(password: "test")!
        #expect(info.passwordDependentPath.hasPrefix("/VAULT_"))
        // /VAULT_ (7 chars) + 10 hex chars = 17 total
        #expect(info.passwordDependentPath.count == 17)
        // Should be uppercase
        #expect(info.passwordDependentPath == info.passwordDependentPath.uppercased())
    }

    @Test("Different passwords produce different vault paths")
    func differentPasswords() {
        let info1 = VaultInfo(password: "password1")!
        let info2 = VaultInfo(password: "password2")!
        #expect(info1.passwordDependentPath != info2.passwordDependentPath)
    }

    @Test("Empty password returns nil")
    func emptyPasswordReturnsNil() {
        let info = VaultInfo(password: "")
        #expect(info == nil)
    }

    @Test("Custom salt produces different vault path")
    func customSalt() {
        let info1 = VaultInfo(password: "test")!
        let info2 = VaultInfo(password: "test", salt: "custom-salt")!
        #expect(info1.passwordDependentPath != info2.passwordDependentPath)
    }

    @Test("canReadFile returns true for matching vault path")
    func canReadFileMatching() {
        let info = VaultInfo(password: "test")!
        let filePath = info.passwordDependentPath + "/data/events/event1.json"
        #expect(info.canReadFile(atPath: filePath))
    }

    @Test("canReadFile returns false for different vault path")
    func canReadFileDifferent() {
        let info = VaultInfo(password: "test")!
        #expect(!info.canReadFile(atPath: "/VAULT_ZZZZZZZZZZ/data/file.json"))
    }

    // MARK: - EncryptedCloudFileSystem

    @Test("Upload and download round-trips with modern encryption")
    func cloudFSRoundTripModern() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let info = VaultInfo(password: "secret")!
        let encFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info)

        try await encFS.connect()

        let content = "Encrypted cloud data"
        let localPath = try writeLocalFile(content)
        try await encFS.uploadLocalFile(atPath: localPath, toPath: "events/event1.json")

        // Verify file is stored in vault with .cdecrypt extension
        let vaultPath = info.passwordDependentPath + "/events/event1.json.cdecrypt"
        let innerExistence = try await memoryFS.fileExists(atPath: vaultPath)
        #expect(innerExistence.exists)

        // Download and verify
        let downloadPath = tempFile("downloaded.json")
        try await encFS.downloadFile(atPath: "events/event1.json", toLocalFile: downloadPath)

        let downloaded = try String(contentsOfFile: downloadPath, encoding: .utf8)
        #expect(downloaded == content)
    }

    @Test("Upload and download round-trips with legacy encryption")
    func cloudFSRoundTripLegacy() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let info = VaultInfo(password: "secret")!
        let encFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info, encryptionFormat: .legacy)

        try await encFS.connect()

        let content = "Legacy encrypted data"
        let localPath = try writeLocalFile(content)
        try await encFS.uploadLocalFile(atPath: localPath, toPath: "file.dat")

        let downloadPath = tempFile("legacy.dat")
        try await encFS.downloadFile(atPath: "file.dat", toLocalFile: downloadPath)

        let downloaded = try String(contentsOfFile: downloadPath, encoding: .utf8)
        #expect(downloaded == content)
    }

    @Test("contentsOfDirectory strips vault prefix and .cdecrypt extension")
    func contentsStripping() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let info = VaultInfo(password: "test")!
        let encFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info)

        let vaultPrefix = info.passwordDependentPath
        await memoryFS.createFile(atPath: "\(vaultPrefix)/dir/a.json.cdecrypt", data: Data())
        await memoryFS.createFile(atPath: "\(vaultPrefix)/dir/b.txt.cdecrypt", data: Data())

        let contents = try await encFS.contentsOfDirectory(atPath: "dir")
        let names = contents.map(\.name).sorted()
        #expect(names == ["a.json", "b.txt"])

        // Paths should also be stripped
        let paths = contents.map(\.path).sorted()
        #expect(paths == ["dir/a.json", "dir/b.txt"])
    }

    @Test("connect creates vault directory")
    func connectCreatesVault() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let info = VaultInfo(password: "test")!
        let encFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info)

        try await encFS.connect()

        let existence = try await memoryFS.fileExists(atPath: info.passwordDependentPath)
        #expect(existence.exists)
    }

    @Test("Convenience init with password")
    func convenienceInit() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let encFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, password: "pass")
        #expect(encFS != nil)

        let nilFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, password: "")
        #expect(nilFS == nil)
    }

    @Test("Modern and legacy can cross-decrypt via cloud FS")
    func crossFormatDecrypt() async throws {
        let memoryFS = MemoryCloudFileSystem()
        let info = VaultInfo(password: "shared")!

        let modernFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info, encryptionFormat: .modern)
        let legacyFS = EncryptedCloudFileSystem(cloudFileSystem: memoryFS, vaultInfo: info, encryptionFormat: .legacy)

        try await modernFS.connect()

        let content = "cross-format test"

        // Upload with modern
        let modernSource = try writeLocalFile(content, name: "modern.dat")
        try await modernFS.uploadLocalFile(atPath: modernSource, toPath: "file.json")

        // Download with legacy FS (should auto-detect modern format)
        let legacyDest = tempFile("legacy-read.json")
        try await legacyFS.downloadFile(atPath: "file.json", toLocalFile: legacyDest)
        let result = try String(contentsOfFile: legacyDest, encoding: .utf8)
        #expect(result == content)
    }
}
