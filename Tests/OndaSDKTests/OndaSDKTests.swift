import XCTest
@testable import OndaSDK

final class IdentityTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "onda.test.\(UUID().uuidString)")!
        return d
    }

    func testAnonIdStableAcrossReads() {
        let id = Identity(defaults: freshDefaults())
        XCTAssertEqual(id.anonId, id.anonId, "anon_id는 최초 발급 후 안정적")
    }

    func testResetIssuesNewAnonIdAndClearsExternal() {
        let id = Identity(defaults: freshDefaults())
        let before = id.anonId
        id.externalId = "user-1"
        id.reset()
        XCTAssertNotEqual(id.anonId, before, "reset 후 새 anon_id")
        XCTAssertNil(id.externalId, "reset 후 external_id 제거")
    }

    func testDeviceIdSurvivesReset() {
        let id = Identity(defaults: freshDefaults())
        let dev = id.deviceId
        id.reset()
        XCTAssertEqual(id.deviceId, dev, "device_id는 설치 단위 — reset에도 유지")
    }
}

final class EventQueueTests: XCTestCase {
    func testEnqueuePeekAck() {
        let q = EventQueue(fileName: "test_\(UUID().uuidString).json")
        let item = EventQueue.Item(insertId: "i1", event: "e", properties: [:],
                                   clientTs: "2026-08-30T00:00:00Z", anonId: "a", externalId: nil)
        q.enqueue(item)
        XCTAssertEqual(q.count, 1)
        let peeked = q.peek(10)
        XCTAssertEqual(peeked.first?.insertId, "i1")
        q.ack(["i1"])
        XCTAssertEqual(q.count, 0, "ack 후 제거")
    }
}
