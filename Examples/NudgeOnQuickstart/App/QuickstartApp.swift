import SwiftUI
import NudgeOnSDK

/// Maven Central의 Android quickstart와 짝을 이루는 iOS 예제다.
/// Swift Package를 **원격 게시본**(`from: 0.1.0`)으로 받아 쓴다.
@main
struct QuickstartApp: App {
    init() {
        let info = Bundle.main.infoDictionary
        let key = info?["NudgeOnSDKKey"] as? String ?? "pk_replace_me"
        let host = URL(string: info?["NudgeOnAPIHost"] as? String ?? "http://localhost:8080")!

        // 1. 초기화 — 앱 진입점에서 한 번만.
        NudgeOn.initialize(config: NudgeOnConfig(sdkKey: key, apiHost: host, logLevel: .info))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
