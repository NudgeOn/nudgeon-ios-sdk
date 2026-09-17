import Foundation

/// Ordered, atomic, installation-scoped telemetry. No credentials or HTML are stored.
final class InAppEventJournal {
    struct Event: Codable {
        let id: String, delivery: String, kind: String, detail: String, occurredAt: String
        let createdAt: TimeInterval
    }
    private struct Snapshot: Codable { let owner: String; let events: [Event] }
    private let file: URL, owner: String
    private(set) var events: [Event] = []
    init(file: URL, owner: String) throws {
        self.file = file; self.owner = owner
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2 * 1024 * 1024 else { throw InAppError.invalidArtifact }
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
            guard snapshot.events.count <= 1000 else { throw InAppError.invalidArtifact }
            if snapshot.owner == owner { events = snapshot.events }
        }
        try commit(events.filter { $0.createdAt > Date().timeIntervalSince1970 - 604800 })
    }
    func append(delivery: String, kind: String, detail: String, now: Date = Date()) throws {
        var next = events.filter { $0.createdAt > now.timeIntervalSince1970 - 604800 }
        guard next.count < 1000 else { throw InAppError.sessionClosed }
        next.append(Event(id: UUID().uuidString, delivery: delivery, kind: kind,
                          detail: String(detail.prefix(200)), occurredAt: now.ISO8601Format(), createdAt: now.timeIntervalSince1970))
        try commit(next)
    }
    func acknowledge(_ id: String) throws { try commit(events.filter { $0.id != id }) }
    func clear() throws { try commit([]) }
    private func commit(_ next: [Event]) throws {
        let data = try JSONEncoder().encode(Snapshot(owner: owner, events: next))
        try data.write(to: file, options: .atomic)
        events = next
    }
}
