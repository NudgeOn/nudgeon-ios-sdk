import Foundation

/// Reject concurrent owners of the same mutable snapshot within one app process.
final class InAppTestStoreLease {
    private static let lock = NSLock()
    private static var owners = Set<String>()
    private let key: String
    init(_ key: String) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard Self.owners.insert(key).inserted else { throw LeaseError.alreadyOwned }
        self.key = key
    }
    deinit { Self.lock.lock(); Self.owners.remove(key); Self.lock.unlock() }
    enum LeaseError: Error { case alreadyOwned }
}
