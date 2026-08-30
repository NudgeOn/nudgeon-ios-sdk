import Foundation

/// NSE에서 호출하는 도달(delivered) 리포터 (PRD-07 iOS 도달 지표).
/// 코어가 app group에 미러링한 설정을 읽어 `$push_delivered` 시스템 이벤트를 /v1/track으로 전송.
/// 코어 인스턴스에 의존하지 않으므로 별도 프로세스(NSE)에서 안전.
public enum OndaDelivery {
    /// `messageId`를 도달로 보고. `appGroup`은 코어 OndaConfig와 동일해야 한다.
    /// NSE의 짧은 실행 시간을 고려해 완료 콜백에서 contentHandler를 이어가도록 설계.
    public static func reportDelivered(messageId: String, appGroup: String?,
                                       completion: @escaping () -> Void) {
        guard let resolved = SharedConfig.resolve(appGroup: appGroup) else {
            OndaLog.warn("NSE 도달 전송 불가 — app group 설정 미러링 없음")
            completion()
            return
        }
        let config = OndaConfig(sdkKey: resolved.sdkKey, apiHost: resolved.apiHost)
        let network = Network(config: config, deviceId: resolved.deviceId)
        let item = EventQueue.Item(
            insertId: UUID().uuidString.lowercased(),
            event: "$push_delivered",
            properties: ["message_id": AnyCodable(messageId)],
            clientTs: ISO8601DateFormatter().string(from: Date()),
            anonId: "",
            externalId: nil
        )
        network.sendTrack([item]) { _ in completion() }
    }
}
