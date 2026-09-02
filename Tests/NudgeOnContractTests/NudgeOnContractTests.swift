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
