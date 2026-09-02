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

// MARK: - M2 푸시

final class PushPayloadTests: XCTestCase {
    func testParsesOndaMessageWithAlertDict() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "제목", "body": "본문"]],
            "onda": [
                "message_id": "m-1", "campaign_id": "c-1", "journey_id": "j-1",
                "deep_link": "myapp://x", "data": ["k": "v", "n": 3],
            ],
        ]
        let p = PushPayload.parse(userInfo)
        XCTAssertEqual(p?.messageId, "m-1")
        XCTAssertEqual(p?.campaignId, "c-1")
        XCTAssertEqual(p?.journeyId, "j-1")
        XCTAssertEqual(p?.title, "제목")
        XCTAssertEqual(p?.body, "본문")
        XCTAssertEqual(p?.deepLink, "myapp://x")
        XCTAssertEqual(p?.data["k"], "v")
        XCTAssertEqual(p?.data["n"], "3", "숫자도 문자열로 평탄화")
    }

    func testParsesAlertString() {
        let p = PushPayload.parse(["aps": ["alert": "just text"], "onda": ["message_id": "m"]])
        XCTAssertEqual(p?.body, "just text")
        XCTAssertEqual(p?.title, "")
    }

    func testReturnsNilForNonOndaMessage() {
        // onda.message_id 없음 → 타 SDK 메시지로 간주, nil (공존).
        XCTAssertNil(PushPayload.parse(["aps": ["alert": "hi"]]))
    }
}

final class EventBusTests: XCTestCase {
    private func syncBus() -> EventBus { EventBus(deliver: { $0() }) } // 테스트: 동기 전달

    private func payload(_ id: String) -> PushPayload {
        PushPayload(messageId: id, title: "t", body: "b")
    }

    func testColdStartBufferReplayedOnFirstSubscribe() {
        let bus = syncBus()
        bus.emitOpened(payload("m1")) // 리스너 등록 전 발생 (콜드 스타트)
        var received: [String] = []
        bus.onPushOpened { received.append($0.messageId) }
        XCTAssertEqual(received, ["m1"], "구독 전 이벤트가 첫 등록 시 재생")
    }

    func testInitialPushPayloadAvailableWithoutListener() {
        let bus = syncBus()
        bus.emitOpened(payload("m9"))
        XCTAssertEqual(bus.getInitialPushPayload()?.messageId, "m9", "getInitialPushPayload 경로")
    }

    func testBufferCappedAt20() {
        let bus = syncBus()
        for i in 0..<25 { bus.emitReceived(payload("m\(i)")) }
        var count = 0
        bus.onPushReceived { _ in count += 1 }
        XCTAssertEqual(count, 20, "버퍼 상한 20 — oldest drop")
    }

    func testLiveDeliveryAfterSubscribe() {
        let bus = syncBus()
        var got: String?
        bus.onPushOpened { got = $0.messageId }
        bus.emitOpened(payload("live"))
        XCTAssertEqual(got, "live")
    }

    func testOffStopsDelivery() {
        let bus = syncBus()
        var count = 0
        let token = bus.onPushReceived { _ in count += 1 }
        bus.off(token)
        bus.emitReceived(payload("x"))
        XCTAssertEqual(count, 0, "off 후 미전달")
    }
}

final class PushManagerTests: XCTestCase {
    private func make() -> (PushManager, UserDefaults) {
        let d = UserDefaults(suiteName: "onda.push.test.\(UUID().uuidString)")!
        let cfg = OndaConfig(sdkKey: "pk", apiHost: URL(string: "https://ingest.example.com")!)
        return (PushManager(config: cfg, network: Network(config: cfg, deviceId: "dev"), defaults: d), d)
    }

    func testHexStringConversion() {
        let data = Data([0x00, 0x0a, 0xff, 0x10])
        XCTAssertEqual(PushManager.hexString(from: data), "000aff10")
    }

    func testServiceOptInDefaultsTrueThenPersists() {
        let (pm, _) = make()
        XCTAssertTrue(pm.serviceOptIn, "미설정 시 기본 수신 동의")
        pm.setServiceOptIn(false)
        XCTAssertFalse(pm.serviceOptIn)
    }

    func testTokenReconciliation() {
        let (pm, _) = make()
        XCTAssertTrue(pm.needsRegistration(token: "t1", externalId: nil, osPermission: "authorized"), "최초 등록 필요")
        pm.markRegistered(token: "t1", externalId: nil, osPermission: "authorized")
        XCTAssertFalse(pm.needsRegistration(token: "t1", externalId: nil, osPermission: "authorized"), "동일 토큰/유저/권한 → 생략")
        XCTAssertTrue(pm.needsRegistration(token: "t2", externalId: nil, osPermission: "authorized"), "토큰 변경 → 재등록 (S-5)")
        XCTAssertTrue(pm.needsRegistration(token: "t1", externalId: "user-1", osPermission: "authorized"), "유저 변경 → 재등록 (S-4)")
    }

    /// R-08: 토큰·유저 불변이어도 OS 권한이 바뀌면 재등록 필요 (설정 앱에서 알림 off 등).
    func testPermissionChangeTriggersRegistration() {
        let (pm, _) = make()
        pm.markRegistered(token: "t1", externalId: "user-1", osPermission: "authorized")
        XCTAssertFalse(pm.needsRegistration(token: "t1", externalId: "user-1", osPermission: "authorized"), "권한 동일 → 생략")
        XCTAssertTrue(pm.needsRegistration(token: "t1", externalId: "user-1", osPermission: "denied"),
                      "토큰·유저 불변이나 권한 변경 → 재등록 (R-08)")
        pm.markRegistered(token: "t1", externalId: "user-1", osPermission: "denied")
        XCTAssertFalse(pm.needsRegistration(token: "t1", externalId: "user-1", osPermission: "denied"), "갱신 후 생략")
    }

    func testSubscriptionStateComposition() {
        let (pm, _) = make()
        let s = pm.subscriptionState(osPermission: "authorized")
        XCTAssertTrue(s.serviceOptIn)
        XCTAssertEqual(s.osPermission, "authorized")
        XCTAssertFalse(s.tokenRegistered, "등록 전 false")
        pm.markRegistered(token: "t", externalId: nil, osPermission: "authorized")
        XCTAssertTrue(pm.subscriptionState(osPermission: "authorized").tokenRegistered)
    }
}
