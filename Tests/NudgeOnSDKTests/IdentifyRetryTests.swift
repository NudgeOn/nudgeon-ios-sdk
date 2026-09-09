import XCTest
@testable import NudgeOnSDK

/// identify 재시도 (M-1 실단말 결함, 2026-09-07): identify 실패가 로그만 남기고 유실돼 서버가 대신
/// identify해야 했다. 실패분은 영속 마커로 남아 다음 flush·앱 재시작에서 같은 (external_id, anon_id)로 재전송된다.
final class IdentifyRetryTests: XCTestCase {
    /// URLProtocol 스텁 — 경로별 응답 코드를 제어하고 요청 본문을 기록한다.
    final class StubProtocol: URLProtocol {
        static let lock = NSLock()
        static var identifyStatuses: [Int] = [] // 순서대로 소비, 비면 200
        static var identifyBodies: [[String: Any]] = []

        static func reset() {
            lock.lock(); defer { lock.unlock() }
            identifyStatuses = []
            identifyBodies = []
        }
        static func nextStatus() -> Int {
            lock.lock(); defer { lock.unlock() }
            return identifyStatuses.isEmpty ? 200 : identifyStatuses.removeFirst()
        }
        static func record(_ body: [String: Any]) {
            lock.lock(); defer { lock.unlock() }
            identifyBodies.append(body)
        }
        static func bodies() -> [[String: Any]] {
            lock.lock(); defer { lock.unlock() }
            return identifyBodies
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var status = 200
            if request.url?.path == "/v1/identify" {
                status = Self.nextStatus()
                if let stream = request.httpBodyStream {
                    stream.open()
                    var data = Data()
                    let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buf.deallocate() }
                    while stream.hasBytesAvailable {
                        let n = stream.read(buf, maxLength: 4096)
                        if n <= 0 { break }
                        data.append(buf, count: n)
                    }
                    stream.close()
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { Self.record(json) }
                } else if let data = request.httpBody,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    Self.record(json)
                }
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private func makeCore(defaults: UserDefaults) -> (NudgeOnCore, Identity) {
        var cfg = NudgeOnConfig(sdkKey: "pk", apiHost: URL(string: "https://ingest.example.com")!)
        cfg.autoTrackSessions = false
        cfg.flushInterval = 3600 // 타이머가 아니라 명시적 flush()로만 재시도를 유발한다
        let sc = URLSessionConfiguration.ephemeral
        sc.protocolClasses = [StubProtocol.self]
        let identity = Identity(defaults: defaults)
        let network = Network(config: cfg, deviceId: identity.deviceId, session: URLSession(configuration: sc))
        let queue = EventQueue(fileName: "identify_retry_\(UUID().uuidString).json")
        let push = PushManager(config: cfg, network: network, defaults: defaults)
        return (NudgeOnCore(config: cfg, identity: identity, queue: queue, network: network, push: push), identity)
    }

    private func waitIdentifyCount(_ n: Int, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while StubProtocol.bodies().count < n, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    override func setUp() { StubProtocol.reset() }

    func testFailedIdentifyIsRetriedOnNextFlushWithSameIdentity() {
        let defaults = UserDefaults(suiteName: "nudgeon.identify.test.\(UUID().uuidString)")!
        let (core, identity) = makeCore(defaults: defaults)
        StubProtocol.identifyStatuses = [503] // 첫 전송 실패

        core.identify("user-1")
        waitIdentifyCount(1)
        XCTAssertEqual(StubProtocol.bodies().count, 1)
        XCTAssertEqual(identity.pendingIdentify?.externalId, "user-1", "실패분은 pending으로 남는다")
        XCTAssertEqual(identity.externalId, "user-1", "로컬 식별자는 즉시 반영")

        core.flush() // 다음 flush(타이머·포그라운드와 같은 경로)에서 재전송
        waitIdentifyCount(2)
        let bodies = StubProtocol.bodies()
        XCTAssertEqual(bodies.count, 2, "재전송 1회")
        XCTAssertEqual(bodies[1]["external_id"] as? String, "user-1")
        XCTAssertEqual(bodies[1]["anon_id"] as? String, bodies[0]["anon_id"] as? String, "같은 anon_id로 재전송")
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(identity.pendingIdentify, "성공하면 pending 제거")

        core.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(StubProtocol.bodies().count, 2, "성공 후 flush는 identify를 다시 보내지 않는다")
    }

    func testPendingIdentifySurvivesRestart() {
        let suite = "nudgeon.identify.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let (core, _) = makeCore(defaults: defaults)
        StubProtocol.identifyStatuses = [500]
        core.identify("user-2")
        waitIdentifyCount(1)

        // 앱 재시작: 같은 UserDefaults로 새 코어 — start()의 첫 flush가 identify를 이어서 보낸다.
        let (restarted, identity) = makeCore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(identity.pendingIdentify?.externalId, "user-2", "재시작 전 pending이 영속됨")
        restarted.start()
        waitIdentifyCount(2)
        XCTAssertEqual(StubProtocol.bodies().count, 2)
        XCTAssertEqual(StubProtocol.bodies()[1]["external_id"] as? String, "user-2")
    }

    func testResetTriesPendingIdentifyOnceThenDropsIt() {
        let defaults = UserDefaults(suiteName: "nudgeon.identify.test.\(UUID().uuidString)")!
        let (core, identity) = makeCore(defaults: defaults)
        StubProtocol.identifyStatuses = [503, 503] // 최초·reset 직전 마지막 시도 모두 실패
        core.identify("user-3")
        waitIdentifyCount(1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2)) // 실패 완료 대기
        let oldAnon = StubProtocol.bodies()[0]["anon_id"] as? String
        core.reset()
        waitIdentifyCount(2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(StubProtocol.bodies()[1]["external_id"] as? String, "user-3", "reset 직전 마지막 1회 시도")
        XCTAssertEqual(StubProtocol.bodies()[1]["anon_id"] as? String, oldAnon, "이전 anon으로")
        XCTAssertNil(identity.pendingIdentify, "로그아웃 뒤 이전 유저 identify는 버린다")
        XCTAssertNil(identity.externalId)
        core.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(StubProtocol.bodies().count, 2, "reset 뒤 재전송 없음")
    }

    func testIdentifyDuringInflightKeepsNewestPending() {
        let defaults = UserDefaults(suiteName: "nudgeon.identify.test.\(UUID().uuidString)")!
        let (core, identity) = makeCore(defaults: defaults)
        core.identify("user-a")
        core.identify("user-b") // 첫 전송이 끝나기 전에 유저가 바뀜
        waitIdentifyCount(2)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(identity.pendingIdentify, "둘 다 서버에 닿으면 pending 없음")
        XCTAssertEqual(StubProtocol.bodies().last?["external_id"] as? String, "user-b", "마지막 유저가 마지막에 전송")
        XCTAssertEqual(identity.externalId, "user-b")
    }
}
