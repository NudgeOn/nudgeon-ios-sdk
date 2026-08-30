import Foundation

/// Onda iOS SDK 공개 진입점 (PRD-01A 2장). API 완전 동형 — 4개 플랫폼 1:1 대응.
/// 코어가 유일한 상태 보유자: 오프라인 큐·식별자 영속·배치 플러시·토큰 라이프사이클.
public enum Onda {
    private static var core: OndaCore?
    private static let bootLock = NSLock()

    /// 초기화 (PRD-01A 2.1). initialize 이전 호출은 코어 내부 큐에 보관 후 순서 실행.
    public static func initialize(config: OndaConfig) {
        bootLock.lock(); defer { bootLock.unlock() }
        if core != nil {
            OndaLog.warn("이미 초기화됨 — 중복 initialize 무시")
            return
        }
        core = OndaCore(config: config)
        core?.start()
    }

    public static func identify(externalId: String) { core?.identify(externalId) }
    public static func reset() { core?.reset() }
    public static func setUserAttributes(_ attrs: [String: OndaValue]) { core?.setUserAttributes(attrs) }
    public static func track(_ name: String, properties: [String: Any]? = nil) {
        core?.track(name, properties: properties ?? [:])
    }
    public static func flush() { core?.flush() }

    public static func getDeviceId() -> String? { core?.deviceId }
    public static func getAnonId() -> String? { core?.anonId }
    public static func setLogLevel(_ level: OndaConfig.LogLevel) { OndaLog.level = level }

    // 푸시(registerForPush·리스너)는 M2에서 구현 (PRD-01A 6장 마일스톤).
}

enum OndaLog {
    static var level: OndaConfig.LogLevel = .warn
    static func warn(_ msg: @autoclosure () -> String) { if level >= .warn { print("[Onda][warn] \(msg())") } }
    static func info(_ msg: @autoclosure () -> String) { if level >= .info { print("[Onda][info] \(msg())") } }
    static func error(_ msg: @autoclosure () -> String) { if level >= .error { print("[Onda][error] \(msg())") } }
}
