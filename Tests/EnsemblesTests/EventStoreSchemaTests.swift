import Testing
import Foundation
@testable import Ensembles

@Suite("EventStoreSchema")
struct EventStoreSchemaTests {

    private func makeTempDB() throws -> SQLiteDatabase {
        let path = NSTemporaryDirectory() + "/schema_test_\(ProcessInfo.processInfo.globallyUniqueString).db"
        return try SQLiteDatabase(path: path)
    }

    @Test("Create schema creates all tables")
    func createAllTables() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        #expect(try db.tableExists("events"))
        #expect(try db.tableExists("revisions"))
        #expect(try db.tableExists("global_identifiers"))
        #expect(try db.tableExists("object_changes"))
        #expect(try db.tableExists("data_files"))
        #expect(try db.tableExists("schema_info"))
    }

    @Test("Schema version is recorded")
    func schemaVersion() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        let version = try EventStoreSchema.currentVersion(in: db)
        #expect(version == EventStoreSchema.version)
    }

    @Test("Schema version returns nil for empty database")
    func noVersionForEmptyDB() throws {
        let db = try makeTempDB()
        let version = try EventStoreSchema.currentVersion(in: db)
        #expect(version == nil)
    }

    @Test("Insert and query events")
    func insertAndQueryEvents() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute(
            "INSERT INTO events (uniqueIdentifier, type, timestamp, globalCount, modelVersion) VALUES (?, ?, ?, ?, ?)",
            bindings: [.text("uid-1"), .integer(200), .real(1000.0), .integer(1), .text("v1")]
        )

        let rows = try db.query("SELECT id, uniqueIdentifier, type, timestamp, globalCount, modelVersion FROM events")
        #expect(rows.count == 1)
        #expect(rows[0][1] == .text("uid-1"))
        #expect(rows[0][2] == .integer(200))
        #expect(rows[0][3] == .real(1000.0))
        #expect(rows[0][4] == .integer(1))
        #expect(rows[0][5] == .text("v1"))
    }

    @Test("Insert and query revisions")
    func insertAndQueryRevisions() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute(
            "INSERT INTO events (uniqueIdentifier, type) VALUES (?, ?)",
            bindings: [.text("uid-1"), .integer(200)]
        )
        let eventId = db.lastInsertRowID

        try db.execute(
            "INSERT INTO revisions (persistentStoreIdentifier, revisionNumber, eventId, isEventRevision) VALUES (?, ?, ?, ?)",
            bindings: [.text("store-1"), .integer(5), .integer(eventId), .integer(1)]
        )

        let rows = try db.query("SELECT persistentStoreIdentifier, revisionNumber, isEventRevision FROM revisions WHERE eventId = ?", bindings: [.integer(eventId)])
        #expect(rows.count == 1)
        #expect(rows[0][0] == .text("store-1"))
        #expect(rows[0][1] == .integer(5))
        #expect(rows[0][2] == .integer(1))
    }

    @Test("Cascade delete from events to revisions")
    func cascadeDeleteRevisions() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 200)")
        let eventId = db.lastInsertRowID
        try db.execute("INSERT INTO revisions (persistentStoreIdentifier, revisionNumber, eventId, isEventRevision) VALUES ('s1', 1, ?, 1)", bindings: [.integer(eventId)])
        try db.execute("INSERT INTO revisions (persistentStoreIdentifier, revisionNumber, eventId, isEventRevision) VALUES ('s2', 2, ?, 0)", bindings: [.integer(eventId)])

        var revCount = try db.queryScalar("SELECT count(*) FROM revisions")
        #expect(revCount == 2)

        try db.execute("DELETE FROM events WHERE id = ?", bindings: [.integer(eventId)])
        revCount = try db.queryScalar("SELECT count(*) FROM revisions")
        #expect(revCount == 0)
    }

    @Test("Cascade delete from events to object changes")
    func cascadeDeleteObjectChanges() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 200)")
        let eventId = db.lastInsertRowID
        try db.execute("INSERT INTO global_identifiers (globalIdentifier, nameOfEntity) VALUES ('gid-1', 'Entity')")
        let globalIdId = db.lastInsertRowID
        try db.execute("INSERT INTO object_changes (type, nameOfEntity, eventId, globalIdentifierId) VALUES (100, 'Entity', ?, ?)", bindings: [.integer(eventId), .integer(globalIdId)])

        var changeCount = try db.queryScalar("SELECT count(*) FROM object_changes")
        #expect(changeCount == 1)

        try db.execute("DELETE FROM events WHERE id = ?", bindings: [.integer(eventId)])
        changeCount = try db.queryScalar("SELECT count(*) FROM object_changes")
        #expect(changeCount == 0)
    }

    @Test("Cascade delete from object changes to data files")
    func cascadeDeleteDataFiles() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 200)")
        let eventId = db.lastInsertRowID
        try db.execute("INSERT INTO global_identifiers (globalIdentifier, nameOfEntity) VALUES ('gid-1', 'Entity')")
        let globalIdId = db.lastInsertRowID
        try db.execute("INSERT INTO object_changes (type, nameOfEntity, eventId, globalIdentifierId) VALUES (100, 'Entity', ?, ?)", bindings: [.integer(eventId), .integer(globalIdId)])
        let changeId = db.lastInsertRowID
        try db.execute("INSERT INTO data_files (filename, objectChangeId) VALUES ('file1.dat', ?)", bindings: [.integer(changeId)])

        var fileCount = try db.queryScalar("SELECT count(*) FROM data_files")
        #expect(fileCount == 1)

        try db.execute("DELETE FROM object_changes WHERE id = ?", bindings: [.integer(changeId)])
        fileCount = try db.queryScalar("SELECT count(*) FROM data_files")
        #expect(fileCount == 0)
    }

    @Test("Duplicate uniqueIdentifier allowed on events")
    func duplicateUniqueIdentifierAllowed() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 200)")
        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 300)")

        let count = try db.queryScalar("SELECT count(*) FROM events WHERE uniqueIdentifier = 'uid-1'")
        #expect(count == 2)
    }

    @Test("Global identifiers allow same identifier for different entities")
    func globalIdentifiersDifferentEntities() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO global_identifiers (globalIdentifier, nameOfEntity) VALUES ('gid-1', 'EntityA')")
        try db.execute("INSERT INTO global_identifiers (globalIdentifier, nameOfEntity) VALUES ('gid-1', 'EntityB')")

        let count = try db.queryScalar("SELECT count(*) FROM global_identifiers WHERE globalIdentifier = 'gid-1'")
        #expect(count == 2)
    }

    @Test("Property changes stored as JSON blob")
    func propertyChangesBlob() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)

        try db.execute("INSERT INTO events (uniqueIdentifier, type) VALUES ('uid-1', 200)")
        let eventId = db.lastInsertRowID
        try db.execute("INSERT INTO global_identifiers (globalIdentifier, nameOfEntity) VALUES ('gid-1', 'Entity')")
        let globalIdId = db.lastInsertRowID

        let changes = [
            StoredPropertyChange(type: 0, propertyName: "name", value: .string("Alice")),
            StoredPropertyChange(type: 0, propertyName: "age", value: .int(30)),
        ]
        let jsonData = try StoredPropertyChange.encode(changes)

        try db.execute(
            "INSERT INTO object_changes (type, nameOfEntity, eventId, globalIdentifierId, propertyChanges) VALUES (?, ?, ?, ?, ?)",
            bindings: [.integer(100), .text("Entity"), .integer(eventId), .integer(globalIdId), .blob(jsonData)]
        )

        let row = try db.querySingle("SELECT propertyChanges FROM object_changes WHERE id = ?", bindings: [.integer(db.lastInsertRowID)])
        guard let row, case .blob(let blobData) = row[0] else {
            Issue.record("Expected blob data")
            return
        }

        let decoded = try StoredPropertyChange.decode(from: blobData)
        #expect(decoded.count == 2)
        #expect(decoded[0].propertyName == "name")
        #expect(decoded[0].value == .string("Alice"))
        #expect(decoded[1].propertyName == "age")
        #expect(decoded[1].value == .int(30))
    }

    @Test("Schema is idempotent")
    func schemaIdempotent() throws {
        let db = try makeTempDB()
        try EventStoreSchema.create(in: db)
        try EventStoreSchema.create(in: db) // Should not fail

        let count = try db.queryScalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='events'")
        #expect(count == 1)
    }
}
