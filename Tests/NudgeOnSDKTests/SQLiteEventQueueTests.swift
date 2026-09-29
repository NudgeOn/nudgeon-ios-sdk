import Foundation
import SQLite3
import XCTest
@testable import NudgeOnSDK

final class SQLiteEventQueueTests: XCTestCase {
    private var directory: URL!
    private var legacy: URL { directory.appendingPathComponent("events.json") }
    private var database: URL { directory.appendingPathComponent("events.sqlite") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func queue() -> EventQueue { EventQueue(fileName: "events.json", directory: directory) }
    private func item(_ id: String) -> EventQueue.Item {
        .init(insertId: id, event: "purchase", properties: [:], clientTs: "2026-09-29T00:00:00Z", anonId: "anon", externalId: "user")
    }
    private func writeLegacy(_ items: [EventQueue.Item]) throws { try JSONEncoder().encode(items).write(to: legacy) }
    private func sql(_ query: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, query, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteTest", code: 1, userInfo: nil)
        }
    }

    func testReopenKeepsFIFOIdentityAndOnlyAcknowledgesSelectedRows() throws {
        do {
            let q = queue()
            XCTAssertTrue(q.enqueue(item("first")))
            XCTAssertTrue(q.enqueue(item("second")))
            XCTAssertTrue(q.enqueue(item("third")))
            XCTAssertEqual(q.peek(2).map(\.insertId), ["first", "second"])
            XCTAssertEqual(q.peek(2).map(\.insertId), ["first", "second"], "Peek must not acknowledge")
            XCTAssertTrue(q.ack(["second"]))
        }
        let restored = queue()
        XCTAssertEqual(restored.peek(10).map(\.insertId), ["first", "third"])
        XCTAssertEqual(restored.peek(1).first?.externalId, "user")
        XCTAssertEqual(restored.peek(1).first?.clientTs, "2026-09-29T00:00:00Z")
        XCTAssertTrue(restored.peek(0).isEmpty)
        XCTAssertEqual(try Data(contentsOf: database).prefix(16), Data("SQLite format 3\0".utf8))
    }

    func testNestedJSONSurvivesDiskAndTransport() throws {
        let props: [String: Any] = ["true": true, "false": false, "zero": 0, "one": 1,
            "large": Int64(9_007_199_254_740_993), "nsOne": NSNumber(value: 1), "nsZero": NSNumber(value: 0), "null": NSNull(), "fraction": 1.25,
            "items": [["name": "한글", "quantity": 2], ["flags": [true, false]]],
            "object": ["nested": ["values": [1, "two", NSNull()] as [Any]]]]
        let e = EventQueue.Item(insertId: "nested", event: "e", properties: props.mapValues(AnyCodable.init), clientTs: "t", anonId: "a", externalId: nil)
        XCTAssertTrue(queue().enqueue(e))
        let restored = try XCTUnwrap(queue().peek(1).first)
        let config = NudgeOnConfig(sdkKey: "pk", apiHost: URL(string: "https://example.invalid")!)
        let body = Network(config: config, deviceId: "device").trackBody([restored])
        let batch = try XCTUnwrap(body["batch"] as? [[String: Any]])
        let actual = try JSONSerialization.data(withJSONObject: batch[0]["properties"]!, options: [.sortedKeys])
        XCTAssertEqual(actual, try JSONSerialization.data(withJSONObject: props, options: [.sortedKeys]))
    }

    func testMigrationIsOneTimeEvenWhenLegacyFileReappearsAfterAck() throws {
        try writeLegacy([item("a"), item("b")])
        do {
            let q = queue()
            XCTAssertEqual(q.peek(10).map(\.insertId), ["a", "b"])
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
            XCTAssertTrue(q.ack(["a", "b"]))
        }
        // Simulates failed legacy cleanup, or death between commit and removal.
        try writeLegacy([item("a"), item("b")])
        XCTAssertEqual(queue().count, 0)
    }

    func testMigrationRollsBackAllRowsAndCanRetry() throws {
        try sql("CREATE TABLE events (sequence INTEGER PRIMARY KEY AUTOINCREMENT, insert_id TEXT NOT NULL UNIQUE, payload BLOB NOT NULL); CREATE TRIGGER fail_import BEFORE INSERT ON events WHEN NEW.insert_id = 'bad' BEGIN SELECT RAISE(ABORT, 'injected'); END;")
        try writeLegacy([item("good"), item("bad")])
        let q = queue()
        XCTAssertEqual(q.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        try sql("DROP TRIGGER fail_import")
        XCTAssertEqual(q.peek(10).map(\.insertId), ["good", "bad"])
    }

    func testMalformedLegacyIsPreservedAndCanBeRepaired() throws {
        let invalid = Data("[{broken".utf8)
        try invalid.write(to: legacy)
        let q = queue()
        XCTAssertFalse(q.enqueue(item("new")))
        XCTAssertEqual(try Data(contentsOf: legacy), invalid)
        try writeLegacy([item("old")])
        XCTAssertTrue(q.enqueue(item("new")))
        XCTAssertEqual(q.peek(10).map(\.insertId), ["old", "new"])
    }

    func testCapAndDuplicateInsertRetainFirstPayloadAndFIFO() throws {
        let q = queue()
        for i in 0..<1005 { XCTAssertTrue(q.enqueue(item("e\(i)"))) }
        XCTAssertEqual(q.count, 1000)
        XCTAssertEqual(q.peek(1).first?.insertId, "e5")
        XCTAssertTrue(q.enqueue(item("e5")))
        XCTAssertEqual(q.count, 1000)
        XCTAssertEqual(q.peek(1).first?.insertId, "e5")
    }

    func testWriteAndAckFailurePreservePreviouslyCommittedRows() throws {
        let q = queue()
        XCTAssertTrue(q.enqueue(item("a")))
        XCTAssertTrue(q.enqueue(item("b")))
        try sql("CREATE TRIGGER fail_insert BEFORE INSERT ON events BEGIN SELECT RAISE(ABORT, 'injected'); END; CREATE TRIGGER fail_delete BEFORE DELETE ON events WHEN OLD.insert_id = 'b' BEGIN SELECT RAISE(ABORT, 'injected'); END;")
        XCTAssertFalse(q.enqueue(item("c")))
        XCTAssertFalse(q.ack(["a", "b"]))
        XCTAssertEqual(q.peek(10).map(\.insertId), ["a", "b"])
        try sql("DROP TRIGGER fail_insert; DROP TRIGGER fail_delete")
        XCTAssertTrue(q.ack(["a", "b"]))
        XCTAssertEqual(q.count, 0)
    }

    func testConcurrentConnectionsDoNotOverwriteEachOther() {
        let first = queue()
        let second = queue()
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            XCTAssertTrue((index % 2 == 0 ? first : second).enqueue(item("e\(index)")))
        }
        XCTAssertEqual(queue().count, 100)
        XCTAssertEqual(Set(queue().peek(100).map(\.insertId)).count, 100)
    }

    func testCorruptDatabaseIsNotDeleted() throws {
        let corrupt = Data("not a SQLite database".utf8)
        try corrupt.write(to: database)
        XCTAssertFalse(queue().enqueue(item("e")))
        XCTAssertEqual(try Data(contentsOf: database), corrupt)
    }
}
