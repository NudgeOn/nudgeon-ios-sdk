import Foundation

/// 코어 오케스트레이터 — 식별자·큐·네트워크·플러시 타이머·푸시를 조율.
/// 내부 직렬 큐에서 모든 상태 변경 수행 (공개 API 논블로킹).
final class OndaCore {
    private let config: OndaConfig
    private let identity: Identity
    private let queue: EventQueue
    private let network: Network
    private let push: PushManager
    let bus: EventBus
    private let work = DispatchQueue(label: "io.onda.core")
    private var flushTimer: DispatchSourceTimer?
    private var flushing = false

    init(config: OndaConfig) {
        self.config = config
        self.identity = Identity()
        self.queue = EventQueue()
        self.network = Network(config: config, deviceId: identity.deviceId)
        self.push = PushManager(config: config, network: network)
        self.bus = EventBus()
        OndaLog.level = config.logLevel
    }

    var deviceId: String { identity.deviceId }
    var anonId: String { identity.anonId }

    func start() {
        OndaLog.info("Onda 초기화: host=\(config.apiHost)")
        // NSE(별도 프로세스)가 도달 이벤트를 보낼 수 있도록 설정을 app group에 미러링.
        SharedConfig.mirror(config: config, deviceId: identity.deviceId)
        if config.autoTrackSessions {
            track("session_start", properties: [:])
        }
        scheduleFlush()
        flush() // 이전 세션 잔존분 즉시 전송 시도
    }

    func identify(_ externalId: String) {
        work.async { [self] in
            identity.externalId = externalId
            network.sendIdentify(externalId: externalId, anonId: identity.anonId, attributes: [:]) { ok in
                OndaLog.info("identify \(ok ? "성공" : "재시도 대기")")
            }
        }
    }

    func reset() {
        work.async { [self] in
            flushSync() // 이전 유저 이벤트를 먼저 비운다
            identity.reset()
            push.clearTokenCache() // 다음 토큰을 새 유저로 재등록 (이전 유저 미발송 — S-4)
            OndaLog.info("reset 완료 — 새 anon_id 발급")
        }
    }

    func setUserAttributes(_ attrs: [String: OndaValue]) {
        work.async { [self] in
            guard let ext = identity.externalId else {
                OndaLog.warn("setUserAttributes: identify 이전 호출 — 무시 (익명 속성은 후속)")
                return
            }
            let json = attrs.mapValues { $0.json ?? NSNull() }
            network.sendIdentify(externalId: ext, anonId: identity.anonId, attributes: json) { _ in }
        }
    }

    func track(_ name: String, properties: [String: Any]) {
        let item = EventQueue.Item(
            insertId: UUID().uuidString.lowercased(),
            event: name,
            properties: properties.mapValues { AnyCodable($0) },
            clientTs: ISO8601DateFormatter().string(from: Date()),
            anonId: identity.anonId,
            externalId: identity.externalId
        )
        queue.enqueue(item)
        if queue.count >= config.flushBatchSize {
            flush()
        }
    }

    func flush() {
        work.async { [self] in flushSync() }
    }

    // MARK: 푸시

    func registerForPush(provisional: Bool) async -> PushPermissionResult {
        await push.requestAuthorization(provisional: provisional)
    }

    /// AppDelegate didRegisterForRemoteNotificationsWithDeviceToken 연동 진입점.
    func setDeviceToken(_ token: Data) {
        let hex = PushManager.hexString(from: token)
        work.async { [self] in
            registerTokenIfPermitted(hex)
        }
    }

    private func registerTokenIfPermitted(_ hex: String) {
        Task { [self] in
            let perm = await push.currentOSPermission()
            work.async { [self] in
                push.registerToken(hex, externalId: identity.externalId, anonId: identity.anonId, osPermission: perm)
            }
        }
    }

    func setPushSubscription(_ optedIn: Bool) {
        work.async { [self] in push.setServiceOptIn(optedIn) }
    }

    func getPushSubscription() async -> SubscriptionState {
        let perm = await push.currentOSPermission()
        return push.subscriptionState(osPermission: perm)
    }

    /// 원격 알림 수신/탭 처리 (AppDelegate·UNUserNotificationCenterDelegate 연동).
    /// opened=true면 탭으로 앱 진입(딥링크 라우팅), false면 포그라운드 수신.
    @discardableResult
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any], opened: Bool) -> Bool {
        guard let payload = PushPayload.parse(userInfo) else { return false }
        if opened {
            track("$push_opened", properties: pushProps(payload))
            bus.emitOpened(payload)
        } else {
            track("$push_received", properties: pushProps(payload))
            bus.emitReceived(payload)
        }
        return true
    }

    private func pushProps(_ p: PushPayload) -> [String: Any] {
        var props: [String: Any] = ["message_id": p.messageId]
        if let c = p.campaignId { props["campaign_id"] = c }
        if let j = p.journeyId { props["journey_id"] = j }
        return props
    }

    // MARK: 내부

    private func flushSync() {
        guard !flushing else { return }
        let batch = queue.peek(config.flushBatchSize)
        guard !batch.isEmpty else { return }
        flushing = true
        let ids = Set(batch.map { $0.insertId })
        network.sendTrack(batch) { [self] ok in
            work.async {
                if ok { queue.ack(ids) }
                flushing = false
            }
        }
    }

    private func scheduleFlush() {
        let timer = DispatchSource.makeTimerSource(queue: work)
        timer.schedule(deadline: .now() + config.flushInterval, repeating: config.flushInterval)
        timer.setEventHandler { [weak self] in self?.flushSync() }
        timer.resume()
        flushTimer = timer
    }
}
