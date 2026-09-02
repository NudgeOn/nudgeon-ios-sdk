import Foundation

/// 배치 업로드 클라이언트 (PRD-01 6.1 /v1/track). 재시도는 큐 잔존으로 처리.
final class Network {
    private let config: OndaConfig
    private let session: URLSession
    private let deviceId: String

    init(config: OndaConfig, deviceId: String, session: URLSession = .shared) {
        self.config = config
        self.deviceId = deviceId
        self.session = session
    }

    /// track 배치 전송. 성공(2xx) 시 true → 호출자가 큐에서 ack.
    func sendTrack(_ items: [EventQueue.Item], platform: String = "ios",
                   completion: @escaping (Bool) -> Void) {
        guard !items.isEmpty else { completion(true); return }
        post(path: "/v1/track", body: trackBody(items, platform: platform), completion: completion)
    }

    /// /v1/track 요청 본문 (PRD-01 6.1). 서버 스키마가 strict라 빈 anon_id는 키 자체를 생략한다
    /// (anon_id는 UUID 또는 부재만 허용 — external_id만 있는 이벤트를 위해).
    func trackBody(_ items: [EventQueue.Item], platform: String = "ios") -> [String: Any] {
        let batch: [[String: Any]] = items.map { item in
            var e: [String: Any] = [
                "insert_id": item.insertId,
                "event": item.event,
                "client_ts": item.clientTs,
                "properties": item.properties.mapValues { $0.value },
            ]
            if !item.anonId.isEmpty { e["anon_id"] = item.anonId }
            if let ext = item.externalId { e["external_id"] = ext }
            return e
        }
        return [
            "batch": batch,
            "device": ["device_id": deviceId, "platform": platform],
        ]
    }

    /// identify 전송 (PRD-01 6.1 /v1/identify).
    func sendIdentify(externalId: String, anonId: String, attributes: [String: Any],
                      completion: @escaping (Bool) -> Void) {
        let body: [String: Any] = [
            "external_id": externalId,
            "anon_id": anonId,
            "attributes": attributes,
        ]
        post(path: "/v1/identify", body: body, completion: completion)
    }

    /// 토큰 등록 (PRD-01 6.1 /v1/devices/token).
    func registerToken(pushToken: String, externalId: String?, anonId: String,
                       osPermission: String, completion: @escaping (Bool) -> Void) {
        var body: [String: Any] = [
            "device": ["device_id": deviceId, "platform": "ios"],
            "push_token": pushToken,
            "os_permission": osPermission,
            "anon_id": anonId,
        ]
        if let ext = externalId { body["external_id"] = ext }
        post(path: "/v1/devices/token", body: body, completion: completion)
    }

    private func post(path: String, body: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: path, relativeTo: config.apiHost),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.sdkKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        session.dataTask(with: req) { _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            completion(err == nil && (200...299).contains(code))
        }.resume()
    }
}
