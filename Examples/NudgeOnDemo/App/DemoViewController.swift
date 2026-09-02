import NudgeOnSDK
import UIKit

/// SDK 공개 API를 직접 호출해 보는 programmatic UIKit 화면.
final class DemoViewController: UIViewController {
    private let externalIDField: UITextField = {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.placeholder = "external_id"
        field.text = "sample-user-123"
        field.accessibilityIdentifier = "external-id-field"
        return field
    }()

    private let identityLabel = DemoViewController.makeValueLabel()
    private let pushStateLabel = DemoViewController.makeValueLabel()
    private let deepLinkLabel = DemoViewController.makeValueLabel()
    private let activityLabel = DemoViewController.makeValueLabel()
    private let serviceOptInSwitch = UISwitch()
    private var activityObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "NudgeOn UIKit Demo"
        navigationController?.navigationBar.prefersLargeTitles = true
        view.backgroundColor = .systemGroupedBackground

        configureLayout()
        configureActions()
        renderActivity()
        refreshIdentity()
        refreshPushState()

        activityObserver = NotificationCenter.default.addObserver(
            forName: .demoActivityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.renderActivity()
        }
    }

    deinit {
        if let activityObserver {
            NotificationCenter.default.removeObserver(activityObserver)
        }
    }

    private func configureLayout() {
        let configuration = AppDelegate.configuration
        let configDescription = makeTextLabel(
            "SDK key: \(configuration.sdkKey)\nAPI host: \(configuration.apiHost.absoluteString)\n" +
            "Default values are safe samples; configure them before testing a real backend.",
            style: .footnote
        )

        let identifyButton = makeButton("Identify user", identifier: "identify-button") { [weak self] in
            self?.identifyUser()
        }
        let resetButton = makeButton("Reset local identity", identifier: "reset-button", destructive: true) {
            NudgeOn.reset()
            DemoActivityCenter.shared.record(
                "Local identity/token cache reset requested asynchronously; refresh IDs later to read it again"
            )
        }
        let identityButtons = makeHorizontalStack([identifyButton, resetButton])
        let refreshIdentityButton = makeButton("Refresh IDs", identifier: "refresh-identity-button") { [weak self] in
            self?.refreshIdentity()
            DemoActivityCenter.shared.record("Read the current local identity snapshot")
        }

        let trackButton = makeButton("Track product_viewed", identifier: "track-button") {
            NudgeOn.track("product_viewed", properties: ["product_id": "P-1", "price": 12_900])
            DemoActivityCenter.shared.record("product_viewed queued locally; server receipt is not confirmed")
        }
        let checkoutButton = makeButton("Track checkout + flush", identifier: "flush-button") {
            NudgeOn.track("checkout_started", properties: ["cart_value": 39_000])
            NudgeOn.flush()
            DemoActivityCenter.shared.record("checkout_started queued and flush requested; server receipt is not confirmed")
        }
        let attributesButton = makeButton("Set user attributes", identifier: "attributes-button") {
            NudgeOn.setUserAttributes(["vip_level": .number(3), "nickname": .string("sample")])
            DemoActivityCenter.shared.record("User attribute update requested; call identify first")
        }

        let pushButton = makeButton("Request push permission", identifier: "push-permission-button") { [weak self] in
            self?.requestPushPermission()
        }
        let provisionalButton = makeButton("Request provisional", identifier: "provisional-push-button") { [weak self] in
            self?.requestPushPermission(provisional: true)
        }
        let refreshPushButton = makeButton("Refresh push state", identifier: "refresh-push-button") { [weak self] in
            self?.refreshPushState()
        }

        let optInTitle = makeTextLabel("Local service opt-in", style: .body)
        let optInRow = UIStackView(arrangedSubviews: [optInTitle, UIView(), serviceOptInSwitch])
        optInRow.axis = .horizontal
        optInRow.alignment = .center
        serviceOptInSwitch.accessibilityIdentifier = "service-opt-in-switch"

        let deepLinkButton = makeButton("Open nudgeondemo://product/P-1", identifier: "deep-link-button") { [weak self] in
            self?.openDemoDeepLink()
        }

        let content = UIStackView(arrangedSubviews: [
            makeHeader(),
            makeSection(title: "Configuration", views: [configDescription]),
            makeSection(
                title: "Identity",
                views: [externalIDField, identityButtons, refreshIdentityButton, identityLabel]
            ),
            makeSection(title: "Events", views: [trackButton, checkoutButton, attributesButton]),
            makeSection(
                title: "Push lifecycle",
                views: [pushButton, provisionalButton, refreshPushButton, optInRow, pushStateLabel]
            ),
            makeSection(title: "Deep link lifecycle", views: [deepLinkButton, deepLinkLabel]),
            makeSection(title: "Last SDK activity", views: [activityLabel]),
        ])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func configureActions() {
        serviceOptInSwitch.addAction(UIAction { action in
            guard let toggle = action.sender as? UISwitch else { return }
            NudgeOn.setPushSubscription(toggle.isOn)
            DemoActivityCenter.shared.record(
                "Local service opt-in change requested: \(toggle.isOn); use Refresh push state to read it later"
            )
        }, for: .valueChanged)
    }

    private func identifyUser() {
        view.endEditing(true)
        let externalID = externalIDField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !externalID.isEmpty else {
            DemoActivityCenter.shared.record("Enter a non-empty external_id")
            return
        }
        NudgeOn.identify(externalId: externalID)
        DemoActivityCenter.shared.record(
            "identify(\(externalID)) requested asynchronously; wait before tracking attribution-sensitive events"
        )
    }

    private func requestPushPermission(provisional: Bool = false) {
        DemoActivityCenter.shared.record("Requesting \(provisional ? "provisional" : "standard") notification permission")
        Task { [weak self] in
            let result = await NudgeOn.registerForPush(provisional: provisional)
            DemoActivityCenter.shared.record(
                "OS permission result: \(result.rawValue); APNs token/server registration may still be pending"
            )
            await self?.refreshPushStateAsync()
        }
    }

    private func refreshPushState() {
        Task { [weak self] in
            await self?.refreshPushStateAsync()
        }
    }

    private func refreshPushStateAsync() async {
        let state = await NudgeOn.getPushSubscription()
        await MainActor.run { [weak self] in
            self?.serviceOptInSwitch.setOn(state.serviceOptIn, animated: true)
            self?.pushStateLabel.text = [
                "OS permission: \(state.osPermission)",
                "Last read local service opt-in: \(state.serviceOptIn)",
                "Token registration cache: \(state.tokenRegistered)",
                "These values do not prove provider delivery or server-side unsubscribe.",
            ].joined(separator: "\n")
        }
    }

    private func refreshIdentity() {
        identityLabel.text = [
            "device_id: \(NudgeOn.getDeviceId() ?? "-")",
            "anon_id: \(NudgeOn.getAnonId() ?? "-")",
        ].joined(separator: "\n")
    }

    private func renderActivity() {
        let snapshot = DemoActivityCenter.shared.snapshot
        deepLinkLabel.text = snapshot.lastDeepLink
        activityLabel.text = snapshot.lastActivity
    }

    private func openDemoDeepLink() {
        guard let url = URL(string: "nudgeondemo://product/P-1") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                DemoActivityCenter.shared.record("Custom URL could not be opened")
            }
        }
    }

    private func makeHeader() -> UIView {
        let title = makeTextLabel("Exercise the public SDK surface", style: .title2)
        title.font = .preferredFont(forTextStyle: .title2).bold()
        let subtitle = makeTextLabel(
            "Calls are intentionally explicit so AppDelegate, token, notification, and deep-link wiring stay visible.",
            style: .body
        )
        subtitle.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func makeSection(title: String, views: [UIView]) -> UIView {
        let titleLabel = makeTextLabel(title, style: .headline)
        let stack = UIStackView(arrangedSubviews: [titleLabel] + views)
        stack.axis = .vertical
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.backgroundColor = .secondarySystemGroupedBackground
        stack.layer.cornerRadius = 14
        return stack
    }

    private func makeButton(
        _ title: String,
        identifier: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.baseForegroundColor = destructive ? .systemRed : .systemBlue
        configuration.buttonSize = .medium
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = identifier
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeHorizontalStack(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        return stack
    }

    private func makeTextLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private static func makeValueLabel() -> UILabel {
        let label = UILabel()
        label.font = .monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
            weight: .regular
        )
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        return label
    }
}

private extension UIFont {
    func bold() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
