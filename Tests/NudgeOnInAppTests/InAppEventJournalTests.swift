import XCTest
@testable import NudgeOnInApp

final class InAppEventJournalTests: XCTestCase {
    func testRestartAcknowledgementAndInstallationIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("events.json")
        let journal = try InAppEventJournal(file: file, owner: "one")
        try journal.append(delivery: "delivery", kind: "presented", detail: "")
        try journal.append(delivery: "delivery", kind: "impression", detail: "")
        let id = journal.events[0].id
        let reopened = try InAppEventJournal(file: file, owner: "one")
        XCTAssertEqual(reopened.events.map(\.kind), ["presented", "impression"])
        XCTAssertEqual(reopened.events[0].id, id)
        try reopened.acknowledge(id)
        XCTAssertEqual(try InAppEventJournal(file: file, owner: "one").events.map(\.kind), ["impression"])
        XCTAssertTrue(try InAppEventJournal(file: file, owner: "two").events.isEmpty)
    }
    func testExpiryAndStorageFailureDoNotAcknowledgeMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("events.json")
        let journal = try InAppEventJournal(file: file, owner: "one")
        try journal.append(delivery: "old", kind: "presented", detail: "", now: Date().addingTimeInterval(-604801))
        XCTAssertTrue(try InAppEventJournal(file: file, owner: "one").events.isEmpty)
        try journal.append(delivery: "new", kind: "dismiss", detail: "")
        let id = journal.events[0].id
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory)
        XCTAssertThrowsError(try journal.acknowledge(id))
        XCTAssertEqual(journal.events.first?.id, id)
    }
}
