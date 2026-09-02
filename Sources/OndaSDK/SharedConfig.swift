import Foundation

/// App Group을 통한 코어 ↔ NSE 설정 공유 (PRD-01A 3.1).
/// NSE는 별도 프로세스라 코어 인스턴스에 접근할 수 없다. 코어가 초기화 시 최소 설정을
/// 공유 UserDefaults에 미러링하고, NSE는 이를 읽어 도달($push_delivered)을 전송한다.
///
/// 식별자(anon_id·external_id)도 함께 미러링한다 — 서버 수집 스키마는 이벤트마다
/// UUID anon_id 또는 external_id 중 하나를 요구하므로, 식별자 없이는 도달 이벤트가 400이 된다.
/// identify/reset으로 식별자가 바뀌면 `mirrorIdentity`로 즉시 갱신한다.
enum SharedConfig {
    static let sdkKeyKey = "onda.shared.sdk_key"
    static let apiHostKey = "onda.shared.api_host"
    static let deviceIdKey = "onda.shared.device_id"
    static let anonIdKey = "onda.shared.anon_id"
    static let externalIdKey = "onda.shared.external_id"

    static func mirror(config: OndaConfig, deviceId: String, anonId: String, externalId: String?) {
        guard let group = config.appGroup, let d = UserDefaults(suiteName: group) else { return }
        d.set(config.sdkKey, forKey: sdkKeyKey)
        d.set(config.apiHost.absoluteString, forKey: apiHostKey)
        d.set(deviceId, forKey: deviceIdKey)
        writeIdentity(to: d, anonId: anonId, externalId: externalId)
    }

    /// identify/reset 후 식별자만 갱신 — NSE가 현재 유저로 도달을 귀속시키도록.
    static func mirrorIdentity(appGroup: String?, anonId: String, externalId: String?) {
        guard let group = appGroup, let d = UserDefaults(suiteName: group) else { return }
        writeIdentity(to: d, anonId: anonId, externalId: externalId)
    }

    private static func writeIdentity(to d: UserDefaults, anonId: String, externalId: String?) {
        d.set(anonId, forKey: anonIdKey)
        if let ext = externalId, !ext.isEmpty { d.set(ext, forKey: externalIdKey) }
        else { d.removeObject(forKey: externalIdKey) }
    }

    struct Resolved {
        let sdkKey: String
        let apiHost: URL
        let deviceId: String
        /// 코어가 미러링한 anon_id. 구버전 코어(식별자 미러링 이전)와 공존 시 nil일 수 있다.
        let anonId: String?
        let externalId: String?
    }

    static func resolve(appGroup: String?) -> Resolved? {
        guard let group = appGroup, let d = UserDefaults(suiteName: group),
              let key = d.string(forKey: sdkKeyKey),
              let host = d.string(forKey: apiHostKey), let url = URL(string: host),
              let device = d.string(forKey: deviceIdKey) else { return nil }
        return Resolved(sdkKey: key, apiHost: url, deviceId: device,
                        anonId: d.string(forKey: anonIdKey),
                        externalId: d.string(forKey: externalIdKey))
    }
}
