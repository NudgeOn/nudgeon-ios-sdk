import Foundation
import OndaSDK

extension Notification.Name {
    static let demoActivityDidChange = Notification.Name("io.onda.demo.activity-did-change")
}

/// SDK 콜백과 SceneDelegate 입력을 UIKit 화면으로 전달하는 작은 샘플 라우터/상태 저장소.
final class DemoActivityCenter {
    struct Snapshot {
        let lastDeepLink: String
        let lastActivity: String
    }

    static let shared = DemoActivityCenter()

    private let lock = NSLock()
    private var lastDeepLink = "No deep link received"
    private var lastActivity = "Waiting for an SDK action"

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(lastDeepLink: lastDeepLink, lastActivity: lastActivity)
    }

    func route(_ rawLink: String?, source: String) {
        guard let rawLink,
              let url = URL(string: rawLink),
              url.scheme != nil else {
            record("No valid deep link in \(source)")
            return
        }

        mutate {
            lastDeepLink = "\(rawLink)\nsource: \(source)"
            lastActivity = "Deep link routed into the UIKit sample"
        }
    }

    func recordPush(_ payload: PushPayload, opened: Bool) {
        let kind = opened ? "opened" : "received"
        record("Push \(kind): message_id=\(payload.messageId), title=\(payload.title)")
    }

    func record(_ message: String) {
        mutate { lastActivity = message }
    }

    private func mutate(_ update: () -> Void) {
        lock.lock()
        update()
        lock.unlock()

        let notify = {
            NotificationCenter.default.post(name: .demoActivityDidChange, object: self)
        }
        if Thread.isMainThread {
            notify()
        } else {
            DispatchQueue.main.async(execute: notify)
        }
    }
}
