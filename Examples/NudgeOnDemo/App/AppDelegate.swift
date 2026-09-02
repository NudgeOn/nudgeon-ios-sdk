import NudgeOnSDK
import UIKit
import UserNotifications

/// UIKit 샘플의 앱 진입점과 NudgeOn 수동 푸시 연동을 한곳에 둔다.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let configuration = DemoConfiguration.load()

    private var pushOpenedListener: UUID?
    private var pushReceivedListener: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let configuration = Self.configuration

        NudgeOn.initialize(config: NudgeOnConfig(
            sdkKey: configuration.sdkKey,
            apiHost: configuration.apiHost,
            appGroup: configuration.appGroup,
            logLevel: .debug
        ))

        UNUserNotificationCenter.current().delegate = self

        // 리스너는 launch 초기에 등록해 콜드 스타트에서 열린 푸시도 놓치지 않는다.
        pushOpenedListener = NudgeOn.onPushOpened { payload in
            DemoActivityCenter.shared.recordPush(payload, opened: true)
            if let deepLink = payload.deepLink {
                DemoActivityCenter.shared.route(deepLink, source: "push opened")
            }
        }
        pushReceivedListener = NudgeOn.onPushReceived { payload in
            DemoActivityCenter.shared.recordPush(payload, opened: false)
        }

        let keyState = configuration.usesPlaceholderKey ? "placeholder pk_ key" : "configured pk_ key"
        DemoActivityCenter.shared.record("SDK initialized (\(keyState)); server receipt is not confirmed")
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NudgeOn.setDeviceToken(deviceToken)
        DemoActivityCenter.shared.record("APNs token received and handed to NudgeOn; server registration is asynchronous")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        DemoActivityCenter.shared.record("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let handled = NudgeOn.handlePushReceived(userInfo)
        completionHandler(handled ? .newData : .noData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        _ = NudgeOn.handlePushReceived(notification.request.content.userInfo)
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        _ = NudgeOn.handlePushOpened(response.notification.request.content.userInfo)
    }
}
