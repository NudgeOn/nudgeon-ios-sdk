# Onda iOS SDK

Onda 고객 인게이지먼트 플랫폼의 iOS(Swift) 네이티브 코어 SDK.
[플랫폼](../onda-platform) · 공개 인터페이스 명세: `onda-platform/docs/prd/PRD-01A`.

> 상태: **M1 코어** (init · identify · track · 오프라인 큐). 푸시(registerForPush·리스너·NSE 도달)는 M2.

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
// 로그아웃 시 필수 — 이전 유저에게 푸시 가는 사고 방지
Onda.reset()
```

## 아키텍처 (PRD-01A 1.1)

- **네이티브 코어가 유일한 상태 보유자** — 오프라인 큐(파일 영속), anon/device ID 영속,
  배치 플러시, 재시도. 브리지(RN/Flutter)는 무상태 전달만.
- `OndaSDK` (코어) + `OndaNotificationService` (NSE — 도달 트래킹·rich push).

## 모듈

| 파일 | 역할 |
|---|---|
| `Onda.swift` | 공개 API (initialize·identify·track·reset·flush) |
| `OndaCore.swift` | 코어 오케스트레이터 (큐·네트워크·플러시 타이머) |
| `Identity.swift` | anon/external/device ID 영속 (reset 정책) |
| `EventQueue.swift` | 오프라인 영속 큐 (1000건 상한·oldest drop) |
| `Network.swift` | /v1/track·identify·devices/token 클라이언트 |

## 로드맵

- **M1** ✅ init·identify·track·오프라인 큐 (현재)
- **M2** 오프라인 큐 내구성·reset·속성·푸시 등록·리스너·NSE 도달
- **M4** 데모 앱·계약 테스트·SPM/CocoaPods 배포

MIT License.
