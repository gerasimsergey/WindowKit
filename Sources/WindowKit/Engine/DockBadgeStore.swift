import Foundation

public final class DockBadgeStore: @unchecked Sendable {
    private var badges: [pid_t: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func badge(forPID pid: pid_t) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return badges[pid]
    }

    public func allBadges() -> [pid_t: String] {
        lock.lock()
        defer { lock.unlock() }
        return badges
    }

    public func setBadge(_ label: String, forPID pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        badges[pid] = label
    }

    public func removeBadge(forPID pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        badges.removeValue(forKey: pid)
    }
}
