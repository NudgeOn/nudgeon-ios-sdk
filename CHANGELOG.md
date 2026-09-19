# Changelog

## 0.2.6 — 2026-09-19

- Expose non-secret review context in `transferStatus.review`: latest run/revision, authoritative session/run expiry, last delivery attempt and observed receipt time.
- Persist context in protected storage across process restart; older journals remain readable with absent metadata.
- Persist each attempt before transport and preserve acknowledgement/storage-failure semantics. Discard clears context; a new run clears its old timestamps.


## 0.2.5 — 2026-09-19

- Persist content-review telemetry and its short-lived credential in protected storage before sending; replay in order with stable event IDs after restart.
- Flush queued events before ending the test session. Network failures retry with exponential backoff; permanent rejections remain visible until explicit discard.
- Add `InAppTestTransferStatus`, `onTransferStatus`, `transferStatus`, `retryPendingEvents()` and `discardPendingEvents()` for waiting/sending/server-confirmed/failed UI.
- Recovery uploads records only; it never reconnects test commands or reopens an ad. Server expiry and run leases still apply. Receipt is not content-review approval.
- Enforce one retained test client per API URL and SDK key. Production campaign and push APIs are unchanged.

## 0.2.4 — 2026-09-18

- Startup ads fill the screen and auto-dismiss after 4 seconds (displaySeconds: 3–5).
- The native timer starts after presentation; startup ads do not require a close/hide button.
- Fullscreen web content covers the full viewport on iOS and Android.
- Late launch decisions record launch_timeout instead of host_blocked.

## 0.2.3 — 2026-09-18

- 앱 시작 화면 이후 `enableAfterLaunch`로 launch 캠페인을 요청합니다. 기존 enable/foreground 동작은 유지합니다.
- 프로세스 단위 시작 기회 중복 방지, 기본 3초 준비 기한, 지연 응답 표시 차단과 완료 결과 콜백을 추가했습니다.
- 화면/동의/백그라운드 변경 시 준비를 취소하며 시간 초과는 정상 중단으로 기록합니다.
- 업데이트한 서버/콘솔과 호스트의 명시적인 시작 시점 연결이 필요합니다. 코어 푸시 동작은 변경하지 않았습니다.

## 0.2.2 — 2026-09-18

- 캠페인 IANA 시간대와 KST 기준 오늘 하루 안 보기를 지원합니다. 기존 UTC 캠페인은 유지하며, UTC 외 캠페인은 시간대 capability를 지원하는 SDK에만 노출됩니다.
- 정상 백그라운드/화면/세션 전환, 기능 비활성화, 캠페인 중지/만료를 `cancelled` 사유로 보고하고 실제 오류와 분리합니다. 구 서버용 이벤트 형식도 유지합니다.
- HTML 브리지에 캠페인 시간대를 전달하고 네이티브 숨김 안내의 고정 UTC 표기를 제거했습니다.
- 인앱 모듈 변경이며 코어 푸시 API는 변경하지 않았습니다. 업데이트한 NudgeOn API·콘솔이 필요합니다.
- iPhone 15 Pro/iOS 27, Fold3/Android 15에서 정상 중단 및 KST 자정 후 재표시를 검증했습니다.
