import XCTest
@testable import NudgeOnSDK

/// 계약 테스트 (PRD-01A 8장 DoD, DEV-sub-05 S-10).
/// 공용 시나리오(contract-tests/scenarios/*.json)를 로드해 공개 코어 → 실제 HTTP → 목 서버
/// 수신 페이로드를 블랙박스로 검증한다. iOS 러너 — 타 플랫폼 러너는 같은 JSON을 공유한다.
final class NudgeOnContractTests: XCTestCase {

    func testAllContractScenarios() throws {
        let scenarios = Scenario.loadAll()
        XCTAssertFalse(scenarios.isEmpty, "contract-tests/scenarios 로드 실패")
        for scenario in scenarios {
            try runScenario(scenario)
        }
    }

    func testStandardEventsUseExistingTrackTransport() throws {
        let names = [
            NudgeOnEvents.signUp,
            NudgeOnEvents.login,
            NudgeOnEvents.purchaseCompleted,
            NudgeOnEvents.productViewed,
            NudgeOnEvents.addToCart,
            NudgeOnEvents.checkoutStarted,
            "purchase", // Existing custom names must not be normalized.
        ]
        let expectedNames = ["sign_up", "login", "purchase_completed", "product_viewed", "add_to_cart", "checkout_started", "purchase"]
        var steps: [[String: Any]] = names.map { name in
            ["call": "track", "args": ["name": name, "properties": [
                "order_id": "order-123", "total_amount": 29000, "currency": "KRW", "item_count": 1
            ]]]
        }
        steps.append(["call": "flush"])
        var asserts: [[String: Any]] = []
        for (index, name) in expectedNames.enumerated() {
            asserts.append(["pointer": "batch.\(index).event", "equals": name])
            asserts.append(["pointer": "batch.\(index).properties.total_amount", "equals": 29000])
            asserts.append(["pointer": "batch.\(index).properties.currency", "equals": "KRW"])
        }
        let scenario = try XCTUnwrap(Scenario(json: [
            "name": "standard_events", "config": ["autoTrackSessions": false, "flushBatchSize": 100],
            "steps": steps, "expect": [["path": "/v1/track", "asserts": asserts]],
        ]))
        try runScenario(scenario)
    }

    func testStandardAttributesUseIdentifyTransport() throws {
        let attrs: [String: Any] = [
            NudgeOnAttributes.firstName: "Minji",
            NudgeOnAttributes.lastName: "Kim",
            NudgeOnAttributes.email: "minji@example.com",
            NudgeOnAttributes.phone: "+821012345678",
            NudgeOnAttributes.dateOfBirth: "1995-03-15",
            NudgeOnAttributes.gender: "F",
            NudgeOnAttributes.homeCity: "Seoul",
            NudgeOnAttributes.country: "KR",
            NudgeOnAttributes.language: "ko",
            NudgeOnAttributes.timezone: "Asia/Seoul",
            NudgeOnAttributes.createdAt: "2026-09-22T00:00:00Z",
            "score": 0, "enabled": false, "interests": ["music"], "removed": NSNull()
        ]
        let expected: [String: Any] = [
            "first_name": "Minji",
            "last_name": "Kim",
            "email": "minji@example.com",
            "phone": "+821012345678",
            "dob": "1995-03-15",
            "gender": "F",
            "home_city": "Seoul",
            "country": "KR",
            "language": "ko",
            "timezone": "Asia/Seoul",
            "created_at": "2026-09-22T00:00:00Z",
            "score": 0, "enabled": false, "interests": ["music"], "removed": NSNull()
        ]
        let scenario = try XCTUnwrap(Scenario(json: [
            "name": "standard_attributes", "config": ["autoTrackSessions": false],
            "steps": [
                ["call": "identify", "args": ["externalId": "profile-123"]],
                ["call": "setUserAttributes", "args": ["attrs": attrs]],
            ],
            "expect": [
                ["path": "/v1/identify", "asserts": [["pointer": "attributes", "equals": [:]]]],
                ["path": "/v1/identify", "asserts": [
                    ["pointer": "external_id", "equals": "profile-123"],
                    ["pointer": "attributes", "equals": expected],
                ]],
            ],
        ]))
        try runScenario(scenario)
    }

    private func runScenario(_ s: Scenario) throws {
        let server = try MockIngestServer()
        defer { server.stop() }

        let expectedCount = s.expect.count
        let done = expectation(description: s.name)
        let counter = Counter()
        let port = try server.start {
            if counter.increment() >= expectedCount { done.fulfill() }
        }
        if expectedCount == 0 { done.fulfill() }

        let host = URL(string: "http://127.0.0.1:\(port)")!
        let core = ContractRunner.buildCore(config: s.config, apiHost: host)
        for step in s.steps { ContractRunner.run(step: step, on: core) }

        wait(for: [done], timeout: 10)

        // 순서 무관 매칭 — 각 기대를 서로 다른 수신 요청에 배정.
        var remaining = server.recorded
        for exp in s.expect {
            guard let idx = remaining.firstIndex(where: { JSONMatch.matches(exp, $0) }) else {
                XCTFail("[\(s.name)] 기대 요청 미수신: \(exp.path) asserts=\(exp.asserts.map { $0.pointer })")
                continue
            }
            remaining.remove(at: idx)
        }
        XCTAssertEqual(remaining.count, 0, "[\(s.name)] 예상외 추가 요청: \(remaining.map { $0.path })")
    }
}

/// 스레드 안전 카운터 (목 서버 콜백은 백그라운드 큐에서 호출).
private final class Counter {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
