import Foundation
import SQLite3

/// A small wrapper around the SQLite C API. Not thread-safe: confine each instance to one actor
/// (``ReceiptRepository`` owns the app's connection).
final class SQLiteDatabase {
    enum Value: Equatable {
        case integer(Int64)
        case text(String)
        case null
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func int(_ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }
        func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    }

    struct Error: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let handle: OpaquePointer

    /// Opens (creating if needed) the database at `path`; pass ":memory:" for a throwaway database.
    init(path: String) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "error \(result)"
            sqlite3_close(handle)
            throw Error(message: "Could not open database: \(message)")
        }
        self.handle = handle
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements that take no parameters.
    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(errorMessage)
            throw Error(message: message)
        }
    }

    /// Runs a single statement and returns the rowid of the last inserted row.
    @discardableResult
    func run(_ sql: String, _ bindings: [Value] = []) throws -> Int64 {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw Error(message: lastErrorMessage) }
        return sqlite3_last_insert_rowid(handle)
    }

    func query<T>(_ sql: String, _ bindings: [Value] = [], map: (Row) throws -> T) throws -> [T] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var rows: [T] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw Error(message: lastErrorMessage) }
            rows.append(try map(Row(statement: statement)))
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT TRANSACTION")
        } catch {
            try? execute("ROLLBACK TRANSACTION")
            throw error
        }
    }

    var userVersion: Int {
        get throws { try query("PRAGMA user_version") { $0.int(0) }.first ?? 0 }
    }

    private func prepare(_ sql: String, _ bindings: [Value]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Error(message: lastErrorMessage)
        }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result = switch value {
            case .integer(let integer): sqlite3_bind_int64(statement, position, integer)
            // SQLITE_TRANSIENT: SQLite copies the string before this call returns.
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .null: sqlite3_bind_null(statement, position)
            }
            guard result == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw Error(message: lastErrorMessage)
            }
        }
        return statement
    }

    private var lastErrorMessage: String { String(cString: sqlite3_errmsg(handle)) }
}
