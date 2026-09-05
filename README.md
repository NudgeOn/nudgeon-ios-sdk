# NudgeOn iOS SDK

[![SPM](https://img.shields.io/github/v/release/NudgeOn/nudgeon-ios-sdk?label=Swift%20Package&sort=semver)](https://github.com/NudgeOn/nudgeon-ios-sdk/releases)
[![CI](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![status](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)

[NudgeOn](https://nudgeon.io) 고객 인게이지먼트 플랫폼의 iOS(Swift) 네이티브 코어 SDK.
이벤트를 수집하고 푸시를 수신합니다. Android SDK와 API가 동형입니다.

> ⚠️ **알파입니다. 프로덕션에 쓰지 마세요.**
> 코어 경로(init · identify · track · 오프라인 큐 · 푸시 등록 · 리스너 · NSE 도달)는 동작하지만,
> 아래가 아직 완료되지 않았습니다.
>
> - **`message_id` 연결** — 서버·iOS·Android가 푸시 payload에서 식별자를 읽는 방식이 아직 통일되지 않았습니다. 발송·도달·리포트 간 조인이 보장되지 않습니다
> - **수신 동의 · 로그아웃 · 토큰 소유권** 서버 동기화
> - **실기기 · 실공급자 발송 검증**
>
> API와 스키마는 예고 없이 바뀔 수 있습니다. 진행 상황은
> [출시 체크리스트](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)를 보세요.

- **플랫폼 저장소** — [NudgeOn/nudgeon-platform](https://github.com/NudgeOn/nudgeon-platform)
- **API 가이드** — [docs-public/API.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/API.md)
- **푸시 계약** — [docs-public/PUSH-CONTRACT.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/PUSH-CONTRACT.md)
- **개발자센터** — [nudgeon.io](https://nudgeon.io)

## 설치 (Swift Package Manager)

```swift
.package(url: "https://github.com/NudgeOn/nudgeon-ios-sdk.git", from: "0.1.0")
```

## 빠른 시작

```swift
import NudgeOnSDK

NudgeOn.initialize(config: NudgeOnConfig(
    sdkKey: "pk_...",
    apiHost: URL(string: "https://ingest.example.com")!  // 셀프호스팅 시 교체
))
NudgeOn.identify(externalId: "user-123")
NudgeOn.track("product_viewed", properties: ["product_id": "P-1", "price": 12900])
NudgeOn.setUserAttributes(["vip_level": .number(3), "nickname": .string("ethan")])
// 현재 로컬 identity/token cache reset. 서버 device detach/unsubscribe 완료를 뜻하지 않음
NudgeOn.reset()

// 푸시 (M2)
Task { let result = await NudgeOn.registerForPush() }   // granted | denied | provisional
NudgeOn.onPushOpened { payload in router.route(payload.deepLink) }  // 콜드 스타트 유실 없음
let initial = NudgeOn.getInitialPushPayload()           // 푸시로 앱이 열렸으면 payload
```

## 실행 가능한 UIKit 샘플

[`Examples/NudgeOnDemo`](Examples/NudgeOnDemo)는 programmatic UIKit 앱, AppDelegate/SceneDelegate 푸시·딥링크 연동,
Notification Service Extension, 로컬 Swift Package 참조, 단위 테스트가 포함된 Xcode 프로젝트다.

```bash
open Examples/NudgeOnDemo/NudgeOnDemo.xcodeproj
```

기본값은 안전한 `pk_sample_replace_me`와 로컬 API host다. 실제 key/host, App Group, signing 설정과
실기기 푸시 테스트 절차는 [샘플 README](Examples/NudgeOnDemo/README.md)를 먼저 확인한다.

## AppDelegate 연동 (수동 — 기본, 스위즐링 미채택)

```swift
func application(_ app: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    NudgeOn.setDeviceToken(token)               // 토큰 대사 → 서버 자동 등록/갱신
}
// UNUserNotificationCenterDelegate
func userNotificationCenter(_ c: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
    NudgeOn.handlePushOpened(response.notification.request.content.userInfo)  // 딥링크 라우팅
}
func userNotificationCenter(_ c: UNUserNotificationCenter,
        willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
    NudgeOn.handlePushReceived(n.request.content.userInfo)
    return [.banner, .sound]
}
```

## 도달 트래킹 (NSE — iOS 도달 지표 필수)

App Group을 코어 설정과 NSE에 공유하고, NSE는 베이스 클래스만 상속한다:

```swift
// 코어: NudgeOnConfig(sdkKey:, apiHost:, appGroup: "group.io.nudgeon.myapp")
import NudgeOnNotificationService
class NotificationService: NudgeOnNotificationServiceBase {
    override var appGroup: String? { "group.io.nudgeon.myapp" }
}
```
`$push_delivered` 전송 + `nudgeon.image_url` 리치 푸시 첨부를 자동 처리한다.
코어가 App Group에 설정과 함께 `anon_id`/`external_id`/`device_id`를 미러링(identify·reset 시 갱신)하고,
NSE는 이를 읽어 서버 수집 스키마(UUID `anon_id` 또는 `external_id` 필수)를 만족하는 이벤트만 보낸다.
미러링이 없으면(코어 초기화 전, App Group 불일치) 경고 로그를 남기고 전송을 건너뛴다.

## 아키텍처

- **네이티브 코어가 유일한 상태 보유자** — 오프라인 큐(파일 영속), anon/device ID 영속,
  배치 플러시, 재시도. 브리지(RN/Flutter)는 무상태 전달만.
- `NudgeOnSDK` (코어) + `NudgeOnNotificationService` (NSE — 도달 트래킹·rich push).

## 모듈

| 파일 | 역할 |
|---|---|
| `NudgeOn.swift` | 공개 API (initialize·identify·track·reset·flush) |
| `NudgeOnCore.swift` | 코어 오케스트레이터 (큐·네트워크·플러시 타이머) |
| `Identity.swift` | anon/external/device ID 영속 (reset 정책) |
| `EventQueue.swift` | 오프라인 영속 큐 (1000건 상한·oldest drop) |
| `Network.swift` | /v1/track·identify·devices/token 클라이언트 |
| `PushPayload.swift` | APNs userInfo 파싱·PushPermissionResult·SubscriptionState |
| `PushManager.swift` | 권한·토큰 대사(S-5)·구독 상태 |
| `EventBus.swift` | pushOpened/Received 리스너·콜드스타트 20건 버퍼·재생 |
| `SharedConfig.swift`·`NudgeOnDelivery.swift` | App Group 미러링(설정+식별자)·NSE 도달 리포터 |

## 로드맵

- **M1** ✅ init·identify·track·오프라인 큐
- **M2** ✅ reset·속성·푸시 등록·리스너(콜드스타트)·토큰 대사(권한 포함)·NSE 도달·rich push
- **M4** ✅ 계약 테스트(`contract-tests/`·`Tests/NudgeOnContractTests`)·실행 가능한 UIKit 데모 앱(`Examples/NudgeOnDemo`) (현재) / ☐ SPM·CocoaPods 배포


## 테스트

```bash
swift test   # 단위(25) + 계약(4 시나리오) = 26 test cases
```

- **계약 테스트** — `contract-tests/scenarios/*.json`(4플랫폼 공용 단일 출처)을 로드해
  공개 코어 → 실제 HTTP → 목 서버(NWListener) 수신 페이로드를 블랙박스 검증. `Tests/NudgeOnContractTests`.

## 기여

버그 제보와 PR을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.
보안 문제는 공개 이슈 대신 `security@nudgeon.io`로 알려주세요.

## 라이선스

[Apache License 2.0](LICENSE). NudgeOn 이름·워드마크·로고는 이 허여 대상이 아닙니다 —
[상표 정책](TRADEMARKS.md)을 따릅니다.
