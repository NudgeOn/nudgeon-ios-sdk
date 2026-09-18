# NudgeOn iOS SDK

CocoaPods 코어·알림 확장 배포 준비와 검증은 [COCOAPODS.md](COCOAPODS.md)를 참고하세요. 현재 trunk 게시 완료를 뜻하지 않습니다.

[![SPM](https://img.shields.io/github/v/release/NudgeOn/nudgeon-ios-sdk?label=Swift%20Package&sort=semver)](https://github.com/NudgeOn/nudgeon-ios-sdk/releases)
[![CI](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/NudgeOn/nudgeon-ios-sdk/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![status](https://img.shields.io/badge/status-beta--candidate-orange.svg)](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)

[NudgeOn](https://nudgeon.io) 고객 인게이지먼트 플랫폼의 iOS(Swift) 네이티브 코어 SDK.
이벤트를 수집하고 푸시를 수신합니다. 공통 이벤트·식별·푸시 API를 제공합니다.

> **파트너 베타 후보입니다.** SPM 0.2.3은 공개 배포되었으며, CocoaPods core/NSE는
> 검증·배포 준비를 마치고 메인테이너 로그인 후 trunk 게시를 기다립니다.
> 플랫폼 전체의 관리형 저장소·목표 부하·24시간 시험과 외부 온보딩 검증은 남아 있습니다.
> 최신 단말·공급자 검증 범위는 [출시 체크리스트](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)를 확인하세요.
> 서버·SDK의 공통 메시지 식별자 계약은 아래 푸시 계약 문서를 따릅니다.

- **플랫폼 저장소** — [NudgeOn/nudgeon-platform](https://github.com/NudgeOn/nudgeon-platform)
- **API 가이드** — [docs-public/API.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/API.md)
- **푸시 계약** — [docs-public/PUSH-CONTRACT.md](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/PUSH-CONTRACT.md)
- **개발자센터** — [nudgeon.io](https://nudgeon.io)
- **인앱 웹 소스 테스트** — [NudgeOnInApp 연결 안내](IN-APP-TESTING.md) (0.2.3)

## 설치 (Swift Package Manager)

```swift
.package(url: "https://github.com/NudgeOn/nudgeon-ios-sdk.git", from: "0.2.3")
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
- **M4** ✅ 계약 테스트(`contract-tests/`·`Tests/NudgeOnContractTests`)·실행 가능한 UIKit 데모 앱(`Examples/NudgeOnDemo`) / ✅ SPM 0.2.3 배포 / ☐ CocoaPods trunk 게시 (준비·lint 완료)


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

## 앱 실행 직후 광고 (0.2.3)

앱 시작 화면과 동의·라우팅이 끝난 뒤 준비된 화면에서 기존 `enable()` 대신 호출합니다.

```swift
campaigns.enableAfterLaunch(timeoutSeconds: 3) { result in
    // shown / noCampaign / timedOut / blocked / cancelled / failed / alreadyHandled
    print(result.rawValue)
}
```

앱 프로세스당 한 번만 시도하며 Scene/Activity/클라이언트 재생성으로 다시 표시하지 않습니다.
광고가 없거나 준비가 늦으면 메인 화면을 그대로 사용합니다. 준비 중 `screen()`을 곧바로
호출하면 시작 시도가 취소됩니다. 객체는 앱 소유자가 보관하고 실제 화면 변경만 전달하세요.
시작 기회를 이미 사용했어도 이후 화면/이벤트 캠페인은 활성 상태로 유지합니다.
전면·투명 팝업, 오늘 하루 숨김, 캠페인 시간대·빈도 제한을 재사용합니다.
서버/콘솔을 먼저 반영하세요. [전체 계약](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/APP-LAUNCH-ADS.md).
