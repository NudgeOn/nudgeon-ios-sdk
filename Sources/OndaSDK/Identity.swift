import Foundation

/// anon_id / external_id / device_id 영속화 (PRD-01 3.1).
/// 코어가 유일한 상태 보유자 — UserDefaults에 영속.
final class Identity {
    private let defaults: UserDefaults
    private let anonKey = "onda.anon_id"
    private let deviceKey = "onda.device_id"
    private let externalKey = "onda.external_id"

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

    /// reset() — 로그아웃. 디바이스를 현재 유저에서 분리하고 새 anon_id 발급 (PRD-01 3.1).
    /// device_id는 유지(설치 단위). 이전 유저에게 다음 유저 푸시가 가는 사고 방지.
    func reset() {
        defaults.removeObject(forKey: externalKey)
        defaults.set(UUID().uuidString.lowercased(), forKey: anonKey)
    }
}
