import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

#if canImport(SwiftData)
import SwiftData
import EnsemblesSwiftData

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Model
final class Item {
    var title: String
    var timestamp: Date

    init(title: String, timestamp: Date = .now) {
        self.title = title
        self.timestamp = timestamp
    }
}
#endif

// MARK: - Tests

@Suite("SwiftData Integration")
struct SwiftDataTests {

    @Test("makeManagedObjectModel produces a valid Core Data model")
    func modelCreation() throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let model = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: [Item.self])
        )
        let entityNames = model.entities.map(\.name)
        #expect(entityNames.contains("Item"))
        #endif
    }

    @Test("makeManagedObjectModel produces consistent entity hashes")
    func consistentHashes() throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let model1 = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: [Item.self])
        )
        let model2 = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: [Item.self])
        )
        #expect(model1.entityVersionHashesByName == model2.entityVersionHashesByName)
        #endif
    }

    @Test("Single-version ensemble creation")
    func singleVersionCreation() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SwiftDataTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appending(path: "test.sqlite")
        let cloud = MemoryCloudFileSystem()

        let swiftDataEnsemble = try #require(
            SwiftDataEnsemble(
                ensembleIdentifier: "com.test.swiftdata",
                persistentStoreURL: storeURL,
                modelTypes: [Item.self],
                cloudFileSystem: cloud
            )
        )
        let ensemble = swiftDataEnsemble.coreDataEnsemble
        defer { ensemble.dismantle() }

        #expect(ensemble.managedObjectModels?.count == 1)
        #expect(ensemble.managedObjectModel.entities.map(\.name).contains("Item"))
        #endif
    }

    @Test("managedObjectModels is nil when not provided")
    func nilManagedObjectModels() async throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SwiftDataURLTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appending(path: "test.sqlite")
        let model = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: [Item.self])
        )

        let cloud = MemoryCloudFileSystem()
        let ensemble = try #require(
            CoreDataEnsemble(
                ensembleIdentifier: "com.test.urlbased",
                persistentStoreURL: storeURL,
                managedObjectModel: model,
                managedObjectModels: nil,
                cloudFileSystem: cloud
            )
        )
        defer { ensemble.dismantle() }

        #expect(ensemble.managedObjectModels == nil)
        #endif
    }

    @Test("RevisionManager.checkModelVersions works with in-memory models")
    func revisionManagerWithInMemoryModels() throws {
        #if canImport(SwiftData)
        guard #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) else { return }
        let model = try #require(
            NSManagedObjectModel.makeManagedObjectModel(for: [Item.self])
        )

        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SwiftDataRevTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let eventStore = try #require(
            EventStore(
                ensembleIdentifier: "com.test.revisionmanager",
                pathToEventDataRootDirectory: tempDir.path
            )
        )
        try eventStore.prepareNewEventStore()
        defer { eventStore.dismantle() }

        let revisionManager = RevisionManager(eventStore: eventStore)
        revisionManager.managedObjectModels = [model]
        revisionManager.allowModelToBeNil = false

        let result = revisionManager.checkModelVersions(of: [])
        #expect(result == true)
        #endif
    }

    @Test("RevisionManager returns true when both URL and models are nil")
    func revisionManagerNilGuard() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "SwiftDataNilTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let eventStore = try #require(
            EventStore(
                ensembleIdentifier: "com.test.nilguard",
                pathToEventDataRootDirectory: tempDir.path
            )
        )
        try eventStore.prepareNewEventStore()
        defer { eventStore.dismantle() }

        let revisionManager = RevisionManager(eventStore: eventStore)
        revisionManager.managedObjectModels = nil
        revisionManager.allowModelToBeNil = true

        let result = revisionManager.checkModelVersions(of: [])
        #expect(result == true)
    }
}
