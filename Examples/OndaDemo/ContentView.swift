import OndaSDK
import SwiftUI

/// 데모 UI — identify·track·푸시 권한·구독 상태·마지막 딥링크를 한 화면에서 실습.
struct ContentView: View {
    @EnvironmentObject private var router: DeepLinkRouter
    @State private var externalId = "user-123"
    @State private var pushResult = "-"
    @State private var subscription = "-"

    var body: some View {
        NavigationStack {
            Form {
                Section("식별") {
                    TextField("external_id", text: $externalId)
                        .textInputAutocapitalization(.never)
                    Button("identify") { Onda.identify(externalId: externalId) }
                    Button("reset (로그아웃)", role: .destructive) { Onda.reset() }
                }

                Section("이벤트") {
                    Button("track: product_viewed") {
                        Onda.track("product_viewed", properties: ["product_id": "P-1", "price": 12900])
                    }
                    Button("track + 즉시 flush") {
                        Onda.track("checkout_started", properties: ["cart_value": 39000])
                        Onda.flush()
                    }
                    Button("속성 설정") {
                        Onda.setUserAttributes(["vip_level": .number(3), "nickname": .string("ethan")])
                    }
                }

                Section("푸시") {
                    Button("registerForPush") {
                        Task {
                            let r = await Onda.registerForPush()
                            pushResult = r.rawValue
                            let s = await Onda.getPushSubscription()
                            subscription = "opt-in=\(s.serviceOptIn) os=\(s.osPermission) token=\(s.tokenRegistered)"
                        }
                    }
                    LabeledContent("권한 결과", value: pushResult)
                    LabeledContent("구독 상태", value: subscription)
                    Toggle("서비스 수신 동의", isOn: Binding(
                        get: { true },
                        set: { Onda.setPushSubscription($0) }
                    ))
                }

                Section("딥링크 (푸시 탭 결과)") {
                    LabeledContent("마지막 딥링크", value: router.lastDeepLink ?? "없음")
                }

                Section("디바이스") {
                    LabeledContent("device_id", value: Onda.getDeviceId() ?? "-")
                    LabeledContent("anon_id", value: Onda.getAnonId() ?? "-")
                }
            }
            .navigationTitle("Onda Demo")
        }
    }
}
