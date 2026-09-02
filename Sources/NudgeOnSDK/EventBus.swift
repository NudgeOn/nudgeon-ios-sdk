import Foundation

/// 푸시 이벤트 리스너 레지스트리 + 콜드스타트 버퍼 (PRD-01A 2.5, 4장).
///
/// 콜드 스타트(푸시로 앱 실행)에서 pushOpened가 리스너 등록보다 먼저 발생한다.
/// → 리스너 없을 때 최대 20건 버퍼링 후 첫 등록 시 재생 (브리지 계약 4장: 코어 최대 20건 버퍼).
/// getInitialPushPayload와 리스너 버퍼 재생의 이중 경로를 모두 이 클래스가 담당.
final class EventBus {
    enum Kind { case opened, received }

    private let lock = NSLock()
    private var openedHandlers: [UUID: (PushPayload) -> Void] = [:]
    private var receivedHandlers: [UUID: (PushPayload) -> Void] = [:]
    private var openedBuffer: [PushPayload] = []
    private var receivedBuffer: [PushPayload] = []
    /// 콜드 스타트 진입 페이로드 — getInitialPushPayload 전용(한 번 조회로 소진되지 않고 유지).
    private var initialOpened: PushPayload?

    private let maxBuffer = 20
    private let deliver: (@escaping () -> Void) -> Void

    /// deliver: 핸들러 호출 디스패치(기본 main). 테스트에서는 동기 실행 주입.
    init(deliver: @escaping (@escaping () -> Void) -> Void = { block in DispatchQueue.main.async(execute: block) }) {
        self.deliver = deliver
    }

    // MARK: 구독

    @discardableResult
    func onPushOpened(_ handler: @escaping (PushPayload) -> Void) -> UUID {
        subscribe(.opened, handler)
    }

    @discardableResult
    func onPushReceived(_ handler: @escaping (PushPayload) -> Void) -> UUID {
        subscribe(.received, handler)
    }

    func off(_ token: UUID) {
        lock.lock(); defer { lock.unlock() }
        openedHandlers[token] = nil
        receivedHandlers[token] = nil
    }

    private func subscribe(_ kind: Kind, _ handler: @escaping (PushPayload) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        let replay: [PushPayload]
        switch kind {
        case .opened:
            openedHandlers[token] = handler
            replay = openedBuffer
            openedBuffer.removeAll()
        case .received:
            receivedHandlers[token] = handler
            replay = receivedBuffer
            receivedBuffer.removeAll()
        }
        lock.unlock()
        for payload in replay {
            deliver { handler(payload) }
        }
        return token
    }

    // MARK: 발행

    func emitOpened(_ payload: PushPayload) {
        lock.lock()
        initialOpened = payload
        let handlers = Array(openedHandlers.values)
        if handlers.isEmpty {
            appendBuffered(&openedBuffer, payload)
        }
        lock.unlock()
        for h in handlers { deliver { h(payload) } }
    }

    func emitReceived(_ payload: PushPayload) {
        lock.lock()
        let handlers = Array(receivedHandlers.values)
        if handlers.isEmpty {
            appendBuffered(&receivedBuffer, payload)
        }
        lock.unlock()
        for h in handlers { deliver { h(payload) } }
    }

    /// 콜드 스타트 진입 페이로드 (RN/Flutter getInitialPushPayload 대응). 없으면 nil.
    func getInitialPushPayload() -> PushPayload? {
        lock.lock(); defer { lock.unlock() }
        return initialOpened
    }

    /// 버퍼 상한 유지 — 초과 시 oldest drop (최신 이벤트 우선).
    private func appendBuffered(_ buffer: inout [PushPayload], _ payload: PushPayload) {
        buffer.append(payload)
        if buffer.count > maxBuffer {
            buffer.removeFirst(buffer.count - maxBuffer)
        }
    }
}
