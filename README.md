# NudgeOn iOS SDK

CocoaPods 코어·알림 확장 배포 준비와 검증은 [COCOAPODS.md](COCOAPODS.md)를 참고하세요. 현재 trunk 게시 완료를 뜻하지 않습니다.

[![SPM](https://img.shields.io/github/v/release/NudgeOn/nudgeon-ios-sdk?label=Swift%20Package&sort=semver)](https://github.com/NudgeOn/nudgeon-ios-sdk/releases)
[![CI](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![status](https://img.shields.io/badge/status-beta--candidate-orange.svg)](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)

[NudgeOn](https://nudgeon.io) 고객 인게이지먼트 플랫폼의 iOS(Swift) 네이티브 코어 SDK.
이벤트를 수집하고 푸시를 수신합니다. 공통 이벤트·식별·푸시 API를 제공합니다.

> **파트너 베타 후보입니다.** SPM 0.2.8는 공개 배포되었으며, CocoaPods core/NSE는
> 검증·배포 준비를 마치고 메인테이너 로그인 후 trunk 게시를 기다립니다.
> 플랫폼 전체의 관리형 저장소·목표 부하·24시간 시험과 외부 온보딩 검증은 남아 있습니다.
> 최신 단말·공급자 검증 범위는 [출시 체크리스트](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)를 확인하세요.
> 서버·SDK의 공통 메시지 식별자 계약은 아래 푸시 계약 문서를 따릅니다.

- **플랫폼 저장소** — [NudgeOn/nudgeon-platform](https://github.com/NudgeOn/nudgeon-platform)
- **API 가이드** — [docs-public/API.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/API.md)
- **푸시 계약** — [docs-public/PUSH-CONTRACT.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/PUSH-CONTRACT.md)
- **개발자센터** — [nudgeon.io](https://nudgeon.io)
- **인앱 웹 소스 테스트** — [NudgeOnInApp 연결 안내](IN-APP-TESTING.md) (0.2.7)


## 기본 사용자 속성 (0.2.8+)

`NudgeOnAttributes`는 `setUserAttributes`에 전달할 키 상수입니다. 키 상수는 0.2.8부터 제공됩니다. 이전 버전에서는 문자열 키를 사용할 수 있습니다. SDK 초기화 후 `identify`를 먼저 호출하세요. 식별 전 속성 설정은 현재 지원하지 않습니다.

```swift
NudgeOn.identify(externalId: "user-123")
NudgeOn.setUserAttributes([
    NudgeOnAttributes.firstName: .string("Minji"),
    NudgeOnAttributes.email: .string("minji@example.com"),
    NudgeOnAttributes.dateOfBirth: .string("1995-03-15"),
    NudgeOnAttributes.country: .string("KR"),
    NudgeOnAttributes.timezone: .string("Asia/Seoul"),
    "membership_level": .string("gold")
])
// Delete a value:
NudgeOn.setUserAttributes([NudgeOnAttributes.phone: .null])
```

| 상수 | 전송 키 | 예시 |
|---|---|---|
| `NudgeOnAttributes.firstName` | `first_name` | `Minji` |
| `NudgeOnAttributes.lastName` | `last_name` | `Kim` |
| `NudgeOnAttributes.email` | `email` | `minji@example.com` |
| `NudgeOnAttributes.phone` | `phone` | `+821012345678` |
| `NudgeOnAttributes.dateOfBirth` | `dob` | `1995-03-15` |
| `NudgeOnAttributes.gender` | `gender` | `F` |
| `NudgeOnAttributes.homeCity` | `home_city` | `Seoul` |
| `NudgeOnAttributes.country` | `country` | `KR` |
| `NudgeOnAttributes.language` | `language` | `ko` |
| `NudgeOnAttributes.timezone` | `timezone` | `Asia/Seoul` |
| `NudgeOnAttributes.createdAt` | `created_at` | `2026-09-22T00:00:00Z` |

생일은 `YYYY-MM-DD` 문자열, 가입일은 시간대가 있는 RFC 3339 문자열을 사용합니다. 전화번호는 E.164, 국가·언어는 `KR`·`ko` 같은 코드, 시간대는 IANA 이름을 권장합니다. `gender` 권장 코드는 `M`, `F`, `O`, `N`, `P`, `U`입니다. Braze `time_zone`은 기존 NudgeOn 키 `timezone`으로 전달합니다.

값은 자동 수집·변환하지 않으며 커스텀 키도 지원합니다. `null`은 값을 삭제합니다. 현재 속성 전송은 네트워크 요청이며 이벤트 오프라인 큐의 영속 재시도 보장을 제공하지 않습니다. 실패에 대비한 재동기화는 앱에서 수행하세요. 푸시 수신 동의는 `setPushSubscription`을 사용하며 `push_subscribe` 같은 일반 속성으로 변경하지 않습니다.

## 기본 이벤트 (Standard events — 0.2.7+)

`NudgeOnEvents`로 콘솔과 같은 이벤트 이름을 사용할 수 있습니다. 아래 상수는 0.2.7부터 사용할 수 있습니다.
SDK를 초기화한 뒤 해당 행동이 성공한 시점에 호출하세요. 예시는 서로 다른 호출 시점을 보여주며, 회원가입·로그인·구입을 한 번에 자동 수집하는 코드는 아닙니다.

```swift
import NudgeOnSDK

// After SDK initialization and your app's authentication succeeds:
NudgeOn.identify(externalId: "user-123")
NudgeOn.track(NudgeOnEvents.signUp, properties: ["method": "email"])
NudgeOn.track(NudgeOnEvents.login, properties: ["method": "email"])
// After order/payment confirmation:
NudgeOn.track(NudgeOnEvents.purchaseCompleted, properties: [
    "order_id": "order-123", "total_amount": 29000, "currency": "KRW", "item_count": 1
])
```

| 상수 | 전송 이름 | 의미 | 권장 속성 |
|---|---|---|---|
| `NudgeOnEvents.signUp` | `sign_up` | 회원가입 | method |
| `NudgeOnEvents.login` | `login` | 로그인 | method |
| `NudgeOnEvents.purchaseCompleted` | `purchase_completed` | 구입 | order_id, total_amount, currency, item_count |
| `NudgeOnEvents.productViewed` | `product_viewed` | 상품 조회 | product_id, price, currency |
| `NudgeOnEvents.addToCart` | `add_to_cart` | 장바구니 담기 | product_id, quantity, price, currency |
| `NudgeOnEvents.checkoutStarted` | `checkout_started` | 결제 시작 | cart_id, item_count, total_amount, currency |

금액은 통화의 기본 단위(원·달러 등) 숫자, 통화는 ISO 4217 코드(`KRW`, `USD` 등)를 사용합니다. 속성은 권장 예시이며 서비스별 속성도 추가할 수 있습니다.
기존 `track("custom_event", ...)`는 그대로 지원하며 `purchase` 같은 기존 이름을 자동 변환하지 않습니다.
이름은 대소문자까지 콘솔 설정과 같아야 합니다. 상수 참조 자체는 이벤트를 만들지 않고, `login` 이벤트는 사용자 식별을 대신하지 않습니다.
`track` 이후 오프라인 저장·배치·재시도는 기존 전송 경로를 사용합니다.


## 설치 (Swift Package Manager)

```swift
.package(url: "https://github.com/NudgeOn/nudgeon-ios-sdk.git", from: "0.2.8")
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
- **M4** ✅ 계약 테스트(`contract-tests/`·`Tests/NudgeOnContractTests`)·실행 가능한 UIKit 데모 앱(`Examples/NudgeOnDemo`) / ✅ SPM 0.2.8 배포 / ☐ CocoaPods trunk 게시 (준비·lint 완료)


## 테스트

```bash
swift test   # 단위·계약 테스트; 최신 개수와 결과는 CI 참조
```

- **계약 테스트** — `contract-tests/scenarios/*.json`(4플랫폼 공용 단일 출처)을 로드해
  공개 코어 → 실제 HTTP → 목 서버(NWListener) 수신 페이로드를 블랙박스 검증. `Tests/NudgeOnContractTests`.

## 기여

버그 제보와 PR을 환영합니다. [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.
보안 문제는 공개 이슈 대신 `security@nudgeon.io`로 알려주세요.

## 라이선스

[Apache License 2.0](LICENSE). NudgeOn 이름·워드마크·로고는 이 허여 대상이 아닙니다 —
[상표 정책](TRADEMARKS.md)을 따릅니다.

## 앱 실행 직후 광고 (0.2.4+)

앱 시작 화면과 동의·라우팅이 끝난 뒤 준비된 화면에서 기존 `enable()` 대신 호출합니다.

```swift
campaigns.enableAfterLaunch(timeoutSeconds: 3, displaySeconds: 4) { result in
    // shown / noCampaign / timedOut / blocked / cancelled / failed / alreadyHandled
    print(result.rawValue)
}
```

앱 프로세스당 한 번만 시도하며 Scene/Activity/클라이언트 재생성으로 다시 표시하지 않습니다.
광고가 없거나 준비가 늦으면 메인 화면을 그대로 사용합니다. 준비 중 `screen()`을 곧바로
호출하면 시작 시도가 취소됩니다. 객체는 앱 소유자가 보관하고 실제 화면 변경만 전달하세요.
시작 기회를 이미 사용했어도 이후 화면/이벤트 캠페인은 활성 상태로 유지합니다.
시작 광고는 불투명 전면 화면으로 표시되며 실제 표시부터 기본 4초 뒤 자동 종료됩니다.
`displaySeconds`는 3~5초로 제한되며 닫기·오늘 하루 숨김 버튼 없이 메인으로 넘어갑니다.
호스트는 메인 UI 앞에 시작 화면을 유지하고 결과 콜백에서 해제합니다. 최대 3초 fallback을 두세요.
일반 인앱 캠페인의 닫기·숨김 동작과 캠페인 시간대·빈도 제한은 유지됩니다.
서버/콘솔을 먼저 반영하세요. [전체 계약](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/APP-LAUNCH-ADS.md).
