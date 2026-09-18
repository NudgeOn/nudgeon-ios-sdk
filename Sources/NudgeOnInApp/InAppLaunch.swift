import Foundation

/// Completion of the launch-ad attempt, not of the user's later interaction.
public enum InAppLaunchResult: String, Sendable {
    case shown, noCampaign, timedOut, blocked, cancelled, failed, alreadyHandled
}

/// A process-scoped guard survives SDK owner / Scene recreation. Never persisted to disk.
final class InAppLaunchRegistry: @unchecked Sendable {
    static let process = InAppLaunchRegistry()
    private let lock = NSLock()
    private var handled = Set<String>()
    func claim(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return handled.insert(key).inserted
    }
}

/// Monotonic deadline and one-shot completion; independent of wall-clock / timezone changes.
final class InAppLaunchWindow {
    let deadline: TimeInterval
    private(set) var result: InAppLaunchResult?
    init(timeout: TimeInterval, now: TimeInterval) {
        deadline = now + (timeout.isFinite ? min(10, max(1, timeout)) : 3)
    }
    func canPresent(now: TimeInterval) -> Bool { result == nil && now < deadline }
    func complete(_ value: InAppLaunchResult, now: TimeInterval) -> InAppLaunchResult? {
        guard result == nil else { return nil }
        let effective = now >= deadline && value != .cancelled ? InAppLaunchResult.timedOut : value
        result = effective
        return effective
    }
}
