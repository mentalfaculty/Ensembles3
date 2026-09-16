import Testing
import Foundation
@_spi(Testing) import Ensembles

/// An import whose file handling is supplied by closures, so tests can observe and
/// sabotage the import sequence at precise points.
private final class ScriptedEventImport: EventImport, @unchecked Sendable {
    var onFirstFile: ((URL) throws -> StoreModificationEvent?)?
    var onSubsequentFile: ((URL) throws -> Bool)?

    override func importFirstFile(at url: URL) throws -> StoreModificationEvent? {
        try onFirstFile?(url)
    }

    override func importSubsequentFile(at url: URL) throws -> Bool {
        try onSubsequentFile?(url) ?? false
    }
}

/// Event import must be atomic: either the complete event with all of its parts
/// commits, or nothing is ever visible. The `.incomplete` marking and the
/// delete-on-failure cleanup are separate, fallible writes; if a process dies (or a
/// write fails) between them, a partially imported event is left behind wearing its
/// real type. A zero-change baseline that escaped this way superseded a customer's
/// real baseline and emptied their store (Keith, 2026-08-16).
@Suite("EventImportAtomicity", .serialized)
struct EventImportAtomicityTests {

    let setup: TestEventStoreSetup
    let databasePath: String

    init() throws {
        setup = try TestEventStoreSetup(useDiskTestStore: true, loadTestModel: true)
        databasePath = (setup.eventStore.pathToEventStoreRootDirectory as NSString)
            .appendingPathComponent("eventstore.db")
    }

    private func eventCount(inSecondConnectionFor uniqueIdentifier: String) throws -> Int64 {
        // A separate connection sees only committed state. This is exactly what a
        // concurrently launched process (or the next launch after a crash) sees.
        let second = try SQLiteDatabase(path: databasePath)
        return try second.queryScalar(
            "SELECT count(*) FROM events WHERE uniqueIdentifier = ?",
            bindings: [.text(uniqueIdentifier)]
        ) ?? -1
    }

    @Test("A multipart import is invisible to other connections until it completes")
    func importIsInvisibleUntilComplete() throws {
        let uid = "ATOMIC-TEST-\(ProcessInfo.processInfo.globallyUniqueString)"
        let store = setup.eventStore

        let importer = ScriptedEventImport(
            eventStore: store,
            importURLs: [URL(fileURLWithPath: "/part1"), URL(fileURLWithPath: "/part2")]
        )
        importer.onFirstFile = { [weak importer] _ in
            // A .save event: the isolation property under test is type-agnostic,
            // and a zero-change multipart baseline would (correctly) trip the
            // empty-multipart-baseline corruption check.
            guard let importer else { return nil }
            return try importer.createEvent(
                ofType: .save,
                uniqueIdentifier: uid,
                timestamp: 123,
                globalCount: 3097
            )
        }

        var visibleMidImport: Int64 = -1
        importer.onSubsequentFile = { _ in
            visibleMidImport = try self.eventCount(inSecondConnectionFor: uid)
            return true
        }

        try importer.run()

        // Mid-import, no other connection may see the half-imported event.
        #expect(visibleMidImport == 0)

        // After completion, the committed event is visible to everyone.
        #expect(try eventCount(inSecondConnectionFor: uid) == 1)
    }

    @Test("A multipart baseline importing with no object changes is refused as corrupt")
    func emptyMultipartBaselineIsRefused() throws {
        // An event is split into parts only when it carries more changes than
        // fit in a single part, so a legitimate multipart baseline is never empty. Zero
        // changes after a multipart import means the parts' content was lost or
        // corrupted in transit. Committing it would be catastrophic: an empty
        // baseline wearing type .baseline passes every integrity check (no
        // changes, so no data files or model versions to verify) and can
        // supersede the real baseline downstream. A single-part empty baseline
        // remains importable: deleting all data is a legitimate fleet state.
        let uid = "EMPTY-MULTIPART-\(ProcessInfo.processInfo.globallyUniqueString)"
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())

        let part1 = tempDir.appendingPathComponent("\(uid)_1of2.cdeevent")
        let part1JSON = """
        {"uniqueIdentifier": "\(uid)", "type": 100, "globalCount": 3097, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 12}}
        """
        try Data(part1JSON.utf8).write(to: part1)
        defer { try? FileManager.default.removeItem(at: part1) }

        let part2 = tempDir.appendingPathComponent("\(uid)_2of2.cdeevent")
        try Data("{\"changesByEntity\": {}}".utf8).write(to: part2)
        defer { try? FileManager.default.removeItem(at: part2) }

        let importer = JSONEventImport(eventStore: setup.eventStore, importURLs: [part1, part2])

        do {
            try importer.run()
            Issue.record("Import of an empty multipart baseline should have thrown")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == EnsembleError.errorDomain)
            #expect(nsError.code == EnsembleError.corruptEventContent.rawValue)
        }

        #expect(try eventCount(inSecondConnectionFor: uid) == 0)
    }

    @Test("A concurrent transaction is serialized against an import, never joined to it")
    func concurrentTransactionIsNotJoinedToImport() throws {
        // SQLite transactions belong to the connection, not the thread: without
        // serialization, a save capture's transaction opened while an import
        // transaction is in flight becomes a savepoint INSIDE it, and the
        // import's rollback silently erases the successfully-reported capture.
        let importUID = "CONCURRENT-IMPORT-\(ProcessInfo.processInfo.globallyUniqueString)"
        let captureUID = "CONCURRENT-CAPTURE-\(ProcessInfo.processInfo.globallyUniqueString)"
        let store = setup.eventStore

        struct ImportSabotaged: Error {}
        let importInsideTransaction = DispatchSemaphore(value: 0)
        let captureFinished = DispatchSemaphore(value: 0)

        let importer = ScriptedEventImport(
            eventStore: store,
            importURLs: [URL(fileURLWithPath: "/part1"), URL(fileURLWithPath: "/part2")]
        )
        importer.onFirstFile = { [weak importer] _ in
            guard let importer else { return nil }
            return try importer.createEvent(
                ofType: .save,
                uniqueIdentifier: importUID,
                timestamp: 123,
                globalCount: 10
            )
        }
        importer.onSubsequentFile = { _ in
            // Let the "capture" thread attempt its transaction while ours is
            // open, give it time to either block (correct) or run joined to us
            // (the defect), then fail the import so our transaction rolls back.
            importInsideTransaction.signal()
            Thread.sleep(forTimeInterval: 0.2)
            throw ImportSabotaged()
        }

        let captureThread = Thread {
            // Timed, so a regression that fails the import before signaling
            // cannot leak a permanently blocked thread.
            _ = importInsideTransaction.wait(timeout: .now() + 10)
            do {
                try store.withTransaction {
                    _ = try store.insertEvent(
                        uniqueIdentifier: captureUID,
                        type: .save,
                        timestamp: 124,
                        globalCount: 11
                    )
                }
            } catch {
                // Recorded via the missing row below.
            }
            captureFinished.signal()
        }
        captureThread.start()

        #expect(throws: ImportSabotaged.self) {
            try importer.run()
        }
        #expect(captureFinished.wait(timeout: .now() + 10) == .success)

        // The capture committed independently and must survive the import's
        // rollback; the import's own event must be gone.
        #expect(try eventCount(inSecondConnectionFor: captureUID) == 1)
        #expect(try eventCount(inSecondConnectionFor: importUID) == 0)
    }

    @Test("The empty-baseline refusal surfaces directly, without a binary-format retry")
    func emptyBaselineRefusalIsNotRetriedAsBinary() async throws {
        // The refusal means "parsed fine, content corrupt". Retrying such a file
        // as a legacy binary store cannot succeed and buries the precise
        // diagnosis inside a generic could-not-import-in-any-format wrapper.
        let uid = "EMPTY-MULTIPART-ROUTE-\(ProcessInfo.processInfo.globallyUniqueString)"
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())

        let part1 = tempDir.appendingPathComponent("\(uid)_1of2.cdeevent")
        let part1JSON = """
        {"uniqueIdentifier": "\(uid)", "type": 100, "globalCount": 3097, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 12}}
        """
        try Data(part1JSON.utf8).write(to: part1)
        defer { try? FileManager.default.removeItem(at: part1) }

        let part2 = tempDir.appendingPathComponent("\(uid)_2of2.cdeevent")
        try Data("{\"changesByEntity\": {}}".utf8).write(to: part2)
        defer { try? FileManager.default.removeItem(at: part2) }

        let migrator = EventMigrator(eventStore: setup.eventStore, managedObjectModel: setup.testModel!)

        do {
            _ = try await migrator.migrateEventIn(from: [part1, part2])
            Issue.record("Migrating an empty multipart baseline should have thrown")
        } catch {
            let nsError = error as NSError
            #expect(nsError.domain == EnsembleError.errorDomain)
            #expect(nsError.code == EnsembleError.corruptEventContent.rawValue)
            // Not the combined both-formats-failed wrapper: no binary retry ran.
            #expect(nsError.userInfo[NSMultipleUnderlyingErrorsKey] == nil)
        }
    }

    @Test("A legitimate single-part empty baseline still imports")
    func singlePartEmptyBaselineImports() throws {
        // Pins the refusal's scope: a fleet that deleted all of its data rebases
        // to a genuinely empty baseline, which is small enough to always be a
        // single file. Refusing it would stop such deletions from propagating.
        let uid = "EMPTY-SINGLE-\(ProcessInfo.processInfo.globallyUniqueString)"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(uid).cdeevent")
        let json = """
        {"uniqueIdentifier": "\(uid)", "type": 100, "globalCount": 3200, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 13}, \
        "changesByEntity": {}}
        """
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let importer = JSONEventImport(eventStore: setup.eventStore, importURLs: [file])
        try importer.run()

        #expect(try eventCount(inSecondConnectionFor: uid) == 1)
    }

    @Test("A failed multipart import leaves nothing behind")
    func failedImportRollsBackCompletely() throws {
        let uid = "ATOMIC-FAIL-\(ProcessInfo.processInfo.globallyUniqueString)"
        let store = setup.eventStore

        struct PartUnreadable: Error {}

        let importer = ScriptedEventImport(
            eventStore: store,
            importURLs: [URL(fileURLWithPath: "/part1"), URL(fileURLWithPath: "/part2")]
        )
        importer.onFirstFile = { [weak importer] _ in
            guard let importer else { return nil }
            return try importer.createEvent(
                ofType: .baseline,
                uniqueIdentifier: uid,
                timestamp: 123,
                globalCount: 3097
            )
        }
        importer.onSubsequentFile = { _ in throw PartUnreadable() }

        #expect(throws: PartUnreadable.self) {
            try importer.run()
        }

        #expect(try eventCount(inSecondConnectionFor: uid) == 0)
    }

    @Test("The event row is Incomplete from creation until the last part commits")
    func rowIsIncompleteUntilImportCompletes() throws {
        // This is the second safety layer, independent of the transaction: an
        // `.incomplete` row is removed at the next launch, a real-typed one is
        // adopted. 3.0.8 inserted the row with its real type and marked it
        // incomplete only after the first part's changes had been written, so a
        // process killed during the first part left a real-typed partial baseline
        // behind (Keith, Writing Shed Pro, 2026-09). The marking must happen at
        // creation, before any change is written.
        let uid = "INCOMPLETE-FIRST-\(ProcessInfo.processInfo.globallyUniqueString)"
        let store = setup.eventStore

        let importer = ScriptedEventImport(
            eventStore: store,
            importURLs: [URL(fileURLWithPath: "/part1"), URL(fileURLWithPath: "/part2")]
        )

        var typeAfterCreation: StoreModificationEventType?
        var typeDuringSecondPart: StoreModificationEventType?

        importer.onFirstFile = { [weak importer] _ in
            guard let importer else { return nil }
            let event = try importer.createEvent(
                ofType: .save,
                uniqueIdentifier: uid,
                timestamp: 123,
                globalCount: 42
            )
            // Same connection, so this sees the uncommitted row as written.
            typeAfterCreation = try store.fetchEvent(id: event.id)?.type
            return event
        }
        importer.onSubsequentFile = { [weak importer] _ in
            guard let eventId = importer?.eventId else { return false }
            typeDuringSecondPart = try store.fetchEvent(id: eventId)?.type
            return true
        }

        try importer.run()

        #expect(typeAfterCreation == .incomplete)
        #expect(typeDuringSecondPart == .incomplete)

        let eventId = try #require(importer.eventId)
        #expect(try store.fetchEvent(id: eventId)?.type == .save)
    }

    @Test("An imported baseline is stored as missing dependencies, never as a live baseline")
    func importedBaselineIsStoredAsMissingDependencies() throws {
        // A baseline arriving from the cloud must be dependency-checked by the
        // consolidator before it can become the current baseline. The declared
        // type is 100 (.baseline); the stored type after import must be 400.
        let uid = "BASELINE-400-\(ProcessInfo.processInfo.globallyUniqueString)"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(uid).cdeevent")
        let json = """
        {"uniqueIdentifier": "\(uid)", "type": 100, "globalCount": 3300, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 14}, \
        "changesByEntity": {}}
        """
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let importer = JSONEventImport(eventStore: setup.eventStore, importURLs: [file])
        try importer.run()

        let eventId = try #require(importer.eventId)
        #expect(try setup.eventStore.fetchEvent(id: eventId)?.type == .baselineMissingDependencies)
    }

    @Test("A first file that bypasses createEvent is refused and leaves nothing behind")
    func firstFileMustUseCreateEvent() throws {
        // Guards the invariant against a future importer inserting the row itself
        // with its real type — the exact regression that produced the 3.0.8 defect.
        let uid = "BYPASS-\(ProcessInfo.processInfo.globallyUniqueString)"
        let store = setup.eventStore

        let importer = ScriptedEventImport(
            eventStore: store,
            importURLs: [URL(fileURLWithPath: "/part1")]
        )
        importer.onFirstFile = { _ in
            try store.insertEvent(
                uniqueIdentifier: uid,
                type: .save,
                timestamp: 123,
                globalCount: 43
            )
        }

        #expect(throws: (any Error).self) {
            try importer.run()
        }
        // The guard, specifically — not some other failure along the way.
        let error = try #require(importer.error as NSError?)
        #expect(error.domain == EnsembleError.errorDomain)
        #expect(error.code == EnsembleError.unknown.rawValue)
        #expect(error.localizedDescription.contains("instead of .incomplete"))
        #expect(try eventCount(inSecondConnectionFor: uid) == 0)
    }

    @Test("JSONEventImport writes the row Incomplete before its object changes")
    func jsonImporterCreatesRowIncompleteBeforeChanges() throws {
        // Pins the REAL importer, not the scripted one: calling importFirstFile
        // directly, without run(), leaves exactly the state a kill during the first
        // part would leave. That state must be an .incomplete row that already
        // holds changes — the 3.0.8 ordering left a real-typed row here.
        let uid = "JSON-ORDER-\(ProcessInfo.processInfo.globallyUniqueString)"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(uid).cdeevent")
        let json = """
        {"uniqueIdentifier": "\(uid)", "type": 200, "globalCount": 44, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 15}, \
        "changesByEntity": {"Parent": [{"type": 100, "globalIdentifier": "\(uid)-A"}, \
        {"type": 100, "globalIdentifier": "\(uid)-B"}]}}
        """
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let importer = JSONEventImport(eventStore: setup.eventStore, importURLs: [file])
        let event = try #require(try importer.importFirstFile(at: file))

        #expect(try setup.eventStore.fetchEvent(id: event.id)?.type == .incomplete)
        #expect(try setup.eventStore.fetchObjectChangeCount(eventId: event.id) == 2)
    }

    @Test("PersistentStoreEventImport writes the row Incomplete before its object changes")
    func binaryImporterCreatesRowIncompleteBeforeChanges() throws {
        // Same property for the Ensembles 2 binary-file path.
        let uid = "BINARY-ORDER-\(ProcessInfo.processInfo.globallyUniqueString)"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(uid).cdeevent")
        let json = """
        {"uniqueIdentifier": "\(uid)", "type": 200, "globalCount": 45, "timestamp": "5", \
        "storeIdentifier": "storeX", "revisionsByStoreIdentifier": {"storeX": 16}, \
        "changesByEntity": {"Parent": [{"type": 100, "globalIdentifier": "\(uid)-A"}]}}
        """
        try Data(json.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        // Source event, exported to the legacy Core Data format.
        let source = JSONEventImport(eventStore: setup.eventStore, importURLs: [file])
        try source.run()
        let sourceEventId = try #require(source.eventId)
        let exporter = try #require(PersistentStoreEventExport(eventStore: setup.eventStore, eventId: sourceEventId, managedObjectModel: setup.testModel!))
        try exporter.run()
        let legacyFiles = exporter.fileURLs
        try #require(!legacyFiles.isEmpty)

        // A fresh event store to import into.
        let importDir = (setup.tempDirectory as NSString).appendingPathComponent("import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: (importDir as NSString).appendingPathComponent("test"), withIntermediateDirectories: true)
        let importStore = try #require(EventStore(ensembleIdentifier: "test", pathToEventDataRootDirectory: importDir))
        try importStore.prepareNewEventStore()

        let importer = PersistentStoreEventImport(eventStore: importStore, importURLs: legacyFiles)
        importer.prepareToImport()
        let event = try #require(try importer.importFirstFile(at: legacyFiles[0]))

        #expect(try importStore.fetchEvent(id: event.id)?.type == .incomplete)
        #expect(try importStore.fetchObjectChangeCount(eventId: event.id) == 1)
    }
}
