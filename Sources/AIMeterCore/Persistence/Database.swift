import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A minimal SQLite wrapper with explicit, ordered migrations.
///
/// SQLite is used directly rather than through a package dependency: the spec
/// asks for predictable migrations and explicit SQL, and prefers system
/// frameworks over new dependencies.
public actor Database {
    public enum DatabaseError: Error, Sendable {
        case open(String)
        case prepare(String)
        case step(String)
    }

    /// One bound parameter. Keeping this typed is what stops SQL string-building.
    public enum Value: Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
    }

    /// Owns the raw connection so it is closed exactly once, when the actor goes
    /// away, without an actor-isolated deinit touching C state.
    private final class Connection: @unchecked Sendable {
        let pointer: OpaquePointer

        init(pointer: OpaquePointer) {
            self.pointer = pointer
        }

        deinit {
            sqlite3_close_v2(pointer)
        }
    }

    private let connection: Connection
    private var handle: OpaquePointer { connection.pointer }
    public let url: URL

    public init(url: URL) throws {
        self.url = url

        if url.path != ":memory:" {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            throw DatabaseError.open(url.path)
        }
        connection = Connection(pointer: pointer)
    }

    /// In-memory database for tests.
    public static func inMemory() throws -> Database {
        try Database(url: URL(fileURLWithPath: ":memory:"))
    }

    public func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw DatabaseError.step(message)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ parameters: [Value] = []) throws -> Int64 {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw DatabaseError.step(String(cString: sqlite3_errmsg(handle)))
        }
        return sqlite3_last_insert_rowid(handle)
    }

    /// Runs a query and maps each row through `decode`.
    public func query<T: Sendable>(
        _ sql: String,
        _ parameters: [Value] = [],
        decode: (Row) throws -> T
    ) throws -> [T] {
        let statement = try prepare(sql, parameters)
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(try decode(Row(statement: statement)))
        }
        return rows
    }

    public func transaction<T: Sendable>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ parameters: [Value]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepare(String(cString: sqlite3_errmsg(handle)))
        }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            switch parameter {
            case .null:
                sqlite3_bind_null(statement, index)
            case .integer(let value):
                sqlite3_bind_int64(statement, index, value)
            case .real(let value):
                sqlite3_bind_double(statement, index, value)
            case .text(let value):
                sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            }
        }

        return statement
    }

    /// Column accessors for one result row.
    public struct Row {
        let statement: OpaquePointer?

        public func int(_ index: Int32) -> Int64? {
            sqlite3_column_type(statement, index) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, index)
        }

        public func double(_ index: Int32) -> Double? {
            sqlite3_column_type(statement, index) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, index)
        }

        public func string(_ index: Int32) -> String? {
            guard let pointer = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: pointer)
        }

        public func date(_ index: Int32) -> Date? {
            double(index).map(Date.init(timeIntervalSince1970:))
        }

        public func decimal(_ index: Int32) -> Decimal? {
            string(index).flatMap { Decimal(string: $0) }
        }
    }
}
