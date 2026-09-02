import Foundation
import NudgeOnNotificationService

/// Rich push/NSE 연결 예제. App 타깃과 동일한 App Group을 사용해야 한다.
final class NotificationService: NudgeOnNotificationServiceBase {
    override var appGroup: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "NudgeOnAppGroup") as? String
        return value?.isEmpty == false ? value : nil
    }
}
