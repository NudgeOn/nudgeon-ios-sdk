import Foundation

/// 푸시 페이로드 (PRD-01A 2.5). APNs userInfo → 구조화. 브리지에도 동일 형태로 노출.
public struct PushPayload: Equatable {
    public let messageId: String
    public let campaignId: String?
    public let journeyId: String?
    public let title: String
    public let body: String
    public let deepLink: String?
    /// 커스텀 데이터 (문자열로 평탄화 — 브리지 직렬화 규칙, PRD-01A 4장).
    public let data: [String: String]

    public init(messageId: String, campaignId: String? = nil, journeyId: String? = nil,
                title: String, body: String, deepLink: String? = nil, data: [String: String] = [:]) {
        self.messageId = messageId
        self.campaignId = campaignId
        self.journeyId = journeyId
        self.title = title
        self.body = body
        self.deepLink = deepLink
        self.data = data
    }

    /// APNs `userInfo`에서 파싱. Onda 발송 규약:
    /// ```
    /// { "aps": { "alert": { "title": .., "body": .. } },
    ///   "onda": { "message_id": .., "campaign_id"?, "journey_id"?, "deep_link"?, "data"?: {..} } }
    /// ```
    /// `onda.message_id`가 없으면 Onda 메시지가 아니므로 nil (타 푸시 SDK 공존 — PRD-01A 3.2 위임 취지).
    public static func parse(_ userInfo: [AnyHashable: Any]) -> PushPayload? {
        let onda = (userInfo["onda"] as? [AnyHashable: Any]) ?? [:]
        guard let messageId = stringValue(onda["message_id"]) else { return nil }

        let (title, body) = extractAlert(userInfo["aps"])
        var data: [String: String] = [:]
        if let raw = onda["data"] as? [AnyHashable: Any] {
            for (k, v) in raw {
                if let key = k as? String, let val = stringValue(v) { data[key] = val }
            }
        }
        return PushPayload(
            messageId: messageId,
            campaignId: stringValue(onda["campaign_id"]),
            journeyId: stringValue(onda["journey_id"]),
            title: title,
            body: body,
            deepLink: stringValue(onda["deep_link"]),
            data: data
        )
    }

    /// `aps.alert`는 문자열 또는 {title, body} 딕셔너리 두 형태 모두 허용.
    private static func extractAlert(_ aps: Any?) -> (String, String) {
        guard let aps = aps as? [AnyHashable: Any] else { return ("", "") }
        if let alert = aps["alert"] as? [AnyHashable: Any] {
            return (stringValue(alert["title"]) ?? "", stringValue(alert["body"]) ?? "")
        }
        if let alert = aps["alert"] as? String {
            return ("", alert)
        }
        return ("", "")
    }

    /// 스칼라를 문자열로 정규화 (숫자·불리언도 문자열화 — 브리지 평탄화 규칙).
    private static func stringValue(_ v: Any?) -> String? {
        switch v {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
}

/// registerForPush 결과 (PRD-01A 2.4).
public enum PushPermissionResult: String {
    case granted, denied, provisional
}

/// 구독 상태 (PRD-01A 2.4). OS 권한과 서비스 opt-in은 별개 축.
public struct SubscriptionState: Equatable {
    public let serviceOptIn: Bool     // Onda.setPushSubscription로 제어하는 서비스 수준 수신 동의
    public let osPermission: String   // authorized|denied|provisional|not_determined|ephemeral
    public let tokenRegistered: Bool  // 서버에 토큰 등록 완료 여부

    public init(serviceOptIn: Bool, osPermission: String, tokenRegistered: Bool) {
        self.serviceOptIn = serviceOptIn
        self.osPermission = osPermission
        self.tokenRegistered = tokenRegistered
    }
}
