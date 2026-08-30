import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#endif

/// 푸시 권한·토큰 라이프사이클·구독 상태 (PRD-01A 2.4).
/// OS 호출부(권한 요청·원격 등록)와 순수 로직(토큰 대사·구독 영속)을 분리 — 후자는 단위 테스트 대상.
final class PushManager {
    private let config: OndaConfig
    private let network: Network
    private let defaults: UserDefaults
    private let optInKey = "onda.push.service_opt_in"
    private let tokenKey = "onda.push.last_token"
    private let tokenExtKey = "onda.push.last_token_external"

    init(config: OndaConfig, network: Network, defaults: UserDefaults = .standard) {
        self.config = config
        self.network = network
        self.defaults = defaults
    }

    // MARK: 서비스 구독 (OS 권한과 별개 축)

    var serviceOptIn: Bool {
        // 기본값 true — 미설정 시 수신 동의 상태.
        defaults.object(forKey: optInKey) == nil ? true : defaults.bool(forKey: optInKey)
    }

    func setServiceOptIn(_ optedIn: Bool) {
        defaults.set(optedIn, forKey: optInKey)
    }

    var tokenRegistered: Bool { defaults.string(forKey: tokenKey) != nil }

    func subscriptionState(osPermission: String) -> SubscriptionState {
        SubscriptionState(serviceOptIn: serviceOptIn, osPermission: osPermission, tokenRegistered: tokenRegistered)
    }

    // MARK: 토큰 대사 (S-5 — 토큰 변경/유저 변경 시 서버 자동 갱신)

    /// APNs Data 토큰을 hex 문자열로 변환.
    static func hexString(from token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// 토큰 대사 판정 — 마지막 등록분과 토큰 또는 유저가 달라졌는지 (S-5 핵심 결정).
    func needsRegistration(token: String, externalId: String?) -> Bool {
        token != defaults.string(forKey: tokenKey) || externalId != defaults.string(forKey: tokenExtKey)
    }

    /// 등록 성공을 영속 — 이후 동일 토큰/유저는 no-op 대상이 된다.
    func markRegistered(token: String, externalId: String?) {
        defaults.set(token, forKey: tokenKey)
        if let ext = externalId { defaults.set(ext, forKey: tokenExtKey) }
        else { defaults.removeObject(forKey: tokenExtKey) }
    }

    /// 새 토큰/유저 조합이 마지막 등록분과 다를 때만 서버 등록. 성공 시 영속.
    /// 재실행 시 OS가 같은 토큰을 주면 no-op, 토큰이 바뀌었으면 자동 갱신된다.
    func registerToken(_ token: String, externalId: String?, anonId: String, osPermission: String) {
        guard needsRegistration(token: token, externalId: externalId) else {
            OndaLog.info("push 토큰 변화 없음 — 등록 생략")
            return
        }
        network.registerToken(pushToken: token, externalId: externalId, anonId: anonId, osPermission: osPermission) { [self] ok in
            if ok {
                markRegistered(token: token, externalId: externalId)
                OndaLog.info("push 토큰 등록 완료")
            } else {
                OndaLog.warn("push 토큰 등록 실패 — 다음 기회 재시도")
            }
        }
    }

    /// reset 시 로컬 등록 캐시 무효화 — 다음 토큰을 새 유저로 재등록하도록.
    func clearTokenCache() {
        defaults.removeObject(forKey: tokenKey)
        defaults.removeObject(forKey: tokenExtKey)
    }

    // MARK: OS 권한

#if canImport(UserNotifications) && !os(macOS)
    /// 권한 요청 → 원격 등록 트리거. 토큰은 AppDelegate 콜백으로 도착 → Onda.setDeviceToken.
    func requestAuthorization(provisional: Bool) async -> PushPermissionResult {
        let center = UNUserNotificationCenter.current()
        var options: UNAuthorizationOptions = [.alert, .badge, .sound]
        if provisional { options.insert(.provisional) }
        let granted = (try? await center.requestAuthorization(options: options)) ?? false
        let settings = await center.notificationSettings()
        await registerForRemoteNotifications()
        return Self.result(from: settings.authorizationStatus, requestedGranted: granted)
    }

    func currentOSPermission() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.permissionString(settings.authorizationStatus)
    }

    static func result(from status: UNAuthorizationStatus, requestedGranted: Bool) -> PushPermissionResult {
        switch status {
        case .authorized: return .granted
        case .provisional: return .provisional
        case .ephemeral: return .granted
        case .denied: return .denied
        default: return requestedGranted ? .granted : .denied
        }
    }

    static func permissionString(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        default: return "not_determined"
        }
    }

    @MainActor
    private func registerForRemoteNotifications() {
#if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
#endif
    }
#else
    func requestAuthorization(provisional: Bool) async -> PushPermissionResult { .denied }
    func currentOSPermission() async -> String { "not_determined" }
#endif
}
