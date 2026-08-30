#if os(iOS)
import UserNotifications

/// NSE 베이스 클래스 — 도달(delivered) 트래킹 + rich push (PRD-01A 3.1).
/// iOS 도달 지표(PRD-07)는 이 익스텐션 없이는 불가능하므로 온보딩 필수 단계.
/// 고객사는 이 클래스를 상속한 NotificationService를 만든다.
///
/// M2에서 $push_delivered 시스템 이벤트 전송 + 이미지 첨부를 구현한다.
open class OndaNotificationServiceBase: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttempt = request.content.mutableCopy() as? UNMutableNotificationContent
        // TODO(M2): message_id 추출 → $push_delivered 전송, image_url rich attachment
        contentHandler(bestAttempt ?? request.content)
    }

    open override func serviceExtensionTimeWillExpire() {
        if let handler = contentHandler, let content = bestAttempt {
            handler(content)
        }
    }
}
#endif
