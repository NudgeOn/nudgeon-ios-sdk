# Onda iOS 데모 앱

`설치 → identify → track → 푸시 수신 → 딥링크 진입 → opened 집계` E2E 예제 (PRD-01A 5장).
"살아있는 문서" — 실제 통합 방법을 코드로 보여준다.

> 이 폴더는 **소스만** 제공한다. 실행하려면 Xcode 프로젝트가 필요하다(아래 참조).
> SPM 패키지 빌드에는 포함되지 않는다(별도 앱 타깃).

## 구성 파일

| 파일 | 역할 |
|---|---|
| `OndaDemoApp.swift` | App 진입 + AppDelegate 푸시 연동(토큰 대사·pushOpened·콜드스타트) |
| `ContentView.swift` | identify·track·registerForPush·구독 상태·딥링크 UI |
| `NotificationService.swift` | NSE 타깃 — 도달($push_delivered)·리치 푸시 |

## Xcode 프로젝트 만들기

1. **New Project → iOS App** (SwiftUI, 이름 `OndaDemo`). 생성된 `App.swift`/`ContentView.swift`는 이 폴더 파일로 교체.
2. **Add Package Dependency** → 로컬 경로 `../..` (onda-ios-sdk) 선택 → `OndaSDK` 라이브러리 추가.
3. **Signing & Capabilities**:
   - `Push Notifications` 추가.
   - `Background Modes` → Remote notifications 체크.
   - `App Groups` 추가 → `group.io.onda.demo` (NSE와 공유).
4. **NSE 타깃**: File → New → Target → *Notification Service Extension* (`OndaDemoNSE`).
   - 생성된 파일을 `NotificationService.swift`로 교체.
   - 이 타깃에도 `OndaNotificationService` 라이브러리와 같은 App Group을 추가.
5. `sdkKey`/`apiHost`를 실제 값으로 교체(`OndaDemoApp.swift`). 셀프호스팅이면 `apiHost`만 바꾼다.

## E2E 확인 순서

1. 앱 실행 → `registerForPush` → 권한 허용 → 구독 상태 `token=true` 확인.
2. 콘솔/API에서 이 유저(`identify`한 external_id)에게 캠페인 발송.
3. 백그라운드 상태에서 푸시 수신 → NSE가 `$push_delivered` 전송(도달 집계).
4. 푸시 탭 → 앱 진입 → "마지막 딥링크"에 payload.deepLink 표시 + `$push_opened` 집계.
5. 앱 종료(kill) 상태에서 푸시 탭 → 콜드 스타트에서도 딥링크 라우팅되는지 확인(`getInitialPushPayload`).
