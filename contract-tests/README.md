# Onda SDK 계약 테스트 (Contract Tests)

`scenarios/*.json` = **4개 플랫폼 공용 단일 출처** (PRD-01A "API 완전 동형"의 기계 검증).
각 시나리오는 *공개 API 호출 시퀀스 → 목 서버가 수신해야 할 HTTP 페이로드*를 선언한다.
iOS·Android·RN·Flutter 러너가 동일 JSON을 로드해 각자의 목 서버 상대로 실행한다.

> 현재 iOS 러너 구현 완료(`Tests/OndaContractTests`, `swift test`로 실행).
> Android/RN/Flutter 러너는 이 디렉터리를 공유(서브모듈/복사)해 후속 구현.

## 시나리오 스키마

```jsonc
{
  "name": "identify_then_track",
  "config": { "autoTrackSessions": false, "flushBatchSize": 100 },
  "steps": [                                  // 공개 API 호출 시퀀스
    { "call": "identify", "args": { "externalId": "user-123" } },
    { "call": "track", "args": { "name": "product_viewed", "properties": { "product_id": "P-1" } } },
    { "call": "flush" }
  ],
  "expect": [                                 // 목 서버가 수신해야 할 요청(순서 무관 매칭)
    { "path": "/v1/identify", "asserts": [ { "pointer": "external_id", "equals": "user-123" } ] },
    { "path": "/v1/track", "asserts": [ { "pointer": "batch.0.event", "equals": "product_viewed" } ] }
  ]
}
```

- **steps.call**: `identify` · `track` · `flush` · `setUserAttributes` · `reset` · `setPushToken`(hex).
- **asserts.pointer**: 점 표기 경로 + 배열 인덱스 (`batch.0.properties.product_id`).
- **asserts**: `equals`(값 일치) · `absent`(키 부재) · `present`(키 존재).
- `config.apiHost`/`sdkKey`는 러너가 목 서버로 주입한다.
