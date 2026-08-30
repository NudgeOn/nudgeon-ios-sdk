import Foundation

/// 오프라인 영속 이벤트 큐 (PRD-01 7.2). 앱 킬·오프라인에도 유실 없음.
/// MVP: 파일 기반 JSON 영속(SQLite 전환은 후속). 상한 1000건(초과 시 oldest drop).
/// 내부 직렬 큐로 접근 보호 — 공개 API는 논블로킹.
final class EventQueue {
    struct Item: Codable {
        let insertId: String
        let event: String
        let properties: [String: AnyCodable]
        let clientTs: String
        let anonId: String
        let externalId: String?
    }

    private let maxItems = 1000
    private let fileURL: URL
    private let lock = DispatchQueue(label: "io.onda.eventqueue")
    private var items: [Item]

    init(fileName: String = "onda_events.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(fileName)
        self.items = EventQueue.load(from: fileURL)
    }

    func enqueue(_ item: Item) {
        lock.sync {
            items.append(item)
            if items.count > maxItems {
                items.removeFirst(items.count - maxItems) // oldest drop
            }
            persist()
        }
    }

    /// 최대 batchSize건을 꺼내 반환(제거하지 않음 — 전송 성공 후 ack로 제거).
    func peek(_ batchSize: Int) -> [Item] {
        lock.sync { Array(items.prefix(batchSize)) }
    }

    /// 전송 성공한 insertId들을 큐에서 제거.
    func ack(_ insertIds: Set<String>) {
        lock.sync {
            items.removeAll { insertIds.contains($0.insertId) }
            persist()
        }
    }

    var count: Int { lock.sync { items.count } }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func load(from url: URL) -> [Item] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return items
    }
}

/// JSON 값 타입 소거 래퍼 (properties 직렬화용).
public struct AnyCodable: Codable {
    let value: Any
    public init(_ value: Any) { self.value = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(Bool.self) { value = v }
        else if let v = try? c.decode([String].self) { value = v }
        else { value = NSNull() }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as String: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as Int: try c.encode(Double(v))
        case let v as Bool: try c.encode(v)
        case let v as [String]: try c.encode(v)
        default: try c.encodeNil()
        }
    }
}
