import Foundation

/// 같은 message_id의 수신을 한 번만 앱에 전달한다 (Android SeenMessages와 대칭).
///
/// 서버 채널 워커는 at-least-once다 — 공급자 전송이 끝난 직후 죽으면 같은 message_id가 한 번 더 온다
/// (플랫폼 M-4 카오스 2026-09-10, 3,000건 중 1건). APNs는 collapse-id로 알림을 접지만 포그라운드 수신
/// 콜백은 두 번 오므로 SDK가 최근 `capacity`개 message_id를 UserDefaults에 기억한다.
final class SeenMessages {
    private let defaults: UserDefaults
    private let key = "nudgeon.push.seen_message_ids"
    private let capacity: Int

    init(defaults: UserDefaults = .standard, capacity: Int = 256) {
        self.defaults = defaults
        self.capacity = capacity
    }

    /// 처음 보는 message_id면 기억하고 true, 이미 봤으면 false. 빈 ID는 접지 않는다.
    func firstTime(_ messageID: String) -> Bool {
        guard !messageID.isEmpty else { return true }
        var ids = defaults.stringArray(forKey: key) ?? []
        if ids.contains(messageID) { return false }
        if ids.count >= capacity { ids.removeFirst(ids.count - capacity + 1) }
        ids.append(messageID)
        defaults.set(ids, forKey: key)
        return true
    }
}
