import Testing
import Foundation
@testable import Ensembles

@Suite("SQLiteDatabase")
struct SQLiteDatabaseTests {

    private func makeTempDB() throws -> SQLiteDatabase {
        let path = NSTemporaryDirectory() + "/test_\(ProcessInfo.processInfo.globallyUniqueString).db"
        return try SQLiteDatabase(path: path)
    }

    @Test("Open and close database")
    func openAndClose() throws {
        let db = try makeTempDB()
        #expect(db.isOpen)
        db.close()
        #expect(!db.isOpen)
    }

    @Test("Create table and insert rows")
    func createAndInsert() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Alice")])
        let rowid = db.lastInsertRowID
        #expect(rowid == 1)

        try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Bob")])
        #expect(db.lastInsertRowID == 2)
    }

    @Test("Query returns correct rows")
    func queryRows() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
        try db.execute("INSERT INTO t (name, score) VALUES (?, ?)", bindings: [.text("Alice"), .real(9.5)])
        try db.execute("INSERT INTO t (name, score) VALUES (?, ?)", bindings: [.text("Bob"), .real(7.0)])

        let rows = try db.query("SELECT id, name, score FROM t ORDER BY id")
        #expect(rows.count == 2)
        #expect(rows[0][1] == .text("Alice"))
        #expect(rows[0][2] == .real(9.5))
        #expect(rows[1][1] == .text("Bob"))
    }

    @Test("Query single row")
    func querySingle() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Alice")])

        let row = try db.querySingle("SELECT name FROM t WHERE id = ?", bindings: [.integer(1)])
        #expect(row?[0] == .text("Alice"))

        let noRow = try db.querySingle("SELECT name FROM t WHERE id = ?", bindings: [.integer(99)])
        #expect(noRow == nil)
    }

    @Test("Query scalar")
    func queryScalar() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        try db.execute("INSERT INTO t VALUES (NULL)")
        try db.execute("INSERT INTO t VALUES (NULL)")
        try db.execute("INSERT INTO t VALUES (NULL)")

        let count = try db.queryScalar("SELECT count(*) FROM t")
        #expect(count == 3)
    }

    @Test("Null binding and retrieval")
    func nullValues() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.null])

        let row = try db.querySingle("SELECT name FROM t WHERE id = 1")
        #expect(row?[0] == .null)
        #expect(row?[0].isNull == true)
    }

    @Test("Blob binding and retrieval")
    func blobValues() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, data BLOB)")
        let testData = Data([0x01, 0x02, 0x03, 0xFF])
        try db.execute("INSERT INTO t (data) VALUES (?)", bindings: [.blob(testData)])

        let row = try db.querySingle("SELECT data FROM t WHERE id = 1")
        #expect(row?[0] == .blob(testData))
        #expect(row?[0].blobValue == testData)
    }

    @Test("Transaction commits on success")
    func transactionCommit() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        try db.withTransaction {
            try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Alice")])
            try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Bob")])
        }

        let count = try db.queryScalar("SELECT count(*) FROM t")
        #expect(count == 2)
    }

    @Test("Transaction rolls back on error")
    func transactionRollback() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")

        do {
            try db.withTransaction {
                try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Alice")])
                try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.null]) // Should fail: NOT NULL constraint
            }
            Issue.record("Expected transaction to throw")
        } catch {
            // Expected
        }

        let count = try db.queryScalar("SELECT count(*) FROM t")
        #expect(count == 0) // Rolled back
    }

    @Test("Savepoint commits on success")
    func savepointCommit() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        try db.withSavepoint {
            try db.execute("INSERT INTO t (name) VALUES (?)", bindings: [.text("Alice")])
        }

        let count = try db.queryScalar("SELECT count(*) FROM t")
        #expect(count == 1)
    }

    @Test("Table exists check")
    func tableExists() throws {
        let db = try makeTempDB()
        #expect(try db.tableExists("nonexistent") == false)
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
        #expect(try db.tableExists("t") == true)
    }

    @Test("WAL mode is enabled")
    func walMode() throws {
        let db = try makeTempDB()
        let row = try db.querySingle("PRAGMA journal_mode")
        #expect(row?[0] == .text("wal"))
    }

    @Test("Foreign keys are enabled")
    func foreignKeys() throws {
        let db = try makeTempDB()
        let row = try db.querySingle("PRAGMA foreign_keys")
        #expect(row?[0] == .integer(1))
    }

    @Test("Foreign key cascade delete")
    func foreignKeyCascade() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE parent (id INTEGER PRIMARY KEY)")
        try db.execute("CREATE TABLE child (id INTEGER PRIMARY KEY, parentId INTEGER REFERENCES parent(id) ON DELETE CASCADE)")

        try db.execute("INSERT INTO parent (id) VALUES (1)")
        try db.execute("INSERT INTO child (parentId) VALUES (1)")
        try db.execute("INSERT INTO child (parentId) VALUES (1)")

        var childCount = try db.queryScalar("SELECT count(*) FROM child")
        #expect(childCount == 2)

        try db.execute("DELETE FROM parent WHERE id = 1")
        childCount = try db.queryScalar("SELECT count(*) FROM child")
        #expect(childCount == 0)
    }

    @Test("Execute returns affected row count")
    func executeReturnsChanges() throws {
        let db = try makeTempDB()
        try db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try db.execute("INSERT INTO t (name) VALUES ('a')")
        try db.execute("INSERT INTO t (name) VALUES ('b')")
        try db.execute("INSERT INTO t (name) VALUES ('c')")

        let deleted = try db.execute("DELETE FROM t WHERE id <= 2")
        #expect(deleted == 2)
    }

    @Test("SQLiteValue convenience accessors")
    func valueAccessors() throws {
        #expect(SQLiteValue.integer(42).intValue == 42)
        #expect(SQLiteValue.real(3.14).doubleValue == 3.14)
        #expect(SQLiteValue.text("hello").textValue == "hello")
        #expect(SQLiteValue.blob(Data([1])).blobValue == Data([1]))
        #expect(SQLiteValue.null.isNull == true)
        #expect(SQLiteValue.integer(42).isNull == false)
        #expect(SQLiteValue.integer(42).textValue == nil)
    }

    @Test("Optional value constructors")
    func optionalConstructors() throws {
        #expect(SQLiteValue.optionalText("hello") == .text("hello"))
        #expect(SQLiteValue.optionalText(nil) == .null)
        #expect(SQLiteValue.optionalInteger(42) == .integer(42))
        #expect(SQLiteValue.optionalInteger(nil) == .null)
    }

    @Test("Error on closed database")
    func errorOnClosed() throws {
        let db = try makeTempDB()
        db.close()

        #expect(throws: SQLiteError.self) {
            try db.execute("SELECT 1")
        }
    }
}
