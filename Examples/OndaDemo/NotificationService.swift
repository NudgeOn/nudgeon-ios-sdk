import OndaNotificationService

/// 데모 NSE 타깃 — 도달($push_delivered)·리치 푸시. iOS 도달 지표(PRD-07) 필수 단계.
/// 별도 Notification Service Extension 타깃에 추가하고, 호스트 앱과 같은 App Group을 지정한다.
final class NotificationService: OndaNotificationServiceBase {
    override var appGroup: String? { "group.io.onda.demo" }
}
