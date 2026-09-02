import Foundation
@testable import NudgeOnSDK

/// 시나리오 스텝을 격리된 NudgeOnCore에 대해 실행 — 시나리오마다 고유 UserDefaults·큐 파일로 오염 방지.
enum ContractRunner {
    /// 시나리오 config + 목 서버 host로 격리 코어 구성.
    static func buildCore(config: [String: Any], apiHost: URL) -> NudgeOnCore {
        let defaults = UserDefaults(suiteName: "nudgeon.contract.\(UUID().uuidString)")!
        let identity = Identity(defaults: defaults)
        // flushInterval 기본을 크게 — 자동 타이머 플러시가 시나리오에 끼어들지 않도록(명시 flush만).
        let nudgeonConfig = NudgeOnConfig(
            sdkKey: "pk_contract",
            apiHost: apiHost,
            logLevel: .none,
            flushInterval: (config["flushInterval"] as? Double) ?? 3600,
            flushBatchSize: (config["flushBatchSize"] as? Int) ?? 10,
            autoTrackSessions: (config["autoTrackSessions"] as? Bool) ?? true
        )
        let queue = EventQueue(fileName: "contract_\(UUID().uuidString).json")
        let network = Network(config: nudgeonConfig, deviceId: identity.deviceId)
        let push = PushManager(config: nudgeonConfig, network: network, defaults: defaults)
        let core = NudgeOnCore(config: nudgeonConfig, identity: identity, queue: queue, network: network, push: push)
        core.start()
        return core
    }

    static func run(step: [String: Any], on core: NudgeOnCore) {
        let call = step["call"] as? String ?? ""
        let args = step["args"] as? [String: Any] ?? [:]
        switch call {
        case "identify": core.identify(args["externalId"] as? String ?? "")
        case "track": core.track(args["name"] as? String ?? "", properties: args["properties"] as? [String: Any] ?? [:])
        case "flush": core.flush()
        case "reset": core.reset()
        case "setUserAttributes": core.setUserAttributes(toNudgeOnValues(args["attrs"] as? [String: Any] ?? [:]))
        case "setPushToken": core.setDeviceToken(dataFromHex(args["hex"] as? String ?? ""))
        default: break
        }
    }

    private static func toNudgeOnValues(_ raw: [String: Any]) -> [String: NudgeOnValue] {
        raw.mapValues { v in
            if let s = v as? String { return .string(s) }
            if v is NSNull { return .null }
            if let n = v as? NSNumber {
                if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
                return .number(n.doubleValue)
            }
            if let a = v as? [String] { return .stringArray(a) }
            return .null
        }
    }

    private static func dataFromHex(_ hex: String) -> Data {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex, let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) {
            if let byte = UInt8(hex[idx..<next], radix: 16) { data.append(byte) }
            idx = next
        }
        return data
    }
}
