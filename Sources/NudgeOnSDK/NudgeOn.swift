import Foundation

/// NudgeOn iOS SDK 공개 진입점 (PRD-01A 2장). API 완전 동형 — 4개 플랫폼 1:1 대응.
/// 코어가 유일한 상태 보유자: 오프라인 큐·식별자 영속·배치 플러시·토큰 라이프사이클.
public enum NudgeOn {
    private static var core: NudgeOnCore?
    private static let bootLock = NSLock()

    /// 초기화 (PRD-01A 2.1). initialize 이전 호출은 코어 내부 큐에 보관 후 순서 실행.
    public static func initialize(config: NudgeOnConfig) {
        bootLock.lock(); defer { bootLock.unlock() }
        if core != nil {
            NudgeOnLog.warn("이미 초기화됨 — 중복 initialize 무시")
            return
        }
        core = NudgeOnCore(config: config)
        core?.start()
    }

    public static func identify(externalId: String) { core?.identify(externalId) }
    public static func reset() { core?.reset() }
    public static func setUserAttributes(_ attrs: [String: NudgeOnValue]) { core?.setUserAttributes(attrs) }
    public static func track(_ name: String, properties: [String: Any]? = nil) {
        core?.track(name, properties: properties ?? [:])
    }
    public static func flush() { core?.flush() }

    public static func getDeviceId() -> String? { core?.deviceId }
    public static func getAnonId() -> String? { core?.anonId }
    public static func setLogLevel(_ level: NudgeOnConfig.LogLevel) { NudgeOnLog.level = level }

    // MARK: 푸시 (PRD-01A 2.4)

    /// OS 권한 요청 → 토큰 획득 → 서버 등록까지 일괄. 토큰은 AppDelegate 콜백으로 도착한다.
    @discardableResult
    public static func registerForPush(provisional: Bool = false) async -> PushPermissionResult {
        await core?.registerForPush(provisional: provisional) ?? .denied
    }

    /// 서비스 수준 수신 동의 (OS 권한과 별개 축).
    public static func setPushSubscription(_ optedIn: Bool) { core?.setPushSubscription(optedIn) }

    /// 구독 상태 조회 {serviceOptIn, osPermission, tokenRegistered}.
    public static func getPushSubscription() async -> SubscriptionState {
        await core?.getPushSubscription()
            ?? SubscriptionState(serviceOptIn: true, osPermission: "not_determined", tokenRegistered: false)
    }

    // MARK: 리스너 (PRD-01A 2.5) — 콜드 스타트 유실 없이 전달

    @discardableResult
    public static func onPushOpened(_ handler: @escaping (PushPayload) -> Void) -> UUID? {
        core?.bus.onPushOpened(handler)
    }

    @discardableResult
    public static func onPushReceived(_ handler: @escaping (PushPayload) -> Void) -> UUID? {
        core?.bus.onPushReceived(handler)
    }

    public static func off(_ token: UUID) { core?.bus.off(token) }

    /// 콜드 스타트로 앱이 푸시 탭에 의해 열렸으면 그 페이로드, 아니면 nil (RN/Flutter 대응 경로).
    public static func getInitialPushPayload() -> PushPayload? { core?.bus.getInitialPushPayload() }

    // MARK: AppDelegate 수동 연동 (PRD-01A 3.1 — 기본 수동, 스위즐링 미채택)

    /// application(_:didRegisterForRemoteNotificationsWithDeviceToken:)에서 호출.
    public static func setDeviceToken(_ deviceToken: Data) { core?.setDeviceToken(deviceToken) }

    /// 푸시 탭으로 앱 진입 시 호출 (UNUserNotificationCenterDelegate didReceive response).
    /// NudgeOn 메시지면 true 반환 후 처리 — 타 푸시 SDK 공존 시 라우팅 분기용.
    @discardableResult
    public static func handlePushOpened(_ userInfo: [AnyHashable: Any]) -> Bool {
        core?.handleRemoteNotification(userInfo, opened: true) ?? false
    }

    /// 포그라운드 수신 시 호출 (willPresent notification).
    @discardableResult
    public static func handlePushReceived(_ userInfo: [AnyHashable: Any]) -> Bool {
        core?.handleRemoteNotification(userInfo, opened: false) ?? false
    }
}

enum NudgeOnLog {
    static var level: NudgeOnConfig.LogLevel = .warn
    static func warn(_ msg: @autoclosure () -> String) { if level >= .warn { print("[NudgeOn][warn] \(msg())") } }
    static func info(_ msg: @autoclosure () -> String) { if level >= .info { print("[NudgeOn][info] \(msg())") } }
    static func error(_ msg: @autoclosure () -> String) { if level >= .error { print("[NudgeOn][error] \(msg())") } }
}
