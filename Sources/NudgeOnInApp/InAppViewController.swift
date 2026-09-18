#if canImport(UIKit)
import UIKit
import WebKit

@MainActor final class InAppViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    var onReady: (() -> Void)?
    var onEvent: ((String, String) -> Void)?
    var onEnd: ((InAppAction?) -> Void)?
    private let artifact: InAppArtifact, nonce = UUID().uuidString
    private let showHideToday: Bool
    private let autoDismissSeconds: TimeInterval?
    private var autoDismiss: Task<Void, Never>?
    private var fullscreen: Bool { autoDismissSeconds != nil || artifact.manifest.display.type == "fullscreen" }
    private let allowedSchemes: Set<String>, allowedHosts: Set<String>
    private var web: WKWebView!
    private var loader: InAppSchemeHandler!
    private var presented = false, ended = false, ready = false, impression = false, actionTaken = false
    private var watchdog: Task<Void, Never>?, impressionTask: Task<Void, Never>?
    private var replies: [String: String] = [:]
    private let contentURL = URL(string: "nudgeon-content://bundle/index.html")!
    init(artifact: InAppArtifact, allowedSchemes: Set<String>, allowedHosts: Set<String>, showHideToday: Bool = false, autoDismissSeconds: TimeInterval? = nil) {
        self.autoDismissSeconds = autoDismissSeconds
        self.showHideToday = showHideToday
        self.artifact = artifact; self.allowedSchemes = allowedSchemes; self.allowedHosts = allowedHosts
        super.init(nibName: nil, bundle: nil); modalPresentationStyle = .overFullScreen
    }
    required init?(coder: NSCoder) { nil }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = fullscreen ? .black : UIColor.black.withAlphaComponent(artifact.manifest.display.backdrop_opacity)
        view.accessibilityViewIsModal = true
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        loader = InAppSchemeHandler(html: artifact.html); config.setURLSchemeHandler(loader, forURLScheme: "nudgeon-content")
        config.userContentController.add(self, name: "nudgeon")
        web = WKWebView(frame: .zero, configuration: config); web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear; web.navigationDelegate = self; web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        let safe = view.safeAreaLayoutGuide
        let display = fullscreen ? "fullscreen" : artifact.manifest.display.type
        var layout: [NSLayoutConstraint] = []
        if display == "fullscreen" {
            // The document paints every pixel; native escape controls remain inside the safe area.
            layout = [web.leadingAnchor.constraint(equalTo: view.leadingAnchor), web.trailingAnchor.constraint(equalTo: view.trailingAnchor), web.topAnchor.constraint(equalTo: view.topAnchor), web.bottomAnchor.constraint(equalTo: view.bottomAnchor)]
        } else {
            layout = [web.leadingAnchor.constraint(equalTo: safe.leadingAnchor), web.trailingAnchor.constraint(equalTo: safe.trailingAnchor)]
        }
        if display == "fullscreen" {
            web.isOpaque = true; web.backgroundColor = .black; web.scrollView.backgroundColor = .black
        } else if display == "bottom" {
            layout += [web.bottomAnchor.constraint(equalTo: safe.bottomAnchor), web.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: 0.65)]
        } else if display == "modal" {
            layout += [web.centerYAnchor.constraint(equalTo: safe.centerYAnchor, constant: 22), web.heightAnchor.constraint(equalTo: safe.heightAnchor, multiplier: 0.8)]
        } else {
            layout += [web.topAnchor.constraint(equalTo: safe.topAnchor, constant: 44), web.bottomAnchor.constraint(equalTo: safe.bottomAnchor)]
        }
        NSLayoutConstraint.activate(layout)
        if autoDismissSeconds == nil {
            let close = UIButton(type: .system); close.setTitle("✕", for: .normal); close.setTitleColor(.white, for: .normal)
            close.backgroundColor = UIColor.black.withAlphaComponent(0.65); close.layer.cornerRadius = 22; close.accessibilityLabel = NSLocalizedString("Close event", comment: "In-app event close")
            close.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(close)
            NSLayoutConstraint.activate([close.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12), close.topAnchor.constraint(equalTo: safe.topAnchor), close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)])
            close.addTarget(self, action: #selector(userClose), for: .touchUpInside)
            if showHideToday {
                let hide = UIButton(type: .system); hide.setTitle(NSLocalizedString("Hide today", comment: "In-app suppression"), for: .normal)
                hide.setTitleColor(.white, for: .normal); hide.backgroundColor = UIColor.black.withAlphaComponent(0.65)
                hide.accessibilityHint = "Until midnight (\(artifact.time_zone ?? "UTC"))"
                hide.layer.cornerRadius = 12; hide.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(hide)
                NSLayoutConstraint.activate([hide.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12), hide.topAnchor.constraint(equalTo: safe.topAnchor), hide.heightAnchor.constraint(equalToConstant: 44), hide.widthAnchor.constraint(equalToConstant: 190)])
                hide.addTarget(self, action: #selector(hideToday), for: .touchUpInside)
            }
        }
        web.load(URLRequest(url: contentURL))
        watchdog = Task { [weak self] in try? await Task.sleep(nanoseconds: 5_000_000_000); guard !Task.isCancelled, let self, !self.presented else { return }; self.fail("CONTENT_TIMEOUT") }
    }
    func markPresented() {
        guard !ended else { return }; presented = true; watchdog?.cancel()
        watchdog = Task { [weak self] in try? await Task.sleep(nanoseconds: 290_000_000_000); guard !Task.isCancelled else { return }; self?.fail("RUN_EXPIRED") }
        if let seconds = autoDismissSeconds {
            autoDismiss = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.recordImpression(); self.finish(reason: "auto_dismiss")
            }
        }
        impressionTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled, let self, self.view.window != nil, UIApplication.shared.applicationState == .active else { return }; self.recordImpression() }
    }
    private func recordImpression() { if presented && !ended && !impression { impression = true; onEvent?("impression", "") } }
    @objc private func hideToday() {
        guard presented && !ended && showHideToday else { return }
        recordImpression(); onEvent?("hide_today", ""); finish(reason: "hide_today")
    }
    @objc private func userClose() { finish(reason: "close_button") }
    override func accessibilityPerformEscape() -> Bool { userClose(); return true }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) { super.viewWillTransition(to: size, with: coordinator); finish(reason: "host_changed") }
    func close() {
        guard !ended else { return }; ended = true; watchdog?.cancel(); impressionTask?.cancel(); autoDismiss?.cancel()
        web?.stopLoading(); web?.configuration.userContentController.removeScriptMessageHandler(forName: "nudgeon"); web?.navigationDelegate = nil
        if presentingViewController != nil { dismiss(animated: false) }; onReady = nil; onEvent = nil; onEnd = nil
    }
    private func fail(_ code: String) { guard !ended else { return }; onEvent?("failed", code); let callback = onEnd; close(); callback?(nil) }
    private func finish(reason: String, action: InAppAction? = nil) {
        guard !ended else { return }; onEvent?("dismiss", reason); let callback = onEnd
        // Ensure navigation runs after the overlay has been dismissed.
        ended = true; watchdog?.cancel(); impressionTask?.cancel(); autoDismiss?.cancel(); web.stopLoading(); web.configuration.userContentController.removeScriptMessageHandler(forName: "nudgeon"); web.navigationDelegate = nil
        onReady = nil; onEvent = nil; onEnd = nil
        if presentingViewController != nil { dismiss(animated: false) { callback?(action) } } else { callback?(action) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !ended else { return }; onEvent?("bridge_ready", "")
        let contextData = try? JSONSerialization.data(withJSONObject: ["time_zone": artifact.time_zone ?? "UTC"])
        let context = contextData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        web.evaluateJavaScript("window.__nudgeonConnect('\(artifact.id)','\(nonce)',\(context))") { [weak self] _, error in if error != nil { Task { @MainActor in self?.fail("BRIDGE_ERROR") } } }
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(!ended && !ready && action.targetFrame?.isMainFrame == true && action.request.url == contentURL ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail("WEBVIEW_ERROR") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail("WEBVIEW_ERROR") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("WEBVIEW_TERMINATED") }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !ended, message.frameInfo.isMainFrame, message.frameInfo.request.url == contentURL,
              let body = message.body as? String, body.utf8.count <= 8192,
              let data = body.data(using: .utf8), let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              m["protocol"] as? Int == 1, m["execution_id"] as? String == artifact.id, m["nonce"] as? String == nonce,
              let id = m["request_id"] as? String, id.count <= 64, replies.count < 200, let method = m["method"] as? String else { return }
        if let reply = replies[id] { web.evaluateJavaScript(reply); return }
        let payload = m["payload"] as? [String: Any] ?? [:]
        if method == "ready" { respond(id); if !ready { ready = true; onEvent?("content_ready", ""); onReady?() }; return }
        if method == "log" { onEvent?("log", "JS_ERROR"); respond(id); return }
        guard presented else { respond(id, error: "NOT_PRESENTED"); return }
        if method == "hideToday" {
            guard showHideToday else { respond(id, error: "LIVE_CAMPAIGN_REQUIRED"); return }
            respond(id); hideToday(); return
        }
        if method == "dismiss" { respond(id); finish(reason: "html_close"); return }
        guard method == "performAction", let actionID = payload["action_id"] as? String, let action = artifact.manifest.actions[actionID], !actionTaken else { respond(id, error: "ACTION_NOT_ALLOWED"); return }
        if action.type == "deep_link" || action.type == "open_url" {
            guard let text = action.url, let url = URL(string: text), let scheme = url.scheme?.lowercased(), url.user == nil, url.password == nil,
                  (action.type == "open_url" ? scheme == "https" && allowedHosts.contains(url.host?.lowercased() ?? "") : allowedSchemes.contains(scheme) && !["file","data","javascript","http","https","intent"].contains(scheme)) else { respond(id, error: "ACTION_NOT_ALLOWED"); return }
        } else if !["copy","dismiss"].contains(action.type) { respond(id, error: "ACTION_NOT_ALLOWED"); return }
        actionTaken = true; recordImpression(); onEvent?("action", actionID); respond(id)
        if action.type == "copy" { UIPasteboard.general.string = action.text; actionTaken = false; return }
        finish(reason: "action", action: action.type == "dismiss" ? nil : action)
    }
    private func respond(_ id: String, error: String? = nil) {
        let result: [String: Any] = error.map { ["request_id":id,"ok":false,"error":["code":$0]] } ?? ["request_id":id,"ok":true]
        guard let data = try? JSONSerialization.data(withJSONObject: result), let json = String(data: data, encoding: .utf8) else { return }
        let js = "window.__nudgeonReply(\(json))"; replies[id] = js; web.evaluateJavaScript(js)
    }
}
private final class InAppSchemeHandler: NSObject, WKURLSchemeHandler {
    private let data: Data
    init(html: String) { data = Data(html.utf8) }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard task.request.url?.absoluteString == "nudgeon-content://bundle/index.html" else { task.didFailWithError(URLError(.resourceUnavailable)); return }
        task.didReceive(URLResponse(url: task.request.url!, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8")); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { }
}
#endif
