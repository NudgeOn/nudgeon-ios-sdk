import Foundation

/// anon_id / external_id / device_id 영속화 (PRD-01 3.1).
/// 코어가 유일한 상태 보유자 — UserDefaults에 영속.
final class Identity {
    private let defaults: UserDefaults
    private let anonKey = "nudgeon.anon_id"
    private let deviceKey = "nudgeon.device_id"
    private let externalKey = "nudgeon.external_id"
    private let pendingIdentifyExternalKey = "nudgeon.identify_pending.external_id"
    private let pendingIdentifyAnonKey = "nudgeon.identify_pending.anon_id"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 최초 실행 시 anon_id(UUID) 발급·영속. 이후 동일 값 반환.
    var anonId: String {
        if let v = defaults.string(forKey: anonKey) { return v }
        let v = UUID().uuidString.lowercased()
        defaults.set(v, forKey: anonKey)
        return v
    }

    /// 디바이스 식별자 — 설치 단위 불변 (재설치 시 새로 발급).
    var deviceId: String {
        if let v = defaults.string(forKey: deviceKey) { return v }
        let v = UUID().uuidString.lowercased()
        defaults.set(v, forKey: deviceKey)
        return v
    }

    var externalId: String? {
        get { defaults.string(forKey: externalKey) }
        set { defaults.set(newValue, forKey: externalKey) }
    }

    /// 서버에 아직 반영되지 않은 identify (external_id, 당시 anon_id). 앱 재시작 후에도 재시도한다.
    /// M-1 실단말(09-07)에서 identify 실패가 조용히 유실돼 서버가 대신 identify해야 했던 결함의 수정.
    var pendingIdentify: (externalId: String, anonId: String)? {
        guard let ext = defaults.string(forKey: pendingIdentifyExternalKey),
              let anon = defaults.string(forKey: pendingIdentifyAnonKey) else { return nil }
        return (ext, anon)
    }

    func markIdentifyPending(externalId: String, anonId: String) {
        defaults.set(externalId, forKey: pendingIdentifyExternalKey)
        defaults.set(anonId, forKey: pendingIdentifyAnonKey)
    }

    /// 전송 성공분이 현재 대기분과 같을 때만 지운다 — 전송 중 다른 identify가 들어왔으면 그쪽이 남는다.
    func clearIdentifyPending(externalId: String, anonId: String) {
        guard let p = pendingIdentify, p.externalId == externalId, p.anonId == anonId else { return }
        defaults.removeObject(forKey: pendingIdentifyExternalKey)
        defaults.removeObject(forKey: pendingIdentifyAnonKey)
    }

    /// reset() — 로그아웃. 디바이스를 현재 유저에서 분리하고 새 anon_id 발급 (PRD-01 3.1).
    /// device_id는 유지(설치 단위). 이전 유저에게 다음 유저 푸시가 가는 사고 방지.
    /// 이전 유저의 미전송 identify도 버린다(코어가 reset 직전에 마지막 1회 전송을 시도한다) —
    /// 로그아웃 뒤에는 재시도하지 않아 이전 anon이 그 유저에 새로 묶이지 않는다.
    func reset() {
        defaults.removeObject(forKey: externalKey)
        defaults.removeObject(forKey: pendingIdentifyExternalKey)
        defaults.removeObject(forKey: pendingIdentifyAnonKey)
        defaults.set(UUID().uuidString.lowercased(), forKey: anonKey)
    }
}
