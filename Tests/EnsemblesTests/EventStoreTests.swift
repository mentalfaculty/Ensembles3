import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

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

    // MARK: - Database

    @Test("Database is nil before install")
    func databaseNilBeforeInstall() {
        let store = makeStore()!
        #expect(store.database == nil)
    }

    @Test("Database created after install")
    func databaseCreatedAfterInstall() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        #expect(store.database != nil)
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

    @Test("Store identifier is discarded when the event database is missing")
    func storeIdentifierDiscardedWhenDatabaseMissing() throws {
        // Reproduces the E2->E3 decoupling. E3 renamed the event database file
        // (events.sqlite -> eventstore.db) with no migrator, but still carries the
        // id sidecar forward (store.plist -> store-metadata.plist). An E2->E3 update
        // therefore leaves the id present with no usable event database; E3 then
        // silently creates a fresh empty one. An EventStore that comes up with an
        // id but an empty database masquerades as "already attached" and re-imports
        // its own cloud baseline forever. A live store id must imply a populated
        // event store — the E2 invariant.
        let store = makeStore()!
        try store.prepareNewEventStore()
        _ = try store.insertEvent(uniqueIdentifier: "evt-1", type: .save)
        #expect(store.persistentStoreIdentifier != nil)
        let storeRoot = store.pathToEventStoreRootDirectory
        store.dismantle()

        // Delete only the event database, leaving store-metadata.plist behind —
        // exactly the state an E2->E3 app update produces.
        let dbPath = (storeRoot as NSString).appendingPathComponent("eventstore.db")
        let metadataPath = (storeRoot as NSString).appendingPathComponent("store-metadata.plist")
        let legacyPath = (storeRoot as NSString).appendingPathComponent("store.plist")
        try FileManager.default.removeItem(atPath: dbPath)
        #expect(FileManager.default.fileExists(atPath: metadataPath), "precondition: the stale sidecar is present")

        let reopened = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        #expect(reopened.persistentStoreIdentifier == nil, "Store id survived an empty/absent event database — install would masquerade as attached")
        #expect(!reopened.containsEventData)

        // The stale sidecar must be removed from disk — not just cleared in memory —
        // so the discard is durable across the next launch.
        #expect(!FileManager.default.fileExists(atPath: metadataPath), "stale store-metadata.plist must be deleted from disk")
        // E3 → E2 downgrade safety: E2 reads `store.plist`; the discard must not
        // resurrect one.
        #expect(!FileManager.default.fileExists(atPath: legacyPath), "discard must not create a store.plist")
        reopened.dismantle()

        // A second fresh init must also come up un-attached — proving the discard
        // is durable and not a one-shot in-memory effect.
        let reopenedAgain = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        #expect(reopenedAgain.persistentStoreIdentifier == nil)
        #expect(!reopenedAgain.containsEventData)
        reopenedAgain.dismantle()
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
    func removingOutdatedDataFiles() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        // Create event, global identifier, object change, and data file via EventStore CRUD
        let event = try store.insertEvent(uniqueIdentifier: "uid-1", type: .save, timestamp: 10.0)
        try store.insertRevision(persistentStoreIdentifier: "store1", revisionNumber: 0, eventId: event.id, isEventRevision: true)
        let gid = try store.insertGlobalIdentifier(globalIdentifier: "gid1", nameOfEntity: "Entity")
        let change = try store.insertObjectChange(type: .insert, nameOfEntity: "Entity", eventId: event.id, globalIdentifierId: gid.id)
        try store.insertDataFile(filename: "123", objectChangeId: change.id)

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

        try store.removeUnreferencedDataFiles()

        #expect(FileManager.default.fileExists(atPath: storePath1))
        #expect(!FileManager.default.fileExists(atPath: storePath2))
        #expect(!FileManager.default.fileExists(atPath: storePath3))
        #expect(FileManager.default.fileExists(atPath: storePath4))

        store.dismantle()
    }

    // MARK: - Baselines

    @Test("fetchBaselineEvent returns highest globalCount baseline")
    func fetchBaselineEventReturnsHighest() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 5)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 20)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 10)

        let baseline = try store.fetchBaselineEvent()
        #expect(baseline?.globalCount == 20)

        store.dismantle()
    }

    @Test("currentBaselineIdentifier returns identifier of highest globalCount baseline")
    func currentBaselineIdentifierReturnsHighest() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        try store.insertEvent(uniqueIdentifier: "old-base", type: .baseline, globalCount: 5)
        try store.insertEvent(uniqueIdentifier: "new-base", type: .baseline, globalCount: 15)

        #expect(store.currentBaselineIdentifier == "new-base")

        store.dismantle()
    }

    @Test("Multiple baselines coexist and fetchBaselineEvents returns all ordered by globalCount")
    func multipleBaselinesCoexist() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 10)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 3)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 20)

        let baselines = try store.fetchBaselineEvents()
        #expect(baselines.count == 3)
        #expect(baselines[0].globalCount == 3)
        #expect(baselines[1].globalCount == 10)
        #expect(baselines[2].globalCount == 20)

        store.dismantle()
    }

    @Test("Deleting old baselines preserves the most recent one")
    func deleteOldBaselines() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()

        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 5)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 15)
        try store.insertEvent(uniqueIdentifier: "base-A", type: .baseline, globalCount: 10)

        // Keep only the most recent
        let best = try store.fetchBaselineEvent()!
        let all = try store.fetchBaselineEvents()
        let oldIds = all.filter { $0.id != best.id }.map(\.id)
        try store.deleteEvents(ids: oldIds)

        let remaining = try store.fetchBaselineEvents()
        #expect(remaining.count == 1)
        #expect(remaining[0].globalCount == 15)

        store.dismantle()
    }

    // MARK: - Cloud Identity Token Round-Trip

    @Test("Identity token round-trips for an NSSecureCoding custom class (regression)")
    func identityTokenRoundTripCustomClass() throws {
        let store = makeStore()!
        let token = IdentityTokenStandIn("user-record-id-123")
        store.cloudFileSystemIdentityToken = token
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
            IdentityTokenStandIn.self,
        ])
        let restoredToken = restored.cloudFileSystemIdentityToken
        #expect((restoredToken as? NSObject)?.isEqual(token) == true,
                "Restored token must equal the original — this is the regression for cloudIdentityChanged-on-every-launch")
        restored.dismantle()
    }

    @Test("Identity token round-trips for an NSString")
    func identityTokenRoundTripNSString() throws {
        let store = makeStore()!
        let token: NSString = "an-account-email@example.com"
        store.cloudFileSystemIdentityToken = token
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
        ])
        let restoredToken = restored.cloudFileSystemIdentityToken as? NSString
        #expect(restoredToken == token)
        restored.dismantle()
    }

    @Test("Identity token round-trips as nil when never set")
    func identityTokenRoundTripNil() throws {
        // prepareNewEventStore() is the path that writes metadata while the token is still nil
        // on a fresh install. The restored value must be nil — never an NSNull placeholder,
        // which would compare unequal to a freshly-fetched real token on the next attach
        // and falsely trigger cloudIdentityChanged.
        let store = makeStore()!
        #expect(store.cloudFileSystemIdentityToken == nil)
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
        ])
        #expect(restored.cloudFileSystemIdentityToken == nil)
        restored.dismantle()
    }

    @Test("Identity token round-trips for a Foundation graph (NSDictionary of primitives)")
    func identityTokenRoundTripFoundationGraph() throws {
        let store = makeStore()!
        let token: NSDictionary = [
            "id": "user-42" as NSString,
            "session": NSNumber(value: 12345),
            "blob": Data([0x01, 0x02, 0x03]) as NSData,
        ]
        store.cloudFileSystemIdentityToken = token
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
        ])
        let restoredToken = restored.cloudFileSystemIdentityToken as? NSDictionary
        #expect(restoredToken == token)
        restored.dismantle()
    }

    @Test("Identity check uses isEqual semantics after round-trip")
    func identityTokenIsEqualSemantics() throws {
        // Pin to the exact comparison shape the production code performs at
        // CoreDataEnsemble.swift line 1072:
        //     (token as? NSObject)?.isEqual(eventStore.cloudFileSystemIdentityToken) ?? true
        // Guards against a future refactor that switches to `==` or `===` and silently
        // breaks the comparison for Foundation-bridged classes. Receiver direction
        // matches `identityTokenRoundTripCustomClass` for consistency across the section.
        let store = makeStore()!
        let original = IdentityTokenStandIn("user-record-id-123")
        store.cloudFileSystemIdentityToken = original
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
            IdentityTokenStandIn.self,
        ])
        let restoredToken = restored.cloudFileSystemIdentityToken
        #expect((restoredToken as? NSObject)?.isEqual(original) == true)
        restored.dismantle()
    }

    @Test("Round-trip preserves identity-check truth (mirrors checkCloudFileSystemIdentity)")
    func identityCheckTruthAfterRoundTrip() throws {
        // End-to-end: a token written by one EventStore and restored by another must
        // satisfy the same predicate that CoreDataEnsemble.checkCloudFileSystemIdentity
        // uses to decide whether to force a detach. If this fails, the user sees the
        // every-launch detach loop.
        let store = makeStore()!
        let original = IdentityTokenStandIn("user-record-id-123")
        store.cloudFileSystemIdentityToken = original
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
            IdentityTokenStandIn.self,
        ])
        // Live token fetched at next attach — same value, fresh allocation.
        // The nil clause mirrors the production predicate's shape; liveToken is never
        // actually nil here (the upcast is always non-nil), which is intentional — the
        // test exercises the isEqual branch, not the nil-token short-circuit.
        let liveToken = IdentityTokenStandIn("user-record-id-123")
        let identityValid = liveToken as NSObject? == nil
            || ((liveToken as NSObject).isEqual(restored.cloudFileSystemIdentityToken))
        #expect(identityValid)
        restored.dismantle()
    }

    @Test("Corrupt cloudFileSystemIdentity blob produces nil without crashing")
    func corruptIdentityBlobProducesNil() throws {
        // Set up a valid store first so the rest of the metadata is present and well-formed.
        let store = makeStore()!
        store.cloudFileSystemIdentityToken = IdentityTokenStandIn("user-record-id-123")
        try store.prepareNewEventStore()
        let storeInfoPath = (store.pathToEventStoreRootDirectory as NSString)
            .appendingPathComponent("store-metadata.plist")
        store.dismantle()

        // Corrupt only the cloudFileSystemIdentity entry of the on-disk plist.
        let plist = try #require(NSMutableDictionary(contentsOfFile: storeInfoPath))
        plist["cloudFileSystemIdentity"] = Data([0xDE, 0xAD, 0xBE, 0xEF])  // not a valid keyed archive
        #expect(plist.write(toFile: storeInfoPath, atomically: true))

        // Re-init: the unarchive should fail, the do/catch should swallow it (and log
        // at .error in the production code — verified by code review, not asserted here),
        // and the token should come back nil.
        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
            IdentityTokenStandIn.self,
        ])
        #expect(restored.cloudFileSystemIdentityToken == nil)
        restored.dismantle()
    }

    @Test("Token decodes with a tight per-backend allowlist (no NSObject catch-all)")
    func tightAllowlistDecodesCustomClass() throws {
        // Beta.9 used `NSObject.self` as a catch-all in the unarchive allowlist,
        // which Apple has begun warning will become an error. The fix replaces
        // the catch-all with a per-backend explicit list. This test proves the
        // explicit list works without the catch-all.
        let store = makeStore()!
        let original = IdentityTokenStandIn("user-record-id-123")
        store.cloudFileSystemIdentityToken = original
        try store.prepareNewEventStore()
        store.dismantle()

        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!

        // The deliberately tight list: Foundation primitives plus the concrete
        // stand-in. No NSObject.self.
        let allowed: [AnyClass] = [
            NSString.self, NSNumber.self, NSData.self, NSDate.self,
            NSUUID.self, NSURL.self, NSArray.self, NSDictionary.self,
            NSNull.self,
            IdentityTokenStandIn.self,
        ]
        restored.decodeCloudFileSystemIdentityToken(allowedClasses: allowed)

        let restoredToken = restored.cloudFileSystemIdentityToken
        #expect((restoredToken as? NSObject)?.isEqual(original) == true)
        restored.dismantle()
    }

    @Test("Default cloudIdentityTokenClasses contains Foundation primitives only")
    func defaultAllowlistContents() {
        // A backend that does not override `cloudIdentityTokenClasses` inherits the
        // protocol default. This test pins the documented contract: Foundation
        // primitives only — no NSObject catch-all.
        let fs = MemoryCloudFileSystem()
        let classes = fs.cloudIdentityTokenClasses
        let names = Set(classes.map { String(describing: $0) })

        let expected: Set<String> = [
            "NSString", "NSNumber", "NSData", "NSDate",
            "NSUUID", "NSURL", "NSArray", "NSDictionary",
            "NSNull",
        ]
        #expect(names == expected,
                "Default allowlist must be exactly Foundation primitives — guards against a regression that re-adds NSObject.self or any backend-specific class to the default")
    }

    // MARK: - Store Metadata Filename Migration

    @Test("Legacy store.plist is renamed to store-metadata.plist on init")
    func legacyStorePlistIsRenamed() throws {
        // Simulate a pre-rename install by pre-creating the legacy file with
        // the dictionary shape EventStore expects.
        let store = makeStore()!
        try store.prepareNewEventStore()
        let ensembleDir = store.pathToEventStoreRootDirectory
        store.dismantle()

        let legacyPath = (ensembleDir as NSString).appendingPathComponent("store.plist")
        let newPath = (ensembleDir as NSString).appendingPathComponent("store-metadata.plist")

        // Move the freshly-written file to the legacy filename, so the next init
        // looks like a pre-rename installation.
        try FileManager.default.moveItem(atPath: newPath, toPath: legacyPath)
        #expect(FileManager.default.fileExists(atPath: legacyPath))
        #expect(!FileManager.default.fileExists(atPath: newPath))

        // Re-init should rename the legacy file to the new name.
        let restored = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)!
        #expect(FileManager.default.fileExists(atPath: newPath))
        #expect(!FileManager.default.fileExists(atPath: legacyPath))
        #expect(restored.persistentStoreIdentifier != nil,
                "Metadata should be readable from the renamed file")
        restored.dismantle()
    }

    @Test("Rename is skipped when store-metadata.plist already exists")
    func renameSkippedWhenNewFileExists() throws {
        let store = makeStore()!
        try store.prepareNewEventStore()
        let ensembleDir = store.pathToEventStoreRootDirectory
        store.dismantle()

        let legacyPath = (ensembleDir as NSString).appendingPathComponent("store.plist")
        let newPath = (ensembleDir as NSString).appendingPathComponent("store-metadata.plist")

        // Plant a legacy file alongside the existing new file with deliberately
        // different contents so we can detect any clobber.
        let legacyMarker: NSDictionary = ["marker": "legacy"]
        legacyMarker.write(toFile: legacyPath, atomically: true)
        let newMarkerBefore = NSDictionary(contentsOfFile: newPath)

        _ = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)

        let newMarkerAfter = NSDictionary(contentsOfFile: newPath)
        #expect(newMarkerAfter == newMarkerBefore,
                "Existing store-metadata.plist must not be clobbered by the migration")
        #expect(FileManager.default.fileExists(atPath: legacyPath),
                "Legacy store.plist should be left alone when the new file already exists")
    }

    @Test("Migration is a no-op when neither file exists")
    func migrationIsNoOpOnFreshInstall() {
        // Init against a directory containing nothing — the migration helper
        // must not create either file on its own. Files are written later by
        // saveStoreMetadata, not by the migration.
        let ensembleDir = (rootTestDirectory as NSString).appendingPathComponent("test")
        try? FileManager.default.createDirectory(atPath: ensembleDir, withIntermediateDirectories: true)

        let store = EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: rootTestDirectory)
        defer { store?.dismantle() }

        let legacyPath = (ensembleDir as NSString).appendingPathComponent("store.plist")
        let newPath = (ensembleDir as NSString).appendingPathComponent("store-metadata.plist")
        #expect(!FileManager.default.fileExists(atPath: legacyPath))
        #expect(!FileManager.default.fileExists(atPath: newPath))
    }
}

// Stands in for CKRecord.ID so the core test target does not need to import CloudKit.
// Conforms to the same NSObjectProtocol & NSCopying & NSCoding contract that
// `EventStore.cloudFileSystemIdentityToken` requires, and to NSSecureCoding so it
// can be archived under `requiringSecureCoding: true`.
//
// The @objc annotation is load-bearing: NSKeyedArchiver records the ObjC class name in the
// archive, so without it the Swift-mangled name is encoded and the unarchiver cannot decode
// the token after any rename or module change.
@objc(IdentityTokenStandIn)
private final class IdentityTokenStandIn: NSObject, NSSecureCoding, NSCopying {
    static var supportsSecureCoding: Bool { true }

    let value: String

    init(_ value: String) {
        self.value = value
        super.init()
    }

    required init?(coder: NSCoder) {
        guard let v = coder.decodeObject(of: NSString.self, forKey: "value") as String? else {
            return nil
        }
        self.value = v
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(value as NSString, forKey: "value")
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? IdentityTokenStandIn else { return false }
        return other.value == value
    }

    override var hash: Int { value.hashValue }

    func copy(with zone: NSZone? = nil) -> Any { IdentityTokenStandIn(value) }
}
