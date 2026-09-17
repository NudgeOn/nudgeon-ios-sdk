#if canImport(UIKit)
import UIKit

/// Public, non-personalized campaigns. Explicit enable and host eligibility are required.
@MainActor public final class InAppCampaignClient {
    public typealias Configuration = InAppTestClient.Configuration
    private let config: Configuration, store: InAppInstallationStore
    private let host: () -> UIViewController?, allowed: () -> Bool, action: (InAppAction) -> Void, diagnostic: (String) -> Void
    private let network = URLSession(configuration: .ephemeral, delegate: InAppCampaignNoRedirect(), delegateQueue: nil)
    private var credential: String?, renderer: InAppViewController?, delivery: String?
    private var shown = false, lifecycleEvents = false
    private var enabled = false, busy = false, generation = UUID(), sessionID = UUID()
    private var polling: Task<Void, Never>?, expiry: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var journal: InAppEventJournal?
    private var retryAt = Date.distantPast, failures = 0
    public init(configuration: Configuration, host: @escaping () -> UIViewController?, isAllowed: @escaping () -> Bool,
                onAction: @escaping (InAppAction) -> Void, onDiagnostic: @escaping (String) -> Void = { _ in }) throws {
        let u = configuration.apiURL
        guard u.scheme == "https" || (u.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(u.host ?? "")),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil else { throw InAppError.invalidServer }
        config = configuration; self.host = host; allowed = isAllowed; action = onAction; diagnostic = onDiagnostic
        store = InAppInstallationStore(account: InAppArtifact.sha256(u.absoluteString + "|" + configuration.sdkKey))
        credential = try store.read()
        if let credential { journal = try makeJournal(credential) }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.stop("background") } })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.foreground() } })
    }
    deinit { polling?.cancel(); expiry?.cancel(); observers.forEach(NotificationCenter.default.removeObserver); network.invalidateAndCancel() }
    public func enable() { guard !enabled else { return }; enabled = true; startPolling(); foreground() }
    public func disable() { enabled = false; stop("disabled"); polling?.cancel(); polling = nil; Task { try? await self.flush() } }
    /// Call on logout, identity or consent changes. Installation frequency survives identity changes.
    public func contextChanged() { stop("context_changed") }
    private func stop(_ reason: String, failure: Bool = false) {
        generation = UUID()
        if let id = delivery {
            let event = InAppTermination.event(reason: reason, failure: failure, shown: shown, lifecycleEvents: lifecycleEvents)
            queue(id, event.kind, event.detail)
        }
        shown = false; renderer?.close(); renderer = nil; delivery = nil; expiry?.cancel(); expiry = nil
    }
    public func foreground() { guard enabled else { return }; stop("session_ended"); sessionID = UUID(); trigger(["type": "foreground"]) }
    public func screen(_ name: String) { stop("screen_changed"); trigger(["type": "screen", "name": name]) }
    public func track(_ name: String) { trigger(["type": "event", "name": name]) }
    /// Explicit opt-out: revoke this installation and remove its local credential. Does not rotate automatically on HTTP 401.
    public func forgetInstallation() async {
        disable(); _ = try? await request("revoke", body: [:]); credential = nil; store.clear(); try? journal?.clear(); journal = nil
    }
    private func trigger(_ trigger: [String: String]) {
        guard enabled, allowed(), !busy, renderer == nil, UIApplication.shared.applicationState == .active,
              let presenter = host(), presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else { return }
        busy = true; let current = generation, session = sessionID
        Task { [weak self, weak presenter] in
            guard let self else { return }; defer { self.busy = false }
            do {
                if self.credential == nil {
                    let data = try await self.request("installations", body: ["platform": "ios"])
                    let value = try JSONDecoder().decode(Registration.self, from: data)
                    guard self.enabled, current == self.generation else { return }
                    let journal = try self.makeJournal(value.credential)
                    try self.store.write(value.credential); self.credential = value.credential; self.journal = journal
                }
                try await self.flush()
                let data = try await self.request("decisions", body: ["request_key": UUID().uuidString, "session_id": session.uuidString, "trigger": trigger])
                guard let artifact = try JSONDecoder().decode(Decision.self, from: data).delivery else { return }
                guard self.enabled, self.allowed(), current == self.generation, let presenter else { self.queue(artifact.id, artifact.lifecycle_events == true ? "cancelled" : "failed", artifact.lifecycle_events == true ? "host_blocked" : "HOST_BLOCKED"); return }
                self.delivery = artifact.id; self.lifecycleEvents = artifact.lifecycle_events == true; try artifact.validate()
                let controller = InAppViewController(artifact: artifact, allowedSchemes: self.config.allowedURLSchemes, allowedHosts: self.config.allowedWebHosts, showHideToday: true)
                controller.onEvent = { [weak self] kind, detail in
                    if kind == "failed" && detail == "RUN_EXPIRED" && artifact.lifecycle_events == true { self?.queue(artifact.id, "cancelled", "display_timeout") }
                    else { self?.queue(artifact.id, kind, detail) }
                }
                controller.onEnd = { [weak self] action in
                    guard let self, self.delivery == artifact.id else { return }; self.shown = false; self.renderer = nil; self.delivery = nil; self.expiry?.cancel()
                    if let action { self.action(action) }
                }
                controller.onReady = { [weak self, weak controller, weak presenter] in
                    Task { @MainActor in
                        guard let self, let controller else { return }
                        do {
                            let data = try await self.request("deliveries/\(artifact.id)/authorize", body: [:])
                            let authorization = try JSONDecoder().decode(Authorization.self, from: data)
                            guard self.delivery == artifact.id else { controller.close(); return }
                            guard self.enabled, self.allowed(), current == self.generation, self.delivery == artifact.id,
                                  UIApplication.shared.applicationState == .active, let presenter, presenter.viewIfLoaded?.window != nil,
                                  presenter.presentedViewController == nil else { self.stop("host_blocked"); return }
                            let seconds = Self.remaining(authorization.expires_at)
                            guard seconds > 0 else { self.stop("display_timeout"); return }
                            presenter.present(controller, animated: false) { [weak self] in
                                self?.shown = true; self?.queue(artifact.id, "presented"); controller.markPresented()
                            }
                            self.expiry = Task { [weak self] in try? await Task.sleep(nanoseconds: UInt64(min(seconds, 290) * 1_000_000_000)); guard !Task.isCancelled else { return }; self?.stop("display_timeout") }
                        } catch { if self.delivery == artifact.id { self.stop("DISPLAY_AUTHORIZATION_FAILED", failure: true) }; self.diagnostic("DISPLAY_AUTHORIZATION_FAILED") }
                    }
                }
                self.renderer = controller; controller.loadViewIfNeeded()
            } catch { if self.delivery != nil { self.stop("CAMPAIGN_REQUEST_FAILED", failure: true) }; self.diagnostic("CAMPAIGN_REQUEST_FAILED"); if case InAppError.server(401) = error { self.disable() } }
        }
    }
    private func queue(_ id: String, _ kind: String, _ detail: String = "") {
        do { try journal?.append(delivery: id, kind: kind, detail: detail) } catch { diagnostic("EVENT_STORAGE_FAILED") }; diagnostic("\(kind):\(detail)")
    }
    private func startPolling() {
        polling?.cancel(); polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.enabled else { return }
                if UIApplication.shared.applicationState == .active {
                    do { try await self.flush(); if self.shown, let id = self.delivery {
                        let data = try await self.request("deliveries/\(id)")
                        let state = try JSONDecoder().decode(Status.self, from: data)
                        if !state.active && self.renderer?.isViewLoaded == true { self.stop(state.reason ?? "delivery_inactive") }
                    }} catch { self.diagnostic("CAMPAIGN_SYNC_FAILED"); if case InAppError.server(401) = error { self.disable(); return } }
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
    private var flushing = false
    private func flush() async throws {
        guard !flushing, Date() >= retryAt else { return }; flushing = true; defer { flushing = false }
        do {
        while let e = journal?.events.first, credential != nil {
            do { _ = try await request("deliveries/\(e.delivery)/events", body: ["event_id": e.id, "kind": e.kind, "detail": e.detail, "occurred_at": e.occurredAt]) }
            catch InAppError.server(let status) where status == 400 || status == 404 || status == 409 { }
            try journal?.acknowledge(e.id)
        }
        failures = 0; retryAt = .distantPast
        } catch {
            failures = min(failures + 1, 6)
            retryAt = Date().addingTimeInterval(min(60, pow(2, Double(failures))) + Double.random(in: 0...1))
            throw error
        }
    }
    private func makeJournal(_ credential: String) throws -> InAppEventJournal {
        var directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("NudgeOnInApp", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return try InAppEventJournal(file: directory.appendingPathComponent(store.account + ".events.json"), owner: InAppArtifact.sha256(credential))
    }
    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: config.apiURL.appendingPathComponent("v1/in-app/live/\(path)")); req.httpMethod = body == nil ? "GET" : "POST"; req.timeoutInterval = 10
        req.setValue("campaign-time-zone", forHTTPHeaderField: "X-NudgeOn-In-App-Capabilities")
        req.setValue("Bearer \(config.sdkKey)", forHTTPHeaderField: "Authorization"); req.setValue(credential, forHTTPHeaderField: "X-NudgeOn-Installation")
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await network.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InAppError.server((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard data.count <= 40 * 1024 * 1024 else { throw InAppError.invalidArtifact }; return data
    }
    private static func remaining(_ value: String) -> TimeInterval {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)?.timeIntervalSinceNow ?? 0
    }
    private struct Registration: Decodable { let credential: String }
    private struct Decision: Decodable { let delivery: InAppArtifact? }
    private struct Authorization: Decodable { let expires_at: String }
    private struct Status: Decodable { let active: Bool; let reason: String? }
}
private final class InAppCampaignNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
#endif
