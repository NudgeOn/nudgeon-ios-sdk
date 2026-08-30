import OndaSDK
import SwiftUI
import UserNotifications

/// Onda iOS 데모 앱 — "설치 → identify → track → 푸시 수신 → 딥링크 진입" E2E 예제.
/// PRD-01A 5장의 "살아있는 문서". Xcode 프로젝트 구성은 이 폴더 README 참조.
@main
struct OndaDemoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var router = DeepLinkRouter.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(router)
        }
    }
}

/// AppDelegate 수동 연동 (PRD-01A 3.1 — 기본 수동, 스위즐링 미채택).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 1) 초기화. 셀프호스팅 시 apiHost 교체. appGroup 지정 시 NSE 도달 트래킹 활성.
        Onda.initialize(config: OndaConfig(
            sdkKey: "pk_demo",
            apiHost: URL(string: "https://ingest.example.com")!,
            appGroup: "group.io.onda.demo",
            logLevel: .debug
        ))

        // 2) 콜드 스타트 딥링크 — 푸시 탭으로 앱이 열렸으면 즉시 라우팅 (유실 0).
        Onda.onPushOpened { payload in
            DeepLinkRouter.shared.route(payload.deepLink)
        }
        if let initial = Onda.getInitialPushPayload() {
            DeepLinkRouter.shared.route(initial.deepLink)
        }

        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // APNs 토큰 → 코어 대사(서버 자동 등록/갱신).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Onda.setDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs 등록 실패: \(error)")
    }

    // 포그라운드 수신.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        Onda.handlePushReceived(notification.request.content.userInfo)
        return [.banner, .sound, .badge]
    }

    // 푸시 탭 → 앱 진입 (딥링크 라우팅).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        Onda.handlePushOpened(response.notification.request.content.userInfo)
    }
}

/// 데모용 딥링크 라우터 — 실제 앱에선 NavigationStack/좌표계에 연결.
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var lastDeepLink: String?
    func route(_ link: String?) {
        guard let link else { return }
        DispatchQueue.main.async { self.lastDeepLink = link }
    }
}
