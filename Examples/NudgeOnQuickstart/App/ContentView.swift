import SwiftUI
import NudgeOnSDK

struct ContentView: View {
    @State private var externalId = ""
    @State private var lines: [String] = []
    @State private var deviceId = "-"
    @State private var anonId = "-"
    @State private var optIn = false
    @State private var osPermission = "-"
    @State private var tokenRegistered = false

    private var usingPlaceholderKey: Bool {
        (Bundle.main.infoDictionary?["NudgeOnSDKKey"] as? String ?? "").hasPrefix("pk_replace_me")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NudgeOn Quickstart").font(.title2.bold())
                    Text("의존성: nudgeon-ios-sdk 0.1.0 (Swift Package, 원격)")
                        .font(.caption).foregroundColor(.secondary)
                }

                if usingPlaceholderKey {
                    Text("⚠️ placeholder 키입니다. NUDGEON_SDK_KEY를 설정하면 실제로 수집됩니다.")
                        .font(.caption).foregroundColor(.orange)
                }

                stateBox

                TextField("external id (예: user-123)", text: $externalId)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                VStack(spacing: 8) {
                    button("identify") {
                        let id = externalId.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty else { return log("external id를 입력하세요") }
                        NudgeOn.identify(externalId: id)
                        NudgeOn.setUserAttributes(["plan": .string("free"), "locale": .string("ko-KR")])
                        log("identify(\(id)) + 속성 2건")
                        refresh()
                    }
                    button("track (product_viewed)") {
                        NudgeOn.track("product_viewed", properties: ["product_id": "P-1", "price": 12900])
                        log("track(product_viewed)")
                    }
                    button("알림 권한 요청") {
                        Task {
                            let result = await NudgeOn.registerForPush()
                            // OS 권한과 서비스 수신 동의는 별개다. 허용일 때만 구독을 켠다.
                            NudgeOn.setPushSubscription(result == .granted)
                            log("권한 결과: \(result.rawValue)")
                            await refreshAsync()
                        }
                    }
                    button("flush") {
                        NudgeOn.flush()
                        log("flush() — 큐를 즉시 전송")
                    }
                    button("reset") {
                        NudgeOn.reset()
                        // reset()은 로컬 식별자·토큰 캐시만 정리한다. 서버 로그아웃 완료가 아니다.
                        log("reset() — 로컬 상태만 초기화됨")
                        refresh()
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("로그").font(.headline)
                    Text(lines.isEmpty ? "-" : lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
        }
        .task {
            // 2. 푸시 리스너. 콜드 스타트로 놓친 것도 버퍼에서 재생된다.
            _ = NudgeOn.onPushOpened { p in log("푸시 열림: \(p.title) → \(p.deepLink ?? "-")") }
            _ = NudgeOn.onPushReceived { p in log("푸시 수신: \(p.messageId)") }
            if let initial = NudgeOn.getInitialPushPayload() {
                log("콜드 스타트 푸시: \(initial.messageId)")
            }
            log("초기화 완료")
            await refreshAsync()
        }
    }

    private var stateBox: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("device id", deviceId)
            row("anon id", anonId)
            row("수신 동의", String(optIn))
            row("OS 권한", osPermission)
            row("토큰 등록", String(tokenRegistered))
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(k).frame(width: 78, alignment: .leading).foregroundColor(.secondary)
            Text(v).textSelection(.enabled)
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func refresh() {
        deviceId = NudgeOn.getDeviceId() ?? "-"
        anonId = NudgeOn.getAnonId() ?? "-"
    }

    private func refreshAsync() async {
        refresh()
        let s = await NudgeOn.getPushSubscription()
        optIn = s.serviceOptIn
        osPermission = s.osPermission
        tokenRegistered = s.tokenRegistered
    }

    private func log(_ message: String) {
        let ts = DateFormatter.ts.string(from: Date())
        lines.insert("\(ts)  \(message)", at: 0)
        if lines.count > 30 { lines.removeLast() }
    }
}

private extension DateFormatter {
    static let ts: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
