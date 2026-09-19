# In-app module (0.2.5)

`NudgeOnInApp` is an optional iOS 15+ Swift Package product. Available starting with SDK 0.2.0. It connects to the NudgeOn platform's in-app source workbench; it does not automatically display production campaigns.

Keep one `InAppTestClient` owned by your app. Provide an HTTPS API URL and SDK key, the active scene's host controller, an explicit `isAllowed` policy, and URL scheme/HTTPS host allow lists. In `onAction`, route the validated URL with your existing app router. The overlay is dismissed before routing.

```swift
import NudgeOnInApp
let client = try InAppTestClient(
    configuration: .init(apiURL: apiURL, sdkKey: sdkKey,
                         allowedURLSchemes: ["myapp"], allowedWebHosts: ["example.com"]),
    host: { activeViewController },
    isAllowed: { mayShowEvent },
    onAction: { action in /* route action.url */ },
    onTransferStatus: { status in /* update receipt UI using status.phase and pendingCount */ }
)
// App-owned debug/settings action, after the person requests a test:
client.presentConnection(from: activeViewController)
```

The console creates a pairing code. Paste it into this native connection UI, compare the six-digit number, confirm in the console, and keep the app open. Connection lasts 30 minutes. Pending telemetry and its credential are protected in Keychain; restart recovers delivery only and requires new pairing for further review. Call `contextChanged()` for identity, consent or host-screen changes and `await end()` to disconnect.

The shared artifact uses SHA-256 verification, network-restricted HTML and registered action IDs. Native close, accessibility escape, rotation, background transitions and a five-minute watchdog can dismiss without JavaScript permission. No push permission is required. Uploaded HTML never receives the SDK key or pairing credential.

Platform setup, supported source formats, API contracts and known first-version limits are documented in `nudgeon-platform/docs-public/IN-APP-WORKBENCH.md`. Browser previews and macOS contract tests do not replace iOS device testing.

## Reliable review delivery (0.2.5)

Create and retain one test client per API URL + SDK key on the main thread, including after app restart, to recover pending records. A second simultaneous owner is rejected. Constructor storage errors must be surfaced; do not report a successful review when protected storage is unavailable.

`onTransferStatus` runs on the main thread and reports `phase`, `pendingCount`, `acknowledgedCount`, `reason`, and `canEndSafely`. Show **waiting → sending → server confirmed**, or **failed** with retry. Acknowledged counts refer to this test session's accepted telemetry, not review approval. Native Close is still required for the normal content-review path; approve the matching revision/platform in the console separately.

- `end()` stops presentation, persists closure, sends all queued records, then ends the server session. It does not discard failed records. Monitor status rather than treating return from `end()` as a receipt.
- `retryPendingEvents()` retries uploads/storage only. It never presents an ad. Automatic transient retries back off from 1 to 30 seconds while the process can run; the OS may suspend background work.
- `discardPendingEvents()` deliberately deletes pending telemetry and attempts to end the old session. Require an explicit user choice; discard never counts as acknowledgement. Perform a new review after abandonment.
- The encrypted snapshot holds at most 200 records (one slot reserved for interruption). IDs survive lost responses and restart, allowing server deduplication. Pairing codes are not stored; the short-lived credential is retained only to finish uploads/closure.
- On restart, an interrupted active run gets one `failed / PROCESS_RESTARTED` record. Rendering and command polling do not resume. Finish recovery or explicitly discard before pairing again.
- The server's 30-minute test credential and five-minute active-run lease still apply. Expired/revoked sessions and cancelled/expired runs can reject delayed records. Permanent HTTP 400/401/403/404/409/410/422, queue-full and storage failures are shown as failures, never successful receipts. Start a new review after resolving/discarding these records. Durable storage does not extend server validity.
- No guarantee covers events before a successful storage write, app uninstall, explicit discard, or a server that has already invalidated the review. Production campaign telemetry has a separate contract below.

## 운영 캠페인 모듈 (0.2.0)

`InAppCampaignClient`는 테스트 페어링 없이 게시된 공개 콘텐츠를 조회합니다. 설치 자격은 기기 보호 저장소에 보관하고, 기간·트리거·빈도 제한을 서버에서 확인합니다. 호스트가 표시 허용, 화면/이벤트, 계정·동의 변경을 연결해야 합니다.

자세한 설정과 양쪽 SDK 예시는 플랫폼의 [캠페인 사용 안내](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/IN-APP-CAMPAIGNS.md)에 있습니다. 플랫폼은 인앱 API와 migration 0010–0012가 포함된 버전이 필요합니다. 테스트 모드를 열 때 운영 클라이언트를 disable하세요.

## Durable campaign telemetry

Live campaign events are written atomically to an installation-scoped journal before sending (up to 1,000 records, seven-day retention). They replay in order with stable event IDs after restart; transient failures use exponential backoff up to 60 seconds plus jitter. The server accepts historical events for seven days without reopening an expired or paused delivery. Permanent 400/404/409 responses discard that event; 401 disables the client without rotating installation identity. Storage failures emit `EVENT_STORAGE_FAILED`. `forgetInstallation` clears the journal. Test-pairing delivery is protected separately as described above; new commands require reconnecting after restart.

Add the `NudgeOnInApp` product to your app target in Xcode (package version 0.2.0 or later).

## HTML 안의 오늘 하루 안 보기 (0.2.1+)

업데이트한 NudgeOn 서버에서 저장한 소스는 `window.nudgeonBridge.hideToday()`를 호출할 수 있습니다. 표시 중인 라이브 캠페인에서 impression → hide_today → dismiss(hide_today)를 기록하고 닫습니다. 동일 설치·캠페인을 캠페인 시간대의 다음 자정까지 제외합니다. SDK 0.2.2와 업데이트한 서버에서 `Asia/Seoul`을 설정하면 한국 시간 자정이며, 기존 설정의 기본값은 UTC입니다. 별도 manifest 액션 등록은 필요 없습니다.

테스트 연결 모드에서는 `LIVE_CAMPAIGN_REQUIRED`로 거절하고 팝업을 유지합니다. 콘솔 미리보기에서는 모의 실행임을 표시합니다. 기존 SDK 0.2.0은 HTML 호출을 지원하지 않으므로 0.2.1 이상이 필요합니다. 일반 `dismiss()`는 오늘 하루 숨김을 적용하지 않습니다.

## 캠페인 시간대·정상 중단 (0.2.2+)

서버·콘솔을 먼저 업데이트한 뒤 SDK를 적용하세요. SDK는 `campaign-time-zone` capability를 보내고, 불변 게시 버전의 시간대를 네이티브 숨김 안내 및 HTML 브리지에 전달합니다. 새 서버에서 다시 저장한 소스의 `window.nudgeonBridge.timeZone`은 읽기 전용이며, 구 소스/서버의 기본값은 UTC입니다. UTC 외 캠페인은 0.2.2 이상에만 표시됩니다. API에서 시간대를 생략한 기존 캠페인은 UTC를 유지합니다.

라이브 캠페인의 백그라운드·화면/세션/표시 조건 변경·비활성화·서버 중지·기간 만료는 `cancelled`와 사유로 전송하며 실제 렌더링/통신 오류는 `failed`로 유지합니다. 구 서버에서는 표시 후 정상 종료를 `dismiss`, 표시 전 중단을 `failed(HOST_BLOCKED)`로 보내 호환성을 유지합니다. 테스트 연결의 로그와는 별도입니다.

검증: iPhone 15 Pro/iOS 27 및 Fold3/Android 15에서 KST 숨김 만료·실제 자정 후 재노출, 정상 중단, 수정 예제 레이아웃 확인. [플랫폼 검증 기록](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/IN-APP-DEVICE-QA-2026-09-17.md)을 참고하세요.
