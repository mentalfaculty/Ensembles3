import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles

@Suite("EventStore", .serialized)
struct EventStoreTests {

    let rootTestDirectory: String

    init() throws {
        rootTestDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("EventStoreTests_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootTestDirectory, withIntermediateDirectories: true)
    }

    private func makeStore(path: String? = nil) -> EventStore? {
        let dir = path ?? rootTestDirectory
        // Pre-create the test directory so removeEventStore in prepareNewEventStore doesn't fail
        let eventStoreDir = (dir as NSString).appendingPathComponent("test")
        try? FileManager.default.createDirectory(atPath: eventStoreDir, withIntermediateDirectories: true)
        return EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: dir)
    }

    // MARK: - Initialization

    @Test("Initialization")
    func initialization() {
        let store = makeStore()
        #expect(store != nil)
        #expect(store?.ensembleIdentifier == "test")
    }

    @Test("Has no persistent store identifier before install")
    func noPersistentStoreIdentifierBeforeInstall() {
        let store = makeStore()
        #expect(store?.persistentStoreIdentifier == nil)
    }

    @Test("Has no incomplete events before install")
    func noIncompleteEventsBeforeInstall() {
        let store = makeStore()!
        #expect(store.incompleteMandatoryEventIdentifiers.isEmpty)
    }

    @Test("Installing event store")
    func installingEventStore() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
    }

    @Test("Has persistent store identifier after install")
    func hasPersistentStoreIdentifierAfterInstall() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        #expect(store.persistentStoreIdentifier != nil)
    }

    // MARK: - Incomplete Events

    @Test("Registering incomplete mandatory event")
    func registeringIncompleteMandatoryEvent() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        store.registerIncompleteMandatoryEventIdentifier("TestID")
        #expect(store.incompleteMandatoryEventIdentifiers.count == 1)
        #expect(store.incompleteMandatoryEventIdentifiers.first == "TestID")
    }

    @Test("Deregistering incomplete event")
    func deregisteringIncompleteEvent() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        store.registerIncompleteMandatoryEventIdentifier("TestID")
        store.deregisterIncompleteMandatoryEventIdentifier("TestID")
        #expect(store.incompleteMandatoryEventIdentifiers.isEmpty)
    }

    @Test("Persistence of incomplete events")
    func persistenceOfIncompleteEvents() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        store.registerIncompleteMandatoryEventIdentifier("TestID")

        let newStore = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        #expect(newStore.incompleteMandatoryEventIdentifiers.count == 1)
        store.dismantle()
        newStore.dismantle()
    }

    // MARK: - Managed Object Context

    @Test("Managed object context is nil before install")
    func managedObjectContextNilBeforeInstall() {
        let store = makeStore()!
        #expect(store.managedObjectContext == nil)
    }

    @Test("Managed object context created after install")
    func managedObjectContextCreatedAfterInstall() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        #expect(store.managedObjectContext != nil)
        store.dismantle()
    }

    // MARK: - Store ID Persistence

    @Test("Event store saves store ID")
    func eventStoreSavesStoreId() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        let secondStore = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        #expect(store.persistentStoreIdentifier == secondStore.persistentStoreIdentifier)
        store.dismantle()
        secondStore.dismantle()
    }

    // MARK: - Data File Operations

    @Test("Importing data file")
    func importingDataFile() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        let file = (NSTemporaryDirectory() as NSString).appendingPathComponent("fileToImport_\(ProcessInfo.processInfo.globallyUniqueString)")
        try "Hi there".write(toFile: file, atomically: false, encoding: .utf8)
        #expect(store.importDataFile(atPath: file))

        let newDataPath = (store.pathToEventDataRootDirectory as NSString)
            .appendingPathComponent("test/newdata/\((file as NSString).lastPathComponent)")
        #expect(FileManager.default.fileExists(atPath: newDataPath))
        #expect(!FileManager.default.fileExists(atPath: file))

        store.dismantle()
    }

    @Test("Exporting data file")
    func exportingDataFile() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        let storePath = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/data/fileToExport")
        try FileManager.default.createDirectory(atPath: ((storePath as NSString).deletingLastPathComponent), withIntermediateDirectories: true)
        try "Hi there".write(toFile: storePath, atomically: false, encoding: .utf8)

        let exportDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("exporttest_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: exportDir, withIntermediateDirectories: true)

        let exportPath = (exportDir as NSString).appendingPathComponent("fileToExport")
        #expect(!FileManager.default.fileExists(atPath: exportPath))
        #expect(store.exportDataFile("fileToExport", toDirectory: exportDir))
        #expect(FileManager.default.fileExists(atPath: exportPath))

        try? FileManager.default.removeItem(atPath: exportDir)
        store.dismantle()
    }

    @Test("Removing data file")
    func removingDataFile() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        let storePath = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/data/fileToRemove")
        try FileManager.default.createDirectory(atPath: ((storePath as NSString).deletingLastPathComponent), withIntermediateDirectories: true)
        try "Hi there".write(toFile: storePath, atomically: false, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: storePath))
        #expect(store.removePreviouslyReferencedDataFile("fileToRemove"))
        #expect(!FileManager.default.fileExists(atPath: storePath))

        store.dismantle()
    }

    @Test("Retrieving data filenames")
    func retrievingDataFilenames() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        let dataPath = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/data")
        let newdataPath = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/newdata")
        try FileManager.default.createDirectory(atPath: dataPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newdataPath, withIntermediateDirectories: true)

        try "Hi".write(toFile: (dataPath as NSString).appendingPathComponent("file1"), atomically: false, encoding: .utf8)
        try "Hi".write(toFile: (newdataPath as NSString).appendingPathComponent("file2"), atomically: false, encoding: .utf8)

        let files = store.allDataFilenames
        #expect(files.count == 2)
        #expect(files.contains("file1"))
        #expect(files.contains("file2"))

        store.dismantle()
    }

    @Test("Removing outdated data files")
    func removingOutdatedDataFiles() async throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        store.managedObjectContext!.performAndWait {
            let ctx = store.managedObjectContext!

            // Create a minimal event and global identifier for the object change
            let event = NSEntityDescription.insertNewObject(forEntityName: "CDEStoreModificationEvent", into: ctx) as! StoreModificationEvent
            event.storeModificationEventType = .save
            event.timestamp = 10.0
            event.eventRevision = EventRevision.makeEventRevision(forPersistentStoreIdentifier: "store1", revisionNumber: 0, in: ctx)

            let gid = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: ctx) as! GlobalIdentifier
            gid.globalIdentifier = "gid1"
            gid.nameOfEntity = "Entity"

            let change = NSEntityDescription.insertNewObject(forEntityName: "CDEObjectChange", into: ctx) as! ObjectChange
            change.nameOfEntity = "Entity"
            change.objectChangeType = .insert
            change.storeModificationEvent = event
            change.globalIdentifier = gid

            let dataFile1 = NSEntityDescription.insertNewObject(forEntityName: "CDEDataFile", into: ctx) as! DataFile
            dataFile1.objectChange = change
            dataFile1.filename = "123"

            let dataFile2 = NSEntityDescription.insertNewObject(forEntityName: "CDEDataFile", into: ctx) as! DataFile
            dataFile2.filename = "345"

            try! ctx.save()
        }

        let dataDir = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/data")
        let newdataDir = (store.pathToEventDataRootDirectory as NSString).appendingPathComponent("test/newdata")
        try FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: newdataDir, withIntermediateDirectories: true)

        let storePath1 = (dataDir as NSString).appendingPathComponent("123")
        let storePath2 = (dataDir as NSString).appendingPathComponent("234")
        let storePath3 = (dataDir as NSString).appendingPathComponent("345")
        let storePath4 = (newdataDir as NSString).appendingPathComponent("789")

        try "Hi".write(toFile: storePath1, atomically: false, encoding: .utf8)
        try "Hi".write(toFile: storePath2, atomically: false, encoding: .utf8)
        try "Hi".write(toFile: storePath3, atomically: false, encoding: .utf8)
        try "Hi".write(toFile: storePath4, atomically: false, encoding: .utf8)

        try await store.removeUnreferencedDataFiles()

        #expect(FileManager.default.fileExists(atPath: storePath1))
        #expect(!FileManager.default.fileExists(atPath: storePath2))
        #expect(!FileManager.default.fileExists(atPath: storePath3))
        #expect(FileManager.default.fileExists(atPath: storePath4))

        store.dismantle()
    }
}
