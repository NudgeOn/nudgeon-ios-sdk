import Foundation

/// SDK 초기화 설정 (PRD-01A 2.1).
public struct NudgeOnConfig {
    public enum LogLevel: Int, Comparable {
        case none, error, warn, info, debug
        public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    }

    /// App 단위 SDK Key (pk_...). 필수.
    public let sdkKey: String
    /// 수집 엔드포인트. 셀프호스팅 시 교체 — SaaS 기본값과 동등 취급 (오픈소스 1급 지원).
    public let apiHost: URL
    /// App Group ID. 설정 시 NSE(별도 프로세스)가 도달($push_delivered)을 전송할 수 있다 (PRD-01A 3.1).
    public var appGroup: String?
    public var logLevel: LogLevel
    public var flushInterval: TimeInterval
    public var flushBatchSize: Int
    public var autoTrackSessions: Bool
    public var autoRegisterPushToken: Bool

    public init(
        sdkKey: String,
        apiHost: URL,
        appGroup: String? = nil,
        logLevel: LogLevel = .warn,
        flushInterval: TimeInterval = 10,
        flushBatchSize: Int = 10,
        autoTrackSessions: Bool = true,
        autoRegisterPushToken: Bool = true
    ) {
        self.sdkKey = sdkKey
        self.apiHost = apiHost
        self.appGroup = appGroup
        self.logLevel = logLevel
        self.flushInterval = flushInterval
        self.flushBatchSize = flushBatchSize
        self.autoTrackSessions = autoTrackSessions
        self.autoRegisterPushToken = autoRegisterPushToken
    }
}

/// 속성/프로퍼티 값 타입 (PRD-01A 2.2). datetime은 ISO8601 문자열로 전송.
public enum NudgeOnValue {
    case string(String)
    case number(Double)
    case bool(Bool)
    case stringArray([String])
    case null  // unset

    var json: Any? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .stringArray(let a): return a
        case .null: return NSNull()
        }
    }
}
