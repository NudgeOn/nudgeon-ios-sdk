# NudgeOn iOS quickstart

**게시된 Swift Package만 사용하는 최소 예제입니다.** 이 저장소의 로컬 소스를 참조하지 않고
`https://github.com/NudgeOn/nudgeon-ios-sdk.git` 을 `from: 0.1.0` 으로 원격에서 받아 씁니다 —
새 프로젝트에 SDK를 붙일 때 필요한 최소 코드를 그대로 보여 줍니다.

> 이 저장소에는 예제가 두 개 있습니다.
>
> | | [`NudgeOnDemo`](../NudgeOnDemo) | `NudgeOnQuickstart` (여기) |
> |---|---|---|
> | SDK 출처 | 로컬 패키지 (`path: ../..`) | **원격 게시본 `0.1.0`** |
> | 목적 | 개발 중 코드 검증 | **게시본 검증 · 통합 예제** |
> | 범위 | APNs · NSE 도달 · 딥링크까지 | 초기화 · identify · track · 권한 |
> | UI | UIKit | SwiftUI |

## 실행

Xcode에서 `NudgeOnQuickstart.xcodeproj` 를 열고 시뮬레이터에서 실행합니다. 명령줄이면:

```bash
cd Examples/NudgeOnQuickstart
xcodebuild -project NudgeOnQuickstart.xcodeproj -scheme NudgeOnQuickstart \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

실제 수집을 확인하려면 publishable 키와 API host를 넘기세요. 넘기지 않으면 placeholder로
빌드되어 앱은 뜨지만 이벤트가 서버에 도달하지 않습니다.

```bash
xcodebuild ... build \
  NUDGEON_SDK_KEY=pk_your_publishable_key \
  NUDGEON_API_HOST=http://localhost:8080
```

프로젝트 파일은 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 으로 생성합니다.
`project.yml` 을 고친 뒤 `xcodegen generate` 를 실행하세요.

## 통합에 필요한 전부

**1. 패키지 추가** — Xcode의 File → Add Package Dependencies, 또는 `Package.swift`:

```swift
.package(url: "https://github.com/NudgeOn/nudgeon-ios-sdk.git", from: "0.1.0")
```

**2. 초기화** — 앱 진입점에서 한 번만.

```swift
NudgeOn.initialize(config: NudgeOnConfig(
    sdkKey: "pk_...",
    apiHost: URL(string: "https://ingest.example.com")!
))
```

**3. 식별과 이벤트**

```swift
NudgeOn.identify(externalId: "user-123")
NudgeOn.setUserAttributes(["plan": .string("free")])
NudgeOn.track("product_viewed", properties: ["product_id": "P-1", "price": 12900])
```

## 이 예제가 다루는 것

- 초기화와 SDK 상태 표시 — device id · anon id · 수신 동의 · OS 권한 · 토큰 등록 여부
- `identify` · `setUserAttributes` · `track` · `flush` · `reset`
- `registerForPush()` 로 알림 권한 요청과 **OS 권한 / 서비스 수신 동의 분리**
  (권한 허용 ≠ 마케팅 수신 동의. 예제는 허용일 때만 `setPushSubscription(true)` 를 호출합니다)
- 푸시 열림 · 수신 리스너와 콜드 스타트 페이로드 재생

## 다루지 않는 것

APNs 토큰 등록, Notification Service Extension을 통한 도달($push_delivered) 추적, 딥링크
라우팅은 [`NudgeOnDemo`](../NudgeOnDemo)를 보세요. App Group과 개발자 계정 설정이 필요합니다.

## 알아 둘 것

`reset()` 은 **로컬 식별자와 토큰 캐시만** 정리합니다. 서버 측 구독 해제와 이전 계정 연결 해제는
아직 완료되지 않았습니다 — [출시 체크리스트](https://github.com/NudgeOn/nudgeon-platform/blob/main/docs-public/RELEASE-CHECKLIST.md)의
P0-03을 참고하세요.
