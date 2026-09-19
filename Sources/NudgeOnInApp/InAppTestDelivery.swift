import Foundation

/// Non-secret context for locating the latest review. Receipt time is observed on the device,
/// not a server clock or review approval. Optional fields allow older journals to recover.
public struct InAppTestReviewDetails: Codable, Equatable {
    public var runID: String?
    public var revisionID: String?
    public var sessionExpiresAt: String?
    public var runExpiresAt: String?
    public var lastAttemptAt: Date?
    public var lastReceivedAt: Date?
}

/// Server acknowledgement of test telemetry, not approval of the content review.
public struct InAppTestTransferStatus: Equatable {
    public enum Phase: String { case idle, pending, sending, acknowledged, failed }
    public let phase: Phase
    public let pendingCount: Int
    public let acknowledgedCount: Int
    public let reason: String?
    public let canEndSafely: Bool
    public var review: InAppTestReviewDetails? = nil
}

/// One encrypted snapshot per API/key. Transport and storage are injected for failure tests.
@MainActor final class InAppTestDelivery {
    struct Event: Codable { let id: String, run: String, kind: String, detail: String }
    struct Snapshot: Codable {
        var credential: String?
        var events: [Event] = []
        var activeRun: String?
        var closing = false
        var acknowledged = 0
        var terminalError: String?
        var review: InAppTestReviewDetails?
    }
    enum Failure: Error { case pendingRecovery, storage, invalidReceipt, full }
    typealias Send = (String, [String: String], String) async throws -> Void
    private let now: () -> Date
    private let write: (String) throws -> Void
    private let changed: (InAppTestTransferStatus) -> Void
    private(set) var snapshot: Snapshot
    private var storageFailed = false
    private var pendingWrite: Snapshot?
    private(set) var sending = false
    private var epoch = UUID()
    private(set) var status = InAppTestTransferStatus(phase: .idle, pendingCount: 0, acknowledgedCount: 0, reason: nil, canEndSafely: true)
    var needsRecovery: Bool { snapshot.credential != nil }
    var canRetry: Bool { needsRecovery && snapshot.terminalError == nil && !storageFailed }

    init(read: () throws -> String?, write: @escaping (String) throws -> Void,
         changed: @escaping (InAppTestTransferStatus) -> Void, now: @escaping () -> Date = Date.init) throws {
        self.now = now
        self.write = write; self.changed = changed
        if let saved = try read() {
            guard saved.utf8.count <= 256 * 1024 else { throw Failure.storage }
            snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(saved.utf8))
            guard snapshot.events.count <= 200 else { throw Failure.storage }
        } else { snapshot = Snapshot() }
        if snapshot.credential != nil {
            var next = snapshot
            next.closing = true // Recovery never resumes commands or presents an old ad.
            if let run = next.activeRun {
                guard next.events.count < 200 else { throw Failure.full }
                next.events.append(Event(id: UUID().uuidString, run: run, kind: "failed", detail: "PROCESS_RESTARTED"))
                next.activeRun = nil
            }
            try commit(next)
        }
        publish()
    }
    func begin(_ credential: String, sessionExpiresAt: String? = nil) throws {
        guard !sending, !needsRecovery, !storageFailed else { throw Failure.pendingRecovery }
        try commit(Snapshot(credential: credential, review: InAppTestReviewDetails(sessionExpiresAt: sessionExpiresAt))); epoch = UUID(); publish()
    }
    func retryStorage() throws {
        if let next = pendingWrite { try commit(next); publish() }
    }
    func updateSessionExpiry(_ value: String?) throws {
        guard let value, snapshot.credential != nil, value != snapshot.review?.sessionExpiresAt else { return }
        guard !storageFailed else { throw Failure.storage }
        var next = snapshot; var review = next.review ?? InAppTestReviewDetails()
        review.sessionExpiresAt = value; next.review = review; try commit(next); publish()
    }
    func active(_ run: String, revisionID: String? = nil, expiresAt: String? = nil) throws {
        guard !storageFailed else { throw Failure.storage }
        var next = snapshot; next.activeRun = run
        next.review = InAppTestReviewDetails(runID: run, revisionID: revisionID,
            sessionExpiresAt: next.review?.sessionExpiresAt, runExpiresAt: expiresAt)
        try commit(next); publish()
    }
    func append(run: String, kind: String, detail: String) throws {
        guard !storageFailed else { throw Failure.storage }
        guard snapshot.credential != nil else { throw Failure.pendingRecovery }
        guard snapshot.events.count < 199 else { var next = snapshot; next.terminalError = "QUEUE_FULL"; try commit(next); publish(); throw Failure.full }
        var next = snapshot
        next.events.append(Event(id: UUID().uuidString, run: run, kind: kind, detail: String(detail.prefix(200))))
        if ["dismiss", "failed"].contains(kind) { next.activeRun = nil }
        try commit(next); publish()
    }
    func close() throws {
        try retryStorage()
        var next = snapshot
        if let run = next.activeRun {
            next.events.append(Event(id: UUID().uuidString, run: run, kind: "failed", detail: "SESSION_ENDED"))
            next.activeRun = nil
        }
        next.closing = next.credential != nil; try commit(next); publish()
    }
    /// Deliberate data loss is separate from end() and never produces an acknowledgement.
    func discard() throws {
        try commit(Snapshot()); storageFailed = false; epoch = UUID(); publish()
    }
    func flush(send: Send, httpStatus: (Error) -> Int?) async {
        guard !sending, canRetry, let token = snapshot.credential else { return }
        sending = true; let current = epoch
        publish(.sending)
        defer { sending = false; if current != epoch { publish() } }
        do {
            while let event = snapshot.events.first {
                var attempt = snapshot
                var review = attempt.review ?? InAppTestReviewDetails(runID: event.run)
                if review.runID == nil { review.runID = event.run }
                review.lastAttemptAt = now(); attempt.review = review
                try commit(attempt); publish(.sending)
                try await send("runs/\(event.run)/events", ["event_id": event.id, "kind": event.kind, "detail": event.detail], token)
                guard current == epoch else { return }
                var next = snapshot
                next.events.removeAll { $0.id == event.id }; next.acknowledged += 1
                next.review?.lastReceivedAt = now()
                try commit(next) // A failed write leaves the same ID queued for retry.
                publish(.sending)
            }
            if snapshot.closing {
                do { try await send("end", [:], token) }
                catch { if httpStatus(error) != 401 { throw error } }
                guard current == epoch else { return }
                var next = snapshot; next.credential = nil; next.closing = false
                try commit(next)
            }
            sending = false; publish()
        } catch {
            guard current == epoch else { return }
            let code = httpStatus(error)
            if let code, [400,401,403,404,409,410,422].contains(code) {
                var next = snapshot; next.terminalError = "HTTP_\(code)"
                try? commit(next) // Rejected data stays available until explicit discard.
            }
            sending = false
            publish(.failed, storageFailed ? "STORAGE_ERROR" : snapshot.terminalError ?? code.map { "HTTP_\($0)" } ?? "NETWORK_ERROR")
        }
    }
    private func commit(_ next: Snapshot) throws {
        do { try write(String(decoding: JSONEncoder().encode(next), as: UTF8.self)); snapshot = next; pendingWrite = nil; storageFailed = false }
        catch { pendingWrite = next; storageFailed = true; publish(.failed, "STORAGE_ERROR"); throw error }
    }
    private func publish(_ phase: InAppTestTransferStatus.Phase? = nil, _ reason: String? = nil) {
        let error = reason ?? snapshot.terminalError ?? (storageFailed ? "STORAGE_ERROR" : nil)
        let inferred: InAppTestTransferStatus.Phase = error != nil ? .failed :
            (!snapshot.events.isEmpty || snapshot.closing ? .pending : (snapshot.acknowledged > 0 ? .acknowledged : .idle))
        status = InAppTestTransferStatus(phase: phase ?? inferred, pendingCount: snapshot.events.count,
            acknowledgedCount: snapshot.acknowledged, reason: error,
            canEndSafely: error == nil && !sending && snapshot.events.isEmpty && snapshot.activeRun == nil && !snapshot.closing, review: snapshot.review)
        changed(status)
    }
}
