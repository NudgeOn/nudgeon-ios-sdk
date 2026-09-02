import OndaSDK
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let navigationController = UINavigationController(rootViewController: DemoViewController())
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window

        // 앱이 종료된 상태에서 푸시를 탭해 시작한 경로.
        if let response = connectionOptions.notificationResponse {
            _ = Onda.handlePushOpened(response.notification.request.content.userInfo)
        }

        // 커스텀 URL로 콜드 스타트한 경로.
        if let url = connectionOptions.urlContexts.first?.url {
            DemoActivityCenter.shared.route(url.absoluteString, source: "scene connection")
        }

        // Universal Link로 콜드 스타트한 경로.
        if let url = connectionOptions.userActivities.compactMap(\.webpageURL).first {
            DemoActivityCenter.shared.route(url.absoluteString, source: "universal link")
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        DemoActivityCenter.shared.route(url.absoluteString, source: "custom URL")
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard let url = userActivity.webpageURL else { return }
        DemoActivityCenter.shared.route(url.absoluteString, source: "universal link")
    }
}
