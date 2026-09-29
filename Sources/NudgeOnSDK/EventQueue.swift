import Foundation
import CoreFoundation
import SQLite3

/// SQLite-backed FIFO. Rows are removed only after successful delivery (or oldest-drop at 1000).
/// The legacy JSON file is imported transactionally once; its deletion is only best-effort cleanup.
final class EventQueue {
    struct Item: Codable {
        let insertId: String
        let event: String
        let properties: [String: AnyCodable]
        let clientTs: String
        let anonId: String
        let externalId: String?
    }

    private let maxItems = 1000
    private let legacyURL: URL
    private let databaseURL: URL
    private let lock = DispatchQueue(label: "io.nudgeon.eventqueue")
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(fileName: String = "nudgeon_events.json", directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        legacyURL = dir.appendingPathComponent(fileName)
        databaseURL = legacyURL.deletingPathExtension().appendingPathExtension("sqlite")
        // Open lazily: initialization/JSON migration runs on the SDK worker, not the app's main thread.
    }

    deinit { if let database { sqlite3_close(database) } }

    @discardableResult
    func enqueue(_ item: Item) -> Bool {
        perform(fallback: false) {
            try transaction {
                try insert(item)
                try trim()
            }
            return true
        }
    }

    /// Peek never deletes; failed network attempts can send exactly the same insert_id again.
    func peek(_ batchSize: Int) -> [Item] {
        guard batchSize > 0 else { return [] }
        return perform(fallback: []) {
            let statement = try prepare("SELECT payload FROM events ORDER BY sequence LIMIT ?")
            defer { sqlite3_finalize(statement) }
            try check(sqlite3_bind_int64(statement, 1, Int64(batchSize)))
            var items: [Item] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                try check(result, expected: SQLITE_ROW)
                guard let bytes = sqlite3_column_blob(statement, 0) else { throw StorageError.invalidPayload }
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
                items.append(try JSONDecoder().decode(Item.self, from: data))
            }
            return items
        }
    }

    @discardableResult
    func ack(_ insertIds: Set<String>) -> Bool {
        guard !insertIds.isEmpty else { return true }
        return perform(fallback: false) {
            try transaction {
                let statement = try prepare("DELETE FROM events WHERE insert_id = ?")
                defer { sqlite3_finalize(statement) }
                for id in insertIds {
                    try check(sqlite3_reset(statement))
                    try bind(id, to: statement, at: 1)
                    try check(sqlite3_step(statement), expected: SQLITE_DONE)
                }
            }
            return true
        }
    }

    var count: Int {
        perform(fallback: 0) { try scalar("SELECT count(*) FROM events") }
    }

    private func perform<T>(fallback: T, _ body: () throws -> T) -> T {
        lock.sync {
            do {
                try openIfNeeded()
                return try body()
            } catch {
                // Never delete/recreate a failed DB or log customer payloads. A later call can retry.
                NudgeOnLog.warn("Event queue storage operation failed; persisted data retained")
                return fallback
            }
        }
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            throw StorageError.sqlite(result)
        }
        database = handle
        do {
            try check(sqlite3_busy_timeout(database, 5000))
            try execute("PRAGMA synchronous = FULL")
            try transaction {
                guard try scalar("PRAGMA user_version") <= 1 else { throw StorageError.unsupportedVersion }
                try execute("CREATE TABLE IF NOT EXISTS events (sequence INTEGER PRIMARY KEY AUTOINCREMENT, insert_id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL)")
                try execute("CREATE TABLE IF NOT EXISTS queue_metadata (key TEXT PRIMARY KEY NOT NULL)")
                if try scalar("SELECT count(*) FROM queue_metadata WHERE key = 'legacy_json_imported'") == 0 {
                    if FileManager.default.fileExists(atPath: legacyURL.path) {
                        let data = try Data(contentsOf: legacyURL)
                        let items = try JSONDecoder().decode([Item].self, from: data)
                        for item in items { try insert(item) }
                    }
                    try trim()
                    try execute("INSERT INTO queue_metadata (key) VALUES ('legacy_json_imported')")
                }
                try execute("PRAGMA user_version = 1")
            }
            // A committed marker prevents replay even if deletion fails or the app dies here.
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.removeItem(at: legacyURL)
            }
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    private func insert(_ item: Item) throws {
        let data = try JSONEncoder().encode(item)
        let statement = try prepare("INSERT OR IGNORE INTO events (insert_id, payload) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        try bind(item.insertId, to: statement, at: 1)
        try data.withUnsafeBytes { buffer in
            try check(sqlite3_bind_blob(statement, 2, buffer.baseAddress, Int32(buffer.count), transient))
        }
        try check(sqlite3_step(statement), expected: SQLITE_DONE)
    }

    private func trim() throws {
        try execute("DELETE FROM events WHERE sequence NOT IN (SELECT sequence FROM events ORDER BY sequence DESC LIMIT \(maxItems))")
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func scalar(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_step(statement), expected: SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
        guard let statement else { throw StorageError.invalidPayload }
        return statement
    }

    private func execute(_ sql: String) throws { try check(sqlite3_exec(database, sql, nil, nil, nil)) }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        try value.withCString { pointer in
            try check(sqlite3_bind_text(statement, index, pointer, Int32(value.utf8.count), transient))
        }
    }

    private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
        if result != expected { throw StorageError.sqlite(result) }
    }

    private enum StorageError: Error { case sqlite(Int32), invalidPayload, unsupportedVersion }
}

/// Recursive JSON value wrapper: persistence must retain nested objects, arrays, booleans and null.
public struct AnyCodable: Codable {
    let value: Any
    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode(Int64.self) { value = v }
        else if let v = try? c.decode(UInt64.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([AnyCodable].self) { value = v.map(\.value) }
        else { value = try c.decode([String: AnyCodable].self).mapValues(\.value) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let v as NSNumber:
            // JSONSerialization/bridges use NSNumber: NSNumber(1) also casts to Bool in Swift.
            if CFGetTypeID(v) == CFBooleanGetTypeID() { try c.encode(v.boolValue) }
            else if ["f", "d"].contains(String(cString: v.objCType)) { try c.encode(v.doubleValue) }
            else if String(cString: v.objCType) == "Q" { try c.encode(v.uint64Value) }
            else { try c.encode(v.int64Value) }
        case let v as String: try c.encode(v)
        case let v as [Any]: try c.encode(v.map(AnyCodable.init))
        case let v as [String: Any]: try c.encode(v.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Not a JSON value"))
        }
    }
}
