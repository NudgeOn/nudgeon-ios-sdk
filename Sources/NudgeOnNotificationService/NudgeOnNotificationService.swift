#if os(iOS)
import UserNotifications
import NudgeOnSDK

/// NSE 베이스 클래스 — 도달(delivered) 트래킹 + rich push (PRD-01A 3.1).
/// iOS 도달 지표(PRD-07)는 이 익스텐션 없이는 불가능하므로 온보딩 필수 단계.
///
/// 고객사는 이 클래스를 상속하고 `appGroup`만 오버라이드하면 된다:
/// ```swift
/// class NotificationService: NudgeOnNotificationServiceBase {
///     override var appGroup: String? { "group.io.nudgeon.myapp" }
/// }
/// ```
open class NudgeOnNotificationServiceBase: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    /// 코어 NudgeOnConfig.appGroup과 동일해야 도달 전송 설정을 읽을 수 있다.
    open var appGroup: String? { nil }

    open override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let mutable = request.content.mutableCopy() as? UNMutableNotificationContent
        bestAttempt = mutable
        let userInfo = request.content.userInfo
        let nudgeon = userInfo["nudgeon"] as? [AnyHashable: Any]

        // rich push — image_url이 있으면 첨부(실패해도 알림은 전달).
        if let urlString = nudgeon?["image_url"] as? String, let url = URL(string: urlString) {
            attachImage(from: url, to: mutable) { [weak self] in
                self?.reportAndFinish(nudgeon: nudgeon)
            }
        } else {
            reportAndFinish(nudgeon: nudgeon)
        }
    }

    private func reportAndFinish(nudgeon: [AnyHashable: Any]?) {
        guard let messageId = nudgeon?["message_id"] as? String else {
            finish(); return
        }
        NudgeOnDelivery.reportDelivered(messageId: messageId, appGroup: appGroup) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        if let handler = contentHandler {
            handler(bestAttempt ?? UNMutableNotificationContent())
        }
    }

    private func attachImage(from url: URL, to content: UNMutableNotificationContent?,
                             completion: @escaping () -> Void) {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            defer { completion() }
            guard let tempURL = tempURL, let content = content else { return }
            let dir = FileManager.default.temporaryDirectory
            let dest = dir.appendingPathComponent(url.lastPathComponent.isEmpty ? "nudgeon_image" : url.lastPathComponent)
            try? FileManager.default.moveItem(at: tempURL, to: dest)
            if let attachment = try? UNNotificationAttachment(identifier: "nudgeon_image", url: dest) {
                content.attachments = [attachment]
            }
        }
        task.resume()
    }

    open override func serviceExtensionTimeWillExpire() {
        finish()
    }
}
#endif
