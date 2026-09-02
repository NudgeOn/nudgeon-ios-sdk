import XCTest
@testable import NudgeOnSDK

/// 서버 수집 스키마(nudgeon-platform apps/api/src/ingestion/schemas.ts)의 Swift 미러.
/// trackBodySchema / trackEventSchema / deviceSchema의 규칙을 그대로 옮겨 SDK 페이로드를 검증한다.
/// 스키마가 바뀌면 이 미러도 함께 갱신한다 (감사 SDK-AUDIT-2026-08-31 "iOS NSE 도달 이벤트" 400 재발 방지).
enum ServerTrackSchema {
    static func isUUID(_ v: Any?) -> Bool { (v as? String).flatMap { UUID(uuidString: $0) } != nil }

    /// z.string().datetime({ offset: true }) — ISO 8601, 'Z' 또는 ±hh:mm 오프셋 필수.
    static func isDatetime(_ v: Any?) -> Bool {
        guard let s = v as? String else { return false }
        let re = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#
        return s.range(of: re, options: .regularExpression) != nil
    }

    static func validateDevice(_ d: [String: Any]) -> [String] {
        var errs: [String] = []
        let allowed: Set<String> = ["device_id", "platform", "app_version", "os_version", "model", "locale"]
        for k in d.keys where !allowed.contains(k) { errs.append("device.\(k): strict 위반") }
        if !isUUID(d["device_id"]) { errs.append("device.device_id: uuid 아님") }
        if !["ios", "android"].contains(d["platform"] as? String ?? "") { errs.append("device.platform: enum 위반") }
        return errs
    }

    static func validateEvent(_ e: [String: Any]) -> [String] {
        var errs: [String] = []
        let allowed: Set<String> = ["insert_id", "anon_id", "external_id", "event", "properties", "client_ts"]
        for k in e.keys where !allowed.contains(k) { errs.append("\(k): strict 위반") }
        if !isUUID(e["insert_id"]) { errs.append("insert_id: uuid 아님") }
        var hasAnon = false, hasExt = false
        if let a = e["anon_id"], !(a is NSNull) {
            if !isUUID(a) { errs.append("anon_id: uuid 아님 (\(a))") } else { hasAnon = true }
        }
        if let x = e["external_id"], !(x is NSNull) {
            if let s = x as? String, (1...256).contains(s.count) { hasExt = true }
            else { errs.append("external_id: 1~256자 아님") }
        }
        if !(hasAnon || hasExt) { errs.append("anon_id 또는 external_id 중 하나는 필수입니다") }
        if let ev = e["event"] as? String, (1...128).contains(ev.count) {} else { errs.append("event: 1~128자 아님") }
        if let p = e["properties"], !(p is [String: Any]) { errs.append("properties: record 아님") }
        if !isDatetime(e["client_ts"]) { errs.append("client_ts: datetime(offset) 아님") }
        return errs
    }

    static func validateBody(_ b: [String: Any]) -> [String] {
        var errs: [String] = []
        for k in b.keys where !["batch", "device"].contains(k) { errs.append("\(k): strict 위반") }
        guard let batch = b["batch"] as? [[String: Any]], (1...100).contains(batch.count) else {
            return errs + ["batch: 1~100건 아님"]
        }
        for (i, e) in batch.enumerated() { errs += validateEvent(e).map { "batch[\(i)].\($0)" } }
        if let d = b["device"] as? [String: Any] { errs += validateDevice(d) }
        return errs
    }
}

final class NudgeOnDeliveryTests: XCTestCase {
    private let deviceId = UUID().uuidString.lowercased()
    private let anonId = UUID().uuidString.lowercased()

    private func resolved(anon: String?, ext: String?, device: String? = nil) -> SharedConfig.Resolved {
        SharedConfig.Resolved(sdkKey: "pk_test", apiHost: URL(string: "https://ingest.example.com")!,
                              deviceId: device ?? deviceId, anonId: anon, externalId: ext)
    }

    /// 실제 전송 경로와 동일하게 직렬화된 본문을 서버 스키마 미러로 검증.
    private func body(for item: EventQueue.Item, device: String? = nil) -> [String: Any] {
        let config = NudgeOnConfig(sdkKey: "pk_test", apiHost: URL(string: "https://ingest.example.com")!)
        return Network(config: config, deviceId: device ?? deviceId).trackBody([item])
    }

    func testAnonOnlyPayloadSatisfiesServerSchema() throws {
        let item = try XCTUnwrap(NudgeOnDelivery.buildEvent(messageId: "m-1", resolved: resolved(anon: anonId, ext: nil), now: Date()))
        let b = body(for: item)
        XCTAssertEqual(ServerTrackSchema.validateBody(b), [], "anon_id(UUID)만으로 스키마 충족")
        let e = (b["batch"] as! [[String: Any]])[0]
        XCTAssertEqual(e["anon_id"] as? String, anonId)
        XCTAssertNil(e["external_id"])
        XCTAssertEqual(e["event"] as? String, "$push_delivered")
        XCTAssertEqual((e["properties"] as? [String: Any])?["message_id"] as? String, "m-1")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(b), "URLSession 전송 가능한 JSON")
    }

    func testIdentifiedPayloadCarriesExternalId() throws {
        let item = try XCTUnwrap(NudgeOnDelivery.buildEvent(messageId: "m-2", resolved: resolved(anon: anonId, ext: "user-123"), now: Date()))
        let b = body(for: item)
        XCTAssertEqual(ServerTrackSchema.validateBody(b), [])
        let e = (b["batch"] as! [[String: Any]])[0]
        XCTAssertEqual(e["external_id"] as? String, "user-123", "identify된 유저에게 도달 귀속")
        XCTAssertEqual(e["anon_id"] as? String, anonId)
    }

    func testExternalOnlyPayloadOmitsAnonKey() throws {
        // 구버전 코어(식별자 미러링 이전)와 공존 등으로 anon_id가 없어도 external_id만으로 유효해야 한다.
        let item = try XCTUnwrap(NudgeOnDelivery.buildEvent(messageId: "m-3", resolved: resolved(anon: nil, ext: "user-1"), now: Date()))
        let b = body(for: item)
        XCTAssertEqual(ServerTrackSchema.validateBody(b), [])
        let e = (b["batch"] as! [[String: Any]])[0]
        XCTAssertNil(e["anon_id"], "빈 anon_id는 키 자체를 생략 (strict uuid)")
    }

    /// 감사 결함 재현: anon_id "" + external_id 없음 → 과거엔 그대로 전송되어 400. 이제 이벤트를 만들지 않는다.
    func testEmptyAnonAndNoExternalIsSkipped() {
        XCTAssertNil(NudgeOnDelivery.buildEvent(messageId: "m-4", resolved: resolved(anon: "", ext: nil), now: Date()),
                     "빈 anon_id·external_id 없음 → 전송 건너뜀 (400 예방)")
        XCTAssertNil(NudgeOnDelivery.buildEvent(messageId: "m-4", resolved: resolved(anon: nil, ext: nil), now: Date()),
                     "식별자 미러링 없음 → 전송 건너뜀")
        XCTAssertNil(NudgeOnDelivery.buildEvent(messageId: "m-4", resolved: resolved(anon: "not-a-uuid", ext: ""), now: Date()),
                     "UUID 아닌 anon_id·빈 external_id → 전송 건너뜀")
    }

    func testInvalidDeviceIdIsSkipped() {
        XCTAssertNil(NudgeOnDelivery.buildEvent(messageId: "m-5", resolved: resolved(anon: anonId, ext: nil, device: "dev-1"), now: Date()),
                     "device.device_id는 UUID 필수")
    }

    /// 빈 anon_id를 가진 레거시 큐 아이템도 직렬화 시 anon_id 키를 내보내지 않는다.
    func testTrackBodyOmitsEmptyAnonIdForLegacyItems() {
        let item = EventQueue.Item(insertId: UUID().uuidString.lowercased(), event: "e", properties: [:],
                                   clientTs: "2026-09-02T00:00:00Z", anonId: "", externalId: "u")
        let e = (body(for: item)["batch"] as! [[String: Any]])[0]
        XCTAssertNil(e["anon_id"])
        XCTAssertEqual(ServerTrackSchema.validateEvent(e), [])
    }

    func testSharedConfigRoundTripsIdentityAndClearsOnReset() throws {
        let group = "nudgeon.test.group.\(UUID().uuidString)"
        let config = NudgeOnConfig(sdkKey: "pk_test", apiHost: URL(string: "https://ingest.example.com")!, appGroup: group)
        SharedConfig.mirror(config: config, deviceId: deviceId, anonId: anonId, externalId: nil)
        var r = try XCTUnwrap(SharedConfig.resolve(appGroup: group))
        XCTAssertEqual(r.anonId, anonId); XCTAssertNil(r.externalId); XCTAssertEqual(r.deviceId, deviceId)

        SharedConfig.mirrorIdentity(appGroup: group, anonId: anonId, externalId: "user-9") // identify
        r = try XCTUnwrap(SharedConfig.resolve(appGroup: group))
        XCTAssertEqual(r.externalId, "user-9")

        let newAnon = UUID().uuidString.lowercased()
        SharedConfig.mirrorIdentity(appGroup: group, anonId: newAnon, externalId: nil) // reset
        r = try XCTUnwrap(SharedConfig.resolve(appGroup: group))
        XCTAssertEqual(r.anonId, newAnon)
        XCTAssertNil(r.externalId, "reset 후 이전 유저 external_id가 NSE에 남지 않음")

        // 미러링된 값으로 만든 도달 이벤트가 스키마를 통과.
        let item = try XCTUnwrap(NudgeOnDelivery.buildEvent(messageId: "m-6", resolved: r, now: Date()))
        XCTAssertEqual(ServerTrackSchema.validateBody(body(for: item)), [])
        UserDefaults.standard.removePersistentDomain(forName: group)
    }

    /// 스키마 미러 자체의 자기검증 — 결함 페이로드(감사 재현)를 실제로 거절하는지.
    func testSchemaMirrorRejectsAuditDefectPayload() {
        let defect: [String: Any] = [
            "batch": [[
                "insert_id": UUID().uuidString.lowercased(), "anon_id": "", "event": "$push_delivered",
                "client_ts": "2026-08-31T00:00:00Z", "properties": ["message_id": "m"],
            ]],
            "device": ["device_id": deviceId, "platform": "ios"],
        ]
        let errs = ServerTrackSchema.validateBody(defect)
        XCTAssertTrue(errs.contains { $0.contains("anon_id: uuid 아님") }, "\(errs)")
        XCTAssertTrue(errs.contains { $0.contains("중 하나는 필수") }, "\(errs)")
    }
}
