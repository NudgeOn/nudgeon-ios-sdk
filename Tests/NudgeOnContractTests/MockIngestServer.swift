import Foundation
import Network

/// 인프로세스 목 수집 서버 — SDK가 실제 URLSession으로 보낸 HTTP 요청을 기록한다.
/// 계약 테스트는 공개 코어 → 실제 네트워크 → 서버 수신 페이로드까지 블랙박스로 검증한다.
final class MockIngestServer {
    struct Recorded {
        let method: String
        let path: String
        let body: [String: Any]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.nudgeon.mockserver")
    private let lock = NSLock()
    private var records: [Recorded] = []
    private var onRecord: (() -> Void)?

    private(set) var port: UInt16 = 0

    init() throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params)
    }

    /// 리스너 시작 후 할당된 포트를 반환 (ready까지 대기).
    func start(onRecord: @escaping () -> Void) throws -> UInt16 {
        self.onRecord = onRecord
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let p = self?.listener.port?.rawValue {
                self?.port = p
                ready.signal()
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        return port
    }

    func stop() { listener.cancel() }

    var recorded: [Recorded] {
        lock.lock(); defer { lock.unlock() }
        return records
    }

    // MARK: 연결 처리

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var acc = buffer
            if let data { acc.append(data) }
            if let req = Self.parse(acc) {
                self.record(req)
                self.respond(conn)
                return
            }
            if isComplete || error != nil {
                conn.cancel(); return
            }
            self.receive(conn, buffer: acc) // 헤더/바디 아직 → 계속 수신
        }
    }

    private func respond(_ conn: NWConnection) {
        let body = "{}".data(using: .utf8)!
        let head = "HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var out = head.data(using: .utf8)!
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func record(_ r: Recorded) {
        lock.lock(); records.append(r); lock.unlock()
        onRecord?()
    }

    // MARK: HTTP 파싱 (요청 라인 + 헤더 + Content-Length 바디)

    private static func parse(_ data: Data) -> Recorded? {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: data.startIndex..<sep.lowerBound)
        guard let header = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = parts[1]

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            contentLength = Int(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let bodyStart = sep.upperBound
        let bodyData = data.subdata(in: bodyStart..<data.endIndex)
        guard bodyData.count >= contentLength else { return nil } // 바디 미완 → 더 수신
        let body = (try? JSONSerialization.jsonObject(with: bodyData.prefix(contentLength))) as? [String: Any] ?? [:]
        return Recorded(method: method, path: path, body: body)
    }
}
