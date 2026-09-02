# Onda iOS UIKit sample app

`initialize → identify/reset → track/flush → push permission/token → notification callbacks → deep link`를
programmatic UIKit으로 보여 주는 실행 가능한 샘플이다. SwiftUI나 storyboard를 사용하지 않는다.

## 바로 실행

1. [OndaDemo.xcodeproj](OndaDemo.xcodeproj)을 Xcode에서 연다.
2. `OndaDemo` scheme과 iOS Simulator를 선택한다.
3. Run한다. 기본 설정은 `pk_sample_replace_me`와 `http://localhost:8080`이므로 실제 고객 데이터가 전송되지 않는다.

저장소 루트에서 CLI 빌드는 다음처럼 실행할 수 있다.

```bash
xcodebuild \
  -project Examples/OndaDemo/OndaDemo.xcodeproj \
  -scheme OndaDemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

프로젝트 파일은 저장소에 포함되어 있다. `project.yml`을 수정했다면 XcodeGen 2.45+로 다시 생성한다.

```bash
cd Examples/OndaDemo
xcodegen generate
```

## 설정

SDK Key와 API host는 Xcode scheme의 환경 변수를 먼저 읽고, 없으면 `project.yml`이 생성한
Info.plist 값을 사용한다. App Group은 entitlement와 NSE에도 같은 값이 필요하므로 런타임 환경 변수를
사용하지 않고 프로젝트 빌드 설정 `ONDA_APP_GROUP`만 읽는다.

| 변수 | 기본값 | 설명 |
|---|---|---|
| `ONDA_SDK_KEY` | `pk_sample_replace_me` | 모바일에 넣을 수 있는 Publishable Key. 반드시 `pk_`만 사용한다. `sk_`나 세션 토큰은 넣지 않는다. |
| `ONDA_API_HOST` | `http://localhost:8080` | Onda API base URL. 실제 기기에서 `localhost`는 Mac이 아니라 기기 자신이므로 접근 가능한 HTTPS 주소로 바꾼다. |
| `ONDA_APP_GROUP` (build setting) | `group.io.onda.demo` | 앱/NSE Info.plist와 entitlement에 함께 들어간다. `project.yml` 또는 두 타깃의 공통 빌드 설정에서 실제 팀의 값으로 교체하고 프로젝트를 재생성한다. |

실제 기기에서 푸시를 시험하려면 다음 값도 자신의 Apple Developer 설정에 맞춰 바꿔야 한다.

- App/NSE bundle identifier와 Development Team
- 두 타깃의 동일한 App Group
- 앱 타깃의 Push Notifications 및 Background Modes > Remote notifications capability
- APNs credential과 Onda 서버의 앱 설정

## 코드 흐름

| 파일 | 확인할 내용 |
|---|---|
| `App/AppDelegate.swift` | launch 시 SDK 초기화, push opened/received listener, APNs token 전달, foreground/background notification delegate |
| `App/SceneDelegate.swift` | programmatic `UIWindow`, 푸시 콜드 스타트, custom URL, Universal Link 진입 |
| `App/DemoViewController.swift` | identify/reset, track/flush, 속성, 권한 요청, 구독 상태, deep-link 실습 UI |
| `App/DemoConfiguration.swift` | `pk_` key 검증과 환경 변수/Info.plist 설정 우선순위 |
| `NotificationServiceExtension/NotificationService.swift` | rich push와 delivered 리포트를 위한 Onda NSE 베이스 클래스 연동 |

직접 딥링크 진입을 확인할 수 있다.

```bash
xcrun simctl openurl booted 'ondademo://product/P-1'
```

앱을 Simulator에서 한 번 실행한 뒤 홈 화면으로 보내 백그라운드 상태로 만든다. 다음 명령을 실행하고
표시된 알림을 직접 탭하면 Onda 형식 payload의 opened callback과 deep-link 경로를 재현할 수 있다.

```bash
xcrun simctl push booted io.onda.demo Examples/OndaDemo/Fixtures/sample-push.apns
```

## 검증 범위와 현재 제한

- `track`은 로컬 큐 적재이고 `flush`는 전송 요청이다. 공개 API에 완료 콜백이 없으므로 화면은 서버 수신 성공을 표시하지 않는다. 서버의 `202`도 receipt/outbox 영속 확인이지 최종 전달 확인이 아니다.
- `registerForPush()` 반환값은 OS 권한 결과다. APNs token 발급이나 Onda 서버 token 등록 성공을 뜻하지 않으므로 `getPushSubscription()`을 별도로 새로고침한다.
- 현재 `autoRegisterPushToken` 설정은 SDK 내부에서 사용되지 않는다. 샘플은 사용자 버튼으로 권한/등록 흐름을 시작한다.
- `identify`·`reset`·`track`은 모두 코어 직렬 큐에서 처리되므로 호출 순서가 곧 귀속 순서다. `identify` 직후 `track`은 새 유저로, `reset` 직후 `track`은 익명으로 귀속된다.
- 현재 `setPushSubscription`과 `reset`은 로컬 상태/캐시만 바꾸며 서버 unsubscribe 또는 device detach 성공을 보장하지 않는다. 샘플 UI도 이를 로컬 상태로 표시한다.
- Simulator의 `simctl push`는 payload 파싱, callback, deep-link UI를 확인하는 로컬 테스트다. 실제 APNs credential, 기기 token, provider delivery, 백엔드 수집을 증명하지 않는다.
- `$push_delivered`는 코어가 App Group에 미러링한 `anon_id`/`external_id`/`device_id`로 전송된다. 앱을 한 번 실행해 SDK가 초기화된 뒤에야 NSE가 식별자를 읽을 수 있으며, 그 전에는 경고 로그를 남기고 전송을 건너뛴다. 앱과 NSE의 App Group 값이 다르면 같은 이유로 도달 집계가 되지 않는다.

## 테스트

`OndaDemoTests`는 환경 변수 우선순위, `pk_` 전용 보호, API URL 검증을 고정적으로 확인한다.

```bash
xcodebuild \
  -project Examples/OndaDemo/OndaDemo.xcodeproj \
  -scheme OndaDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
```
