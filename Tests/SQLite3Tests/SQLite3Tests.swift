// SQLite's C API through `import SQLite3`: SwiftUIWeb's amalgamation on Linux and WASI (where
// these run under Node), Apple's on macOS, so the same calls are checked against both.
import Testing
import SQLite3

/// SQLite's `SQLITE_TRANSIENT`: SQLite copies the bytes before the call returns.
private var transient: sqlite3_destructor_type { unsafeBitCast(-1, to: sqlite3_destructor_type.self) }

/// An in-memory database, closed when the test ends.
private final class Database {
    var handle: OpaquePointer?
    init() throws {
        #expect(sqlite3_open(":memory:", &handle) == SQLITE_OK)
        try #require(handle != nil)
    }
    deinit { sqlite3_close(handle) }

    func exec(_ sql: String) -> Int32 { sqlite3_exec(handle, sql, nil, nil, nil) }

    /// The first column of each row `sql` returns, as text.
    func column(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var rows: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return rows
    }
}

@Suite struct SQLite3Tests {
    @Test func reportsAVersion() {
        #expect(sqlite3_libversion_number() >= 3_000_000)
        #expect(String(cString: sqlite3_libversion()).hasPrefix("3."))
    }

    @Test func storesAndReadsRowsWithBoundValues() throws {
        let db = try Database()
        #expect(db.exec("CREATE TABLE notes (id INTEGER PRIMARY KEY, title TEXT, score REAL)") == SQLITE_OK)
        var insert: OpaquePointer?
        try #require(sqlite3_prepare_v2(db.handle, "INSERT INTO notes (title, score) VALUES (?, ?)", -1, &insert, nil) == SQLITE_OK)
        for (title, score) in [("Groceries", 1.5), ("Taxes", 3.25)] {
            sqlite3_bind_text(insert, 1, title, -1, transient)
            sqlite3_bind_double(insert, 2, score)
            #expect(sqlite3_step(insert) == SQLITE_DONE)
            sqlite3_reset(insert)
        }
        sqlite3_finalize(insert)
        #expect(sqlite3_last_insert_rowid(db.handle) == 2)
        #expect(sqlite3_changes(db.handle) == 1)

        var select: OpaquePointer?
        try #require(sqlite3_prepare_v2(db.handle, "SELECT id, title, score FROM notes WHERE score > ? ORDER BY id", -1, &select, nil) == SQLITE_OK)
        sqlite3_bind_double(select, 1, 2)
        #expect(sqlite3_step(select) == SQLITE_ROW)
        #expect(sqlite3_column_int64(select, 0) == 2)
        #expect(String(cString: sqlite3_column_text(select, 1)) == "Taxes")
        #expect(sqlite3_column_double(select, 2) == 3.25)
        #expect(sqlite3_column_type(select, 1) == SQLITE_TEXT)
        #expect(sqlite3_step(select) == SQLITE_DONE)
        sqlite3_finalize(select)
    }

    @Test func reportsErrorsWithMessages() throws {
        let db = try Database()
        #expect(db.exec("SELECT * FROM missing") == SQLITE_ERROR)
        #expect(String(cString: sqlite3_errmsg(db.handle)) == "no such table: missing")
        #expect(db.exec("CREATE TABLE t (k TEXT UNIQUE)") == SQLITE_OK)
        #expect(db.exec("INSERT INTO t VALUES ('a')") == SQLITE_OK)
        #expect(db.exec("INSERT INTO t VALUES ('a')") == SQLITE_CONSTRAINT)
        #expect(sqlite3_extended_errcode(db.handle) == SQLITE_CONSTRAINT_UNIQUE)
    }

    @Test func rollsBackATransaction() throws {
        let db = try Database()
        #expect(db.exec("CREATE TABLE t (n INTEGER)") == SQLITE_OK)
        #expect(db.exec("BEGIN; INSERT INTO t VALUES (1); ROLLBACK") == SQLITE_OK)
        #expect(db.exec("BEGIN; INSERT INTO t VALUES (2); COMMIT") == SQLITE_OK)
        #expect(try db.column("SELECT n FROM t") == ["2"])
    }

    @Test func searchesFullTextAndJSON() throws {
        let db = try Database()
        #expect(db.exec("CREATE VIRTUAL TABLE docs USING fts5(body)") == SQLITE_OK)
        #expect(db.exec("INSERT INTO docs VALUES ('the quick brown fox'), ('lazy dogs sleep')") == SQLITE_OK)
        #expect(try db.column("SELECT body FROM docs WHERE docs MATCH 'quick'") == ["the quick brown fox"])
        #expect(db.exec("CREATE VIRTUAL TABLE old USING fts4(body)") == SQLITE_OK)
        #expect(db.exec("CREATE VIRTUAL TABLE boxes USING rtree(id, minX, maxX)") == SQLITE_OK)
        #expect(try db.column("SELECT json_extract('{\"a\":[1,2,3]}', '$.a[1]')") == ["2"])
    }
}
