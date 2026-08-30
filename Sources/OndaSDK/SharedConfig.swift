import Foundation

/// App Group을 통한 코어 ↔ NSE 설정 공유 (PRD-01A 3.1).
/// NSE는 별도 프로세스라 코어 인스턴스에 접근할 수 없다. 코어가 초기화 시 최소 설정을
/// 공유 UserDefaults에 미러링하고, NSE는 이를 읽어 도달($push_delivered)을 전송한다.
enum SharedConfig {
    static let sdkKeyKey = "onda.shared.sdk_key"
    static let apiHostKey = "onda.shared.api_host"
    static let deviceIdKey = "onda.shared.device_id"

    static func mirror(config: OndaConfig, deviceId: String) {
        guard let group = config.appGroup, let d = UserDefaults(suiteName: group) else { return }
        d.set(config.sdkKey, forKey: sdkKeyKey)
        d.set(config.apiHost.absoluteString, forKey: apiHostKey)
        d.set(deviceId, forKey: deviceIdKey)
    }

    struct Resolved {
        let sdkKey: String
        let apiHost: URL
        let deviceId: String
    }

    static func resolve(appGroup: String?) -> Resolved? {
        guard let group = appGroup, let d = UserDefaults(suiteName: group),
              let key = d.string(forKey: sdkKeyKey),
              let host = d.string(forKey: apiHostKey), let url = URL(string: host),
              let device = d.string(forKey: deviceIdKey) else { return nil }
        return Resolved(sdkKey: key, apiHost: url, deviceId: device)
    }
}
