import Ensembles
import EnsemblesLocalFile

@MainActor
final class SyncController {
    static let baseDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SimpleSync", isDirectory: true)
    }()

    let container: CoreDataEnsembleContainer

    init(name: String) {
        let storeDir = Self.baseDir.appendingPathComponent(name, isDirectory: true)
        let cloudDir = Self.baseDir.appendingPathComponent("cloudfiles", isDirectory: true)
        try! FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        let storeURL = storeDir.appendingPathComponent("store.sqlite")

        let cloudFS = LocalCloudFileSystem(rootDirectory: cloudDir.path)
        self.container = CoreDataEnsembleContainer(
            name: "NumberStore",
            storeURL: storeURL,
            modelURL: Bundle.main.url(forResource: "Model", withExtension: "momd")!,
            cloudFileSystem: cloudFS,
            configuration: .init(localDataRootDirectoryURL: storeDir)
        )!

        container.globalIdentifiers = { objects in
            objects.map { ($0 as? NumberHolder)?.uniqueIdentifier }
        }

        // Create holder object if needed and save before attaching
        _ = NumberHolder.numberHolder(in: container.viewContext)
        try? container.viewContext.save()
    }
}
