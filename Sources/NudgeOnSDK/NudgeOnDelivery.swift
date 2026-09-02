import Foundation

/// NSE에서 호출하는 도달(delivered) 리포터 (PRD-07 iOS 도달 지표).
/// 코어가 app group에 미러링한 설정·식별자를 읽어 `$push_delivered` 시스템 이벤트를 /v1/track으로 전송.
/// 코어 인스턴스에 의존하지 않으므로 별도 프로세스(NSE)에서 안전.
///
/// 서버 수집 스키마(apps/api/src/ingestion/schemas.ts trackEventSchema)의 식별자 규칙:
/// - `anon_id`: UUID 문자열(옵션), `external_id`: 1~256자(옵션) — 둘 중 하나는 필수
/// - `device.device_id`: UUID
/// 규칙을 만족하지 못하면 전송하지 않는다(400이 확정된 요청을 보내지 않음).
public enum NudgeOnDelivery {
    /// `messageId`를 도달로 보고. `appGroup`은 코어 NudgeOnConfig와 동일해야 한다.
    /// NSE의 짧은 실행 시간을 고려해 완료 콜백에서 contentHandler를 이어가도록 설계.
    public static func reportDelivered(messageId: String, appGroup: String?,
                                       completion: @escaping () -> Void) {
        guard let resolved = SharedConfig.resolve(appGroup: appGroup) else {
            NudgeOnLog.warn("NSE 도달 전송 불가 — app group 설정 미러링 없음 (코어 initialize 전이거나 appGroup 불일치)")
            completion()
            return
        }
        guard let item = buildEvent(messageId: messageId, resolved: resolved, now: Date()) else {
            NudgeOnLog.warn("NSE 도달 전송 건너뜀 — 유효한 anon_id(UUID)/external_id 없음 (message_id=\(messageId))")
            completion()
            return
        }
        let config = NudgeOnConfig(sdkKey: resolved.sdkKey, apiHost: resolved.apiHost)
        let network = Network(config: config, deviceId: resolved.deviceId)
        network.sendTrack([item]) { ok in
            if !ok { NudgeOnLog.warn("NSE 도달 전송 실패 (message_id=\(messageId))") }
            completion()
        }
    }

    /// 서버 스키마를 만족하는 도달 이벤트를 구성. 식별자 규칙 위반 시 nil (호출자가 건너뜀).
    static func buildEvent(messageId: String, resolved: SharedConfig.Resolved, now: Date) -> EventQueue.Item? {
        guard isUUID(resolved.deviceId) else { return nil }
        let anon = resolved.anonId.flatMap { isUUID($0) ? $0.lowercased() : nil }
        let ext = resolved.externalId.flatMap { (1...256).contains($0.count) ? $0 : nil }
        guard anon != nil || ext != nil else { return nil }
        return EventQueue.Item(
            insertId: UUID().uuidString.lowercased(),
            event: "$push_delivered",
            properties: ["message_id": AnyCodable(messageId)],
            clientTs: ISO8601DateFormatter().string(from: now),
            anonId: anon ?? "",
            externalId: ext
        )
    }

    static func isUUID(_ s: String) -> Bool { UUID(uuidString: s) != nil }
}
