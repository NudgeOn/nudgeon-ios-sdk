import XCTest
@testable import NudgeOnSDK

/// 같은 message_id 재수신 접기 (플랫폼 M-4: 서버 at-least-once 창에서 같은 메시지가 한 번 더 온다).
final class SeenMessagesTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "nudgeon.seen.test.\(UUID().uuidString)")! }

    func testSecondDeliveryIsNotFirstTime() {
        let seen = SeenMessages(defaults: defaults())
        XCTAssertTrue(seen.firstTime("m-1"))
        XCTAssertFalse(seen.firstTime("m-1"))
        XCTAssertTrue(seen.firstTime("m-2"))
    }

    func testRememberedAcrossInstances() {
        let d = defaults()
        XCTAssertTrue(SeenMessages(defaults: d).firstTime("m-1"))
        XCTAssertFalse(SeenMessages(defaults: d).firstTime("m-1"), "앱 재시작 후에도 접는다")
    }

    func testCapacityEvictsOldest() {
        let d = defaults()
        let seen = SeenMessages(defaults: d, capacity: 3)
        for i in 1...4 { _ = seen.firstTime("m-\(i)") }
        XCTAssertEqual(d.stringArray(forKey: "nudgeon.push.seen_message_ids"), ["m-2", "m-3", "m-4"])
        XCTAssertTrue(seen.firstTime("m-1"), "밀려난 것은 다시 처음으로 본다")
    }

    func testCoreDropsDuplicateReceiptButNotOpen() {
        let d = defaults()
        var cfg = NudgeOnConfig(sdkKey: "pk", apiHost: URL(string: "https://ingest.example.com")!)
        cfg.autoTrackSessions = false
        let identity = Identity(defaults: d)
        let network = Network(config: cfg, deviceId: identity.deviceId)
        let core = NudgeOnCore(config: cfg, identity: identity, queue: EventQueue(fileName: "seen_\(UUID().uuidString).json"),
                               network: network, push: PushManager(config: cfg, network: network, defaults: d),
                               bus: EventBus(deliver: { $0() }), seen: SeenMessages(defaults: d))
        var received = 0, opened = 0
        _ = core.bus.onPushReceived { _ in received += 1 }
        _ = core.bus.onPushOpened { _ in opened += 1 }
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": "hi"], "nudgeon": ["message_id": "m-dup"]]
        XCTAssertTrue(core.handleRemoteNotification(userInfo, opened: false))
        XCTAssertTrue(core.handleRemoteNotification(userInfo, opened: false), "중복도 NudgeOn 메시지로 소비(true)")
        XCTAssertTrue(core.handleRemoteNotification(userInfo, opened: true))
        XCTAssertEqual(received, 1, "두 번째 수신은 리스너에 가지 않는다")
        XCTAssertEqual(opened, 1, "탭은 접지 않는다")
    }
}
