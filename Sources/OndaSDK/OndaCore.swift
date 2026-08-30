import Foundation

/// 코어 오케스트레이터 — 식별자·큐·네트워크·플러시 타이머를 조율.
/// 내부 직렬 큐에서 모든 상태 변경 수행 (공개 API 논블로킹).
final class OndaCore {
    private let config: OndaConfig
    private let identity: Identity
    private let queue: EventQueue
    private let network: Network
    private let work = DispatchQueue(label: "io.onda.core")
    private var flushTimer: DispatchSourceTimer?
    private var flushing = false

    init(config: OndaConfig) {
        self.config = config
        self.identity = Identity()
        self.queue = EventQueue()
        self.network = Network(config: config, deviceId: identity.deviceId)
        OndaLog.level = config.logLevel
    }

    var deviceId: String { identity.deviceId }
    var anonId: String { identity.anonId }

    func start() {
        OndaLog.info("Onda 초기화: host=\(config.apiHost)")
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
