#if canImport(UIKit)
import UIKit

/// Explicit, short-lived test session. Does not enable production campaigns or depend on push consent.
@MainActor public final class InAppTestClient {
    public struct Configuration {
        public let apiURL: URL
        public let sdkKey: String
        public let allowedURLSchemes: Set<String>
        public let allowedWebHosts: Set<String>
        public init(apiURL: URL, sdkKey: String, allowedURLSchemes: Set<String> = [], allowedWebHosts: Set<String> = []) {
            self.apiURL = apiURL; self.sdkKey = sdkKey
            self.allowedURLSchemes = Set(allowedURLSchemes.map { $0.lowercased() })
            self.allowedWebHosts = Set(allowedWebHosts.map { $0.lowercased() })
        }
    }
    private let config: Configuration
    private let host: () -> UIViewController?
    private let allowed: () -> Bool
    private let action: (InAppAction) -> Void
    private let diagnostic: (String) -> Void
    private let session = URLSession(configuration: .ephemeral, delegate: InAppNoRedirect(), delegateQueue: nil)
    private var credential: String?
    private var polling: Task<Void, Never>?
    private var rendering: InAppViewController?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var runID: String?
    private var events: [(id: String, run: String, kind: String, detail: String)] = []

    public init(configuration: Configuration, host: @escaping () -> UIViewController?, isAllowed: @escaping () -> Bool,
                onAction: @escaping (InAppAction) -> Void, onDiagnostic: @escaping (String) -> Void = { _ in }) throws {
        let url = configuration.apiURL
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw InAppError.invalidServer }
        config = configuration; self.host = host; allowed = isAllowed; action = onAction; diagnostic = onDiagnostic
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.interrupt("APP_BACKGROUND") }
        })
    }
    deinit { polling?.cancel(); observers.forEach(NotificationCenter.default.removeObserver); session.invalidateAndCancel() }

    /// Call only after the person holding the device explicitly agrees to enter test mode.
    public func pair(token: String, deviceName: String = "iOS test device") async throws -> InAppPairing {
        await end(); let current = generation
        let data = try await request("pair", body: ["token": token, "label": String(deviceName.prefix(80)), "platform": "ios", "sdk_version": "inapp-test/1"])
        let result = try JSONDecoder().decode(InAppPairing.self, from: data)
        guard generation == current else { throw InAppError.sessionClosed }
        credential = result.credential; diagnostic("CONFIRM_DEVICE:\(result.confirmation_code)"); startPolling(); return result
    }
    /// Present from an app-owned debug/settings action; never automatically on launch.
    public func presentConnection(from presenter: UIViewController) {
        let alert = UIAlertController(title: "NudgeOn test device", message: "Paste the pairing code from the NudgeOn console. Test actions may open app screens.", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Pairing code"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self, weak alert, weak presenter] _ in
            guard let self, let token = alert?.textFields?.first?.text else { return }
            Task { @MainActor in
                do {
                    let result = try await self.pair(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
                    let notice = UIAlertController(title: result.confirmation_code, message: "Confirm this number in NudgeOn, then keep the app open. The connection expires after 30 minutes.", preferredStyle: .alert)
                    notice.addAction(UIAlertAction(title: "OK", style: .default)); presenter?.present(notice, animated: true)
                } catch {
                    let notice = UIAlertController(title: "Connection failed", message: "Create a new pairing code in NudgeOn and try again.", preferredStyle: .alert)
                    notice.addAction(UIAlertAction(title: "OK", style: .default)); presenter?.present(notice, animated: true)
                }
            }
        })
        presenter.present(alert, animated: true)
    }
    public func end() async {
        let old = credential; credential = nil; generation = UUID(); polling?.cancel(); polling = nil
        rendering?.close(); rendering = nil; runID = nil; events.removeAll()
        if let old { _ = try? await request("end", body: [:], token: old) }
    }
    /// Host must call when login identity, consent or screen eligibility changes.
    public func contextChanged() { interrupt("CONTEXT_CHANGED") }
    private func interrupt(_ reason: String) {
        generation = UUID()
        if let id = runID { queue(id, "failed", reason) }
        rendering?.close(); rendering = nil; runID = nil
    }
    private func queue(_ run: String, _ kind: String, _ detail: String = "") {
        if events.count < 200 { events.append((UUID().uuidString, run, kind, String(detail.prefix(200)))) }
        diagnostic("\(kind):\(detail)")
    }
    private func startPolling() {
        polling?.cancel()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.credential != nil else { return }
                do {
                    if UIApplication.shared.applicationState == .active {
                        try await self.flush()
                        let data = try await self.request("commands")
                        let commands = try JSONDecoder().decode(InAppCommands.self, from: data)
                        if let id = self.runID, commands.run?.id != id { self.interrupt("RUN_CANCELLED") }
                        if commands.state == "active", let run = commands.run, run.state == "queued", self.runID == nil { try await self.render(run.id) }
                    }
                } catch InAppError.server(let status) where status == 401 { await self.end(); return }
                catch { self.diagnostic("TEST_NETWORK_ERROR") }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    private func flush() async throws {
        while let e = events.first {
            do { _ = try await request("runs/\(e.run)/events", body: ["event_id": e.id, "kind": e.kind, "detail": e.detail]) }
            catch InAppError.server(let status) where status == 409 || status == 404 { }
            if events.first?.id == e.id { events.removeFirst() }
        }
    }
    private func render(_ id: String) async throws {
        guard allowed(), let presenter = host(), presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
        let current = generation
        let data = try await request("runs/\(id)/claim", body: [:])
        do {
            let artifact = try JSONDecoder().decode(InAppArtifact.self, from: data); try artifact.validate()
            guard current == generation, allowed(), UIApplication.shared.applicationState == .active else { queue(id, "failed", "HOST_BLOCKED"); return }
            runID = id
            let controller = InAppViewController(artifact: artifact, allowedSchemes: config.allowedURLSchemes, allowedHosts: config.allowedWebHosts)
            controller.onReady = { [weak self, weak controller, weak presenter] in
                guard let self, let controller, let presenter, self.runID == id, current == self.generation,
                      self.allowed(), UIApplication.shared.applicationState == .active, presenter.viewIfLoaded?.window != nil,
                      presenter.presentedViewController == nil else { self?.interrupt("HOST_BLOCKED"); controller?.close(); return }
                presenter.present(controller, animated: false) { [weak self] in
                    self?.queue(id, "presented"); controller.markPresented()
                }
            }
            controller.onEvent = { [weak self] kind, detail in self?.queue(id, kind, detail) }
            controller.onEnd = { [weak self] action in
                guard let self, self.runID == id else { return }; self.rendering = nil; self.runID = nil
                if let action { self.action(action) }
            }
            rendering = controller; controller.loadViewIfNeeded()
        } catch { queue(id, "failed", "INVALID_ARTIFACT"); throw error }
    }
    private func request(_ path: String, body: [String: String]? = nil, token: String? = nil) async throws -> Data {
        var req = URLRequest(url: config.apiURL.appendingPathComponent("v1/in-app/test/\(path)"))
        req.httpMethod = body == nil ? "GET" : "POST"; req.timeoutInterval = 10
        req.setValue("Bearer \(config.sdkKey)", forHTTPHeaderField: "Authorization")
        req.setValue(token ?? credential, forHTTPHeaderField: "X-NudgeOn-Test-Token")
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InAppError.server((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard data.count <= 40 * 1024 * 1024 else { throw InAppError.invalidArtifact }; return data
    }
}
private final class InAppNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif
