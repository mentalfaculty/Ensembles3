import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesLocalFile

@Suite("ActivityNotificationTests", .serialized)
@MainActor
struct ActivityNotificationTests {

    let rootDir: String
    let cloudDir: String
    let ensemble: CoreDataEnsemble
    let managedObjectContext: NSManagedObjectContext

    init() throws {
        let root = (NSTemporaryDirectory() as NSString).appendingPathComponent("ActivityNotificationTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        self.rootDir = root

        let cloud = (root as NSString).appendingPathComponent("cloud")
        try FileManager.default.createDirectory(atPath: cloud, withIntermediateDirectories: true)
        self.cloudDir = cloud

        let modelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        let model = TestModelCache.model(for: modelURL)!

        let storePath = (root as NSString).appendingPathComponent("db.sqlite")
        let storeURL = URL(fileURLWithPath: storePath)

        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let moc = NSManagedObjectContext(.mainQueue)
        moc.persistentStoreCoordinator = psc
        self.managedObjectContext = moc

        let cloudFS = LocalCloudFileSystem(rootDirectory: cloud)
        let eventDataRoot = (root as NSString).appendingPathComponent("eventStore")
        let ens = CoreDataEnsemble(
            ensembleIdentifier: "testensemble",
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: modelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS,
            localDataRootDirectoryURL: URL(fileURLWithPath: eventDataRoot)
        )!
        self.ensemble = ens
    }

    // MARK: - Helpers

    private func collectNotifications(during operation: () async throws -> Void) async rethrows -> [Notification] {
        nonisolated(unsafe) var collected: [Notification] = []
        let lock = NSLock()
        let beginObserver = NotificationCenter.default.addObserver(
            forName: .coreDataEnsembleDidBeginActivity,
            object: ensemble,
            queue: nil
        ) { notif in
            lock.withLock { collected.append(notif) }
        }
        let endObserver = NotificationCenter.default.addObserver(
            forName: .coreDataEnsembleWillEndActivity,
            object: ensemble,
            queue: nil
        ) { notif in
            lock.withLock { collected.append(notif) }
        }
        defer {
            NotificationCenter.default.removeObserver(beginObserver)
            NotificationCenter.default.removeObserver(endObserver)
        }

        try await operation()

        return lock.withLock { collected }
    }

    private func assertActivityNotifications(_ notifications: [Notification], expectedActivity: EnsembleActivity, expectError: Bool) {
        let beginNotifs = notifications.filter { $0.name == .coreDataEnsembleDidBeginActivity }
        let endNotifs = notifications.filter { $0.name == .coreDataEnsembleWillEndActivity }

        #expect(beginNotifs.count >= 1, "Expected at least one begin notification")
        #expect(endNotifs.count >= 1, "Expected at least one end notification")

        if let begin = beginNotifs.first {
            let activity = begin.userInfo?[EnsembleNotificationKey.ensembleActivity] as? UInt
            #expect(activity == expectedActivity.rawValue)
            let error = begin.userInfo?[EnsembleNotificationKey.activityError]
            #expect(error == nil, "Begin notification should not have error")
        }

        if let end = endNotifs.last {
            let activity = end.userInfo?[EnsembleNotificationKey.ensembleActivity] as? UInt
            #expect(activity == expectedActivity.rawValue)
            let error = end.userInfo?[EnsembleNotificationKey.activityError]
            if expectError {
                #expect(error != nil, "End notification should have error")
            } else {
                #expect(error == nil, "End notification should not have error")
            }
        }
    }

    // MARK: - Attaching Notifications

    @Test("Attaching notifications")
    func attachingNotifications() async throws {
        let notifications = try await collectNotifications {
            try await ensemble.attachPersistentStore()
        }
        assertActivityNotifications(notifications, expectedActivity: .attaching, expectError: false)
    }

    @Test("Attaching with error notifications")
    func attachingWithErrorNotifications() async throws {
        // Remove the cloud directory to cause an error
        try FileManager.default.removeItem(atPath: cloudDir)

        let notifications = await collectNotifications {
            try? await ensemble.attachPersistentStore()
        }
        assertActivityNotifications(notifications, expectedActivity: .attaching, expectError: true)
    }

    // MARK: - Merging Notifications

    @Test("Merging notifications")
    func mergingNotifications() async throws {
        try await ensemble.attachPersistentStore()

        let notifications = try await collectNotifications {
            try await ensemble.sync()
        }
        assertActivityNotifications(notifications, expectedActivity: .syncing, expectError: false)
    }

    @Test("Merging with error notifications")
    func mergingWithErrorNotifications() async throws {
        try await ensemble.attachPersistentStore()
        try FileManager.default.removeItem(atPath: cloudDir)

        let notifications = await collectNotifications {
            try? await ensemble.sync()
        }
        assertActivityNotifications(notifications, expectedActivity: .syncing, expectError: true)
    }

    // MARK: - Detaching Notifications

    @Test("Detaching notifications")
    func detachingNotifications() async throws {
        try await ensemble.attachPersistentStore()

        let notifications = try await collectNotifications {
            try await ensemble.detachPersistentStore()
        }
        assertActivityNotifications(notifications, expectedActivity: .detaching, expectError: false)
    }

    @Test("Detaching with error notifications")
    func detachingWithErrorNotifications() async throws {
        try await ensemble.attachPersistentStore()

        // Remove the event store to cause an error
        try ensemble.eventStore.removeEventStore()

        let notifications = await collectNotifications {
            try? await ensemble.detachPersistentStore()
        }
        assertActivityNotifications(notifications, expectedActivity: .detaching, expectError: true)
    }
}
