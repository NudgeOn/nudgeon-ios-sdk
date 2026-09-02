import Foundation

struct DemoConfiguration: Equatable {
    static let placeholderSDKKey = "pk_sample_replace_me"
    static let localAPIHost = URL(string: "http://localhost:8080")!

    let sdkKey: String
    let apiHost: URL
    let appGroup: String?

    var usesPlaceholderKey: Bool { sdkKey == Self.placeholderSDKKey }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> DemoConfiguration {
        let requestedKey = configuredValue(
            environmentKey: "NUDGEON_SDK_KEY",
            infoKey: "NudgeOnSDKKey",
            environment: environment,
            infoDictionary: infoDictionary
        )
        let sdkKey: String
        if let requestedKey, requestedKey.hasPrefix("pk_") {
            sdkKey = requestedKey
        } else {
            sdkKey = placeholderSDKKey
        }

        let requestedHost = configuredValue(
            environmentKey: "NUDGEON_API_HOST",
            infoKey: "NudgeOnAPIHost",
            environment: environment,
            infoDictionary: infoDictionary
        )
        let apiHost = requestedHost.flatMap(validHTTPURL) ?? localAPIHost

        // App Group은 entitlement와 NSE Info.plist에도 동일하게 빌드 시 들어가야 한다.
        // 런타임 환경 변수로 앱 프로세스만 바꾸면 세 값이 어긋나므로 Info.plist/build setting만 사용한다.
        let appGroup = trimmedValue(infoDictionary["NudgeOnAppGroup"] as? String)

        return DemoConfiguration(sdkKey: sdkKey, apiHost: apiHost, appGroup: appGroup)
    }

    private static func configuredValue(
        environmentKey: String,
        infoKey: String,
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> String? {
        trimmedValue(environment[environmentKey] ?? infoDictionary[infoKey] as? String)
    }

    private static func trimmedValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func validHTTPURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
