# In-app module (0.2.0)

`NudgeOnInApp` is an optional iOS 15+ Swift Package product. Available starting with SDK 0.2.0. It connects to the NudgeOn platform's in-app source workbench; it does not automatically display production campaigns.

Keep one `InAppTestClient` owned by your app. Provide an HTTPS API URL and SDK key, the active scene's host controller, an explicit `isAllowed` policy, and URL scheme/HTTPS host allow lists. In `onAction`, route the validated URL with your existing app router. The overlay is dismissed before routing.

```swift
import NudgeOnInApp
let client = try InAppTestClient(
    configuration: .init(apiURL: apiURL, sdkKey: sdkKey,
                         allowedURLSchemes: ["myapp"], allowedWebHosts: ["example.com"]),
    host: { activeViewController },
    isAllowed: { mayShowEvent },
    onAction: { action in /* route action.url */ }
)
// App-owned debug/settings action, after the person requests a test:
client.presentConnection(from: activeViewController)
```

The console creates a pairing code. Paste it into this native connection UI, compare the six-digit number, confirm in the console, and keep the app open. Connection lasts 30 minutes. Credentials remain in memory; restarting requires pairing again. Call `contextChanged()` for identity, consent or host-screen changes and `await end()` to disconnect.

The shared artifact uses SHA-256 verification, network-restricted HTML and registered action IDs. Native close, accessibility escape, rotation, background transitions and a five-minute watchdog can dismiss without JavaScript permission. No push permission is required. Uploaded HTML never receives the SDK key or pairing credential.

Platform setup, supported source formats, API contracts and known first-version limits are documented in `nudgeon-platform/docs-public/IN-APP-WORKBENCH.md`. Browser previews and macOS contract tests do not replace iOS device testing.

## 운영 캠페인 모듈 (0.2.0)

`InAppCampaignClient`는 테스트 페어링 없이 게시된 공개 콘텐츠를 조회합니다. 설치 자격은 기기 보호 저장소에 보관하고, 기간·트리거·빈도 제한을 서버에서 확인합니다. 호스트가 표시 허용, 화면/이벤트, 계정·동의 변경을 연결해야 합니다.

자세한 설정과 양쪽 SDK 예시는 플랫폼의 [캠페인 사용 안내](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/IN-APP-CAMPAIGNS.md)에 있습니다. 플랫폼은 인앱 API와 migration 0010–0012가 포함된 버전이 필요합니다. 테스트 모드를 열 때 운영 클라이언트를 disable하세요.

## Durable campaign telemetry

Live campaign events are written atomically to an installation-scoped journal before sending (up to 1,000 records, seven-day retention). They replay in order with stable event IDs after restart; transient failures use exponential backoff up to 60 seconds plus jitter. The server accepts historical events for seven days without reopening an expired or paused delivery. Permanent 400/404/409 responses discard that event; 401 disables the client without rotating installation identity. Storage failures emit `EVENT_STORAGE_FAILED`. `forgetInstallation` clears the journal. Test-pairing sessions remain memory-only and require reconnecting after restart.

Add the `NudgeOnInApp` product to your app target in Xcode (package version 0.2.0 or later).
