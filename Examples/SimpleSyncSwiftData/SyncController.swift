import Foundation
import SwiftData
import EnsemblesSwiftData
import EnsemblesLocalFile

@MainActor @Observable
final class SyncController {
    static let baseDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SimpleSyncSwiftData", isDirectory: true)
    }()

    let container: SwiftDataEnsembleContainer

    init(name: String) {
        let storeDir = Self.baseDir.appendingPathComponent(name, isDirectory: true)
        let cloudDir = Self.baseDir.appendingPathComponent("cloudfiles", isDirectory: true)
        try! FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("store.sqlite")

        let cloudFS = LocalCloudFileSystem(rootDirectory: cloudDir.path)
        self.container = SwiftDataEnsembleContainer(
            name: "NumberStore",
            storeURL: storeURL,
            modelTypes: [NumberItem.self],
            cloudFileSystem: cloudFS,
            configuration: .init(localDataRootDirectoryURL: storeDir)
        )!
    }
}
