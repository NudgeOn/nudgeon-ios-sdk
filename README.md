# Onda iOS SDK

Onda 고객 인게이지먼트 플랫폼의 iOS(Swift) 네이티브 코어 SDK.
[플랫폼](../onda-platform) · 공개 인터페이스 명세: `onda-platform/docs/prd/PRD-01A`.

> 상태: **M2 코어 구현** — init · identify · track · 오프라인 큐 · 푸시 등록 · 리스너(콜드스타트 버퍼) · NSE 연결. 실제 delivered 수집은 아래 계약 제한이 남아 있다.

## 설치 (Swift Package Manager)

```swift
.package(url: "https://github.com/ondahq/onda-ios-sdk.git", from: "0.1.0")
```

## 빠른 시작

```swift
import OndaSDK

Onda.initialize(config: OndaConfig(
    sdkKey: "pk_...",
    apiHost: URL(string: "https://ingest.example.com")!  // 셀프호스팅 시 교체
))
Onda.identify(externalId: "user-123")
Onda.track("product_viewed", properties: ["product_id": "P-1", "price": 12900])
Onda.setUserAttributes(["vip_level": .number(3), "nickname": .string("ethan")])
// 현재 로컬 identity/token cache reset. 서버 device detach/unsubscribe 완료를 뜻하지 않음
Onda.reset()

// 푸시 (M2)
Task { let result = await Onda.registerForPush() }   // granted | denied | provisional
Onda.onPushOpened { payload in router.route(payload.deepLink) }  // 콜드 스타트 유실 없음
let initial = Onda.getInitialPushPayload()           // 푸시로 앱이 열렸으면 payload
```

## 실행 가능한 UIKit 샘플

[`Examples/OndaDemo`](Examples/OndaDemo)는 programmatic UIKit 앱, AppDelegate/SceneDelegate 푸시·딥링크 연동,
Notification Service Extension, 로컬 Swift Package 참조, 단위 테스트가 포함된 Xcode 프로젝트다.

```bash
open Examples/OndaDemo/OndaDemo.xcodeproj
```

기본값은 안전한 `pk_sample_replace_me`와 로컬 API host다. 실제 key/host, App Group, signing 설정과
현재 delivered 집계 계약 제한은 [샘플 README](Examples/OndaDemo/README.md)를 먼저 확인한다.

## AppDelegate 연동 (수동 — 기본, 스위즐링 미채택)

```swift
func application(_ app: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    Onda.setDeviceToken(token)               // 토큰 대사 → 서버 자동 등록/갱신
}
// UNUserNotificationCenterDelegate
func userNotificationCenter(_ c: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
    Onda.handlePushOpened(response.notification.request.content.userInfo)  // 딥링크 라우팅
}
func userNotificationCenter(_ c: UNUserNotificationCenter,
        willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
    Onda.handlePushReceived(n.request.content.userInfo)
    return [.banner, .sound]
}
```

## Notification Service Extension (delivered 집계 계약 제한 있음)

App Group을 코어 설정과 NSE에 공유하고, NSE는 베이스 클래스만 상속한다:

```swift
// 코어: OndaConfig(sdkKey:, apiHost:, appGroup: "group.io.onda.myapp")
import OndaNotificationService
class NotificationService: OndaNotificationServiceBase {
    override var appGroup: String? { "group.io.onda.myapp" }
}
```
`onda.image_url` 리치 푸시 첨부와 `$push_delivered` 전송 시도를 처리한다. 다만 현재
`OndaDelivery`가 빈 `anon_id`와 `external_id` 없이 보내 서버 식별자 스키마에서 `400`이 되므로,
식별자 계약을 고치기 전까지 delivered 집계 E2E는 완료로 보지 않는다.

## 아키텍처 (PRD-01A 1.1)

- **네이티브 코어가 유일한 상태 보유자** — 오프라인 큐(파일 영속), anon/device ID 영속,
  배치 플러시, 재시도. 브리지(RN/Flutter)는 무상태 전달만.
- `OndaSDK` (코어) + `OndaNotificationService` (NSE — delivered 전송 시도·rich push, 위 계약 제한 참고).

## 모듈

| 파일 | 역할 |
|---|---|
| `Onda.swift` | 공개 API (initialize·identify·track·reset·flush) |
| `OndaCore.swift` | 코어 오케스트레이터 (큐·네트워크·플러시 타이머) |
| `Identity.swift` | anon/external/device ID 영속 (reset 정책) |
| `EventQueue.swift` | 오프라인 영속 큐 (1000건 상한·oldest drop) |
| `Network.swift` | /v1/track·identify·devices/token 클라이언트 |
| `PushPayload.swift` | APNs userInfo 파싱·PushPermissionResult·SubscriptionState |
| `PushManager.swift` | 권한·토큰 대사(S-5)·구독 상태 |
| `EventBus.swift` | pushOpened/Received 리스너·콜드스타트 20건 버퍼·재생 |
| `SharedConfig.swift`·`OndaDelivery.swift` | App Group 미러링·NSE delivered 리포터(현재 식별자 계약 제한) |

## 로드맵

- **M1** ✅ init·identify·track·오프라인 큐
- **M2** ◐ reset·속성·푸시 등록·리스너(콜드스타트)·토큰 대사·NSE/rich push 연결 구현, delivered 수집 계약 수정 필요
- **M4** ✅ 계약 테스트(`contract-tests/`·`Tests/OndaContractTests`)·실행 가능한 UIKit 데모 앱(`Examples/OndaDemo`) (현재) / ☐ SPM·CocoaPods 배포


## 테스트

```bash
swift test   # 단위(16) + 계약(4 시나리오) = 17 test cases
```

- **계약 테스트** — `contract-tests/scenarios/*.json`(4플랫폼 공용 단일 출처)을 로드해
  공개 코어 → 실제 HTTP → 목 서버(NWListener) 수신 페이로드를 블랙박스 검증. `Tests/OndaContractTests`.

Licensed under the [Apache License 2.0](LICENSE).
