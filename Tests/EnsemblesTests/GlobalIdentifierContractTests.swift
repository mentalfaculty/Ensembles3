import Testing
import Foundation
import CoreData
@_spi(Testing) import Ensembles
import EnsemblesMemory

@Suite("GlobalIdentifierContract", .serialized)
@MainActor
struct GlobalIdentifierContractTests {

    let rootTestDirectory: String
    let testModelURL: URL
    let storeURL: URL

    init() throws {
        rootTestDirectory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("GlobalIdContract_\(ProcessInfo.processInfo.globallyUniqueString)")
        try FileManager.default.createDirectory(atPath: rootTestDirectory, withIntermediateDirectories: true)
        testModelURL = Bundle.module.url(forResource: "CDEStoreModificationEventTestsModel", withExtension: "momd")!
        storeURL = URL(fileURLWithPath: (rootTestDirectory as NSString).appendingPathComponent("store.sql"))
    }

    private func makeEnsemble(delegate: (any CoreDataEnsembleDelegate)?) -> CoreDataEnsemble {
        let model = TestModelCache.model(for: testModelURL)!
        let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
        try! psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let cloudFS = MemoryCloudFileSystem()
        let edRoot = (rootTestDirectory as NSString).appendingPathComponent("eventData")
        let ensemble = CoreDataEnsemble(
            ensembleIdentifier: "test",
            persistentStoreURL: storeURL,
            persistentStoreOptions: nil,
            managedObjectModelURL: testModelURL,
            managedObjectModel: model,
            cloudFileSystem: cloudFS,
            localDataRootDirectoryURL: URL(fileURLWithPath: edRoot)
        )!
        ensemble.delegate = delegate
        return ensemble
    }

    // MARK: - Configuration check

    @Test("Attach throws missingGlobalIdentifierSource when no delegate is set")
    func attachThrowsWhenNoDelegate() async throws {
        let ensemble = makeEnsemble(delegate: nil)
        await #expect(throws: EnsembleError.missingGlobalIdentifierSource) {
            try await ensemble.attachPersistentStore()
        }
        ensemble.dismantle()
    }

    // MARK: - Behavioral notes
    //
    // The attach-time configuration check is intentionally minimal: it only verifies a
    // delegate is set. Delegates that return [] (meaning "no source configured") will
    // still pass the attach gate but later record rows with no globalID, which the
    // existing import / integration pipeline already tolerates. Empty-string elements
    // are caught by a precondition in CoreDataEnsemble.globalIdentifiers(forManagedObjects:)
    // — exercising that path requires a real attach + delegate invocation, which is
    // covered by the wider sync tests.

    // MARK: - JSON import

    private func makeEventStore(named: String) throws -> EventStore {
        let dir = (rootTestDirectory as NSString).appendingPathComponent(named)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = EventStore(ensembleIdentifier: named, pathToEventDataRootDirectory: rootTestDirectory)!
        try store.prepareNewEventStore()
        return store
    }

    private func writeEventJSON(_ dict: [String: Any], to fileName: String) throws -> URL {
        let url = URL(fileURLWithPath: (rootTestDirectory as NSString).appendingPathComponent(fileName))
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        try data.write(to: url)
        return url
    }

    @Test("JSON import rejects missing globalIdentifier in .ensembles3 mode")
    func jsonImportRejectsMissingGlobalIdentifierInEnsembles3() throws {
        let store = try makeEventStore(named: "e3")
        defer { store.dismantle() }

        // Three change-dicts; the middle one lacks globalIdentifier.
        let eventDict: [String: Any] = [
            "uniqueIdentifier": "evt-1",
            "type": 1,
            "globalCount": 1,
            "timestamp": "0",
            "storeIdentifier": "store-1",
            "revisionsByStoreIdentifier": ["store-1": 1],
            "changesByEntity": [
                "Parent": [
                    ["type": 100, "globalIdentifier": "gid-A"],
                    ["type": 100],
                    ["type": 100, "globalIdentifier": "gid-C"]
                ]
            ]
        ]
        let url = try writeEventJSON(eventDict, to: "e3.json")

        let importer = JSONEventImport(eventStore: store, importURLs: [url])
        importer.compatibilityMode = .ensembles3

        // EventImport.run() captures the error on `importer.error` AND re-throws.
        // `try?` swallows the throw so we can inspect `importer.error.code` below.
        try? importer.run()
        let nserror = importer.error as NSError?
        #expect(nserror?.code == EnsembleError.invalidGlobalIdentifier.rawValue,
                "Expected invalidGlobalIdentifier, got \(String(describing: importer.error))")
    }

    @Test("JSON import skips missing globalIdentifier in .ensembles2Compatible mode and preserves per-change indexing")
    func jsonImportSkipsMissingGlobalIdentifierInEnsembles2Compat() throws {
        // This is the regression for the compactMap index-drift bug. Property changes
        // must remain attached to the correct globalIdentifier row. Distinct property
        // values per change-dict let us prove no cross-wiring occurred — under the OLD
        // buggy code the last change's property would be silently lost AND the middle
        // change's property would attach to gid-C's row.
        let store = try makeEventStore(named: "e2c")
        defer { store.dismantle() }

        let eventDict: [String: Any] = [
            "uniqueIdentifier": "evt-2",
            "type": 1,
            "globalCount": 1,
            "timestamp": "0",
            "storeIdentifier": "store-1",
            "revisionsByStoreIdentifier": ["store-1": 1],
            "changesByEntity": [
                "Parent": [
                    ["type": 100,
                     "globalIdentifier": "gid-A",
                     "properties": [["type": 0, "propertyName": "name", "value": "A"]]],
                    ["type": 100,
                     "properties": [["type": 0, "propertyName": "name", "value": "X"]]],
                    ["type": 100,
                     "globalIdentifier": "gid-C",
                     "properties": [["type": 0, "propertyName": "name", "value": "C"]]]
                ]
            ]
        ]
        let url = try writeEventJSON(eventDict, to: "e2c.json")

        let importer = JSONEventImport(eventStore: store, importURLs: [url])
        importer.compatibilityMode = .ensembles2Compatible
        try importer.run()
        #expect(importer.error == nil)

        let gidA = try #require(try store.fetchGlobalIdentifier(globalIdentifier: "gid-A", nameOfEntity: "Parent"))
        let gidC = try #require(try store.fetchGlobalIdentifier(globalIdentifier: "gid-C", nameOfEntity: "Parent"))

        let eventId = try #require(importer.eventId)
        let allChanges = try store.fetchObjectChanges(eventId: eventId, nameOfEntity: "Parent")

        #expect(allChanges.count == 2,
                "Two change-dicts had valid globalIdentifiers — the third (bad) one must be skipped, not silently mis-attached. Got \(allChanges.count).")

        // Each gid row must own exactly its OWN change. Under the old compactMap+index
        // bug, gid-C's row would have ended up with the middle change's name="X"
        // properties because index 1 read changeDicts[1] (the bad one) instead of
        // changeDicts[2].
        func propertyValue(_ change: ObjectChange, _ name: String) -> StoredValue? {
            change.propertyChangeValues?.first(where: { $0.propertyName == name })?.value
        }

        let changeForA = try #require(allChanges.first(where: { $0.globalIdentifierId == gidA.id }))
        let changeForC = try #require(allChanges.first(where: { $0.globalIdentifierId == gidC.id }))

        // Compare via the underlying string value rather than constructing a
        // StoredValue for comparison (StoredValue's equality semantics aren't trivial).
        if case .string(let nameA)? = propertyValue(changeForA, "name") {
            #expect(nameA == "A", "gid-A's change must own properties from changeDicts[0]")
        } else {
            Issue.record("gid-A's change had no string 'name' property")
        }
        if case .string(let nameC)? = propertyValue(changeForC, "name") {
            #expect(nameC == "C", "gid-C's change must own properties from changeDicts[2], not cross-wired from changeDicts[1]")
        } else {
            Issue.record("gid-C's change had no string 'name' property")
        }
    }

    // MARK: - ObjectGraphMigrator

    @Test("ObjectGraphMigrator skips legacy rows with empty-string globalIdentifier")
    func objectGraphMigratorSkipsEmpty() throws {
        // Legacy E2 data may have CDEGlobalIdentifier rows with empty-string
        // globalIdentifier (and historically nil, but the model requires non-nil so
        // we cannot directly construct a nil row in a test; the migrator's nil
        // handling is by inspection — `value(forKey:) as? String` returns nil for
        // either nil or non-String values, both of which go through the same code
        // path as the empty-string case below). The migrator previously coerced
        // such values to "" and inserted anyway, collapsing multiple legacy
        // objects onto a single empty-string entry in the new event store. It
        // must now skip them.
        let legacyModel = try #require(EventStore.loadEventStoreModel())
        let psc = NSPersistentStoreCoordinator(managedObjectModel: legacyModel)
        _ = try psc.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        let legacyCtx = NSManagedObjectContext(.mainQueue)
        legacyCtx.persistentStoreCoordinator = psc

        let good = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: legacyCtx)
        good.setValue("real-id", forKey: "globalIdentifier")
        good.setValue("Parent", forKey: "nameOfEntity")
        good.setValue("x-coredata://store/Parent/p1", forKey: "storeURI")

        let emptyRow = NSEntityDescription.insertNewObject(forEntityName: "CDEGlobalIdentifier", into: legacyCtx)
        emptyRow.setValue("", forKey: "globalIdentifier")
        emptyRow.setValue("Parent", forKey: "nameOfEntity")
        emptyRow.setValue("x-coredata://store/Parent/p3", forKey: "storeURI")

        try legacyCtx.save()

        let store = try makeEventStore(named: "ogm")
        defer { store.dismantle() }

        let mapping = try ObjectGraphMigrator.migrateGlobalIdentifiers(from: legacyCtx, to: store)

        #expect(mapping[good.objectID] != nil, "Valid row must migrate")
        #expect(mapping[emptyRow.objectID] == nil, "Empty-string globalIdentifier row must be skipped")

        // Regression: no empty-string row should exist in the new event store.
        let emptyLookup = try store.fetchGlobalIdentifier(globalIdentifier: "", nameOfEntity: "Parent")
        #expect(emptyLookup == nil, "Empty-string row must not be inserted into the new event store")
    }
}
