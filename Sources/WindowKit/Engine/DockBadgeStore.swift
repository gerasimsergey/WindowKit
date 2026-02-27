import ApplicationServices
import Cocoa

public final class DockBadgeStore: @unchecked Sendable {
    private var badges: [pid_t: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func badge(forPID pid: pid_t) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return badges[pid]
    }

    public func removeBadge(forPID pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        badges.removeValue(forKey: pid)
    }

    public func refresh(forPID pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let appName = app.localizedName else { return }

        guard let dockPID = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" })?
            .processIdentifier else { return }

        let dockApp = AXUIElement.application(pid: dockPID)
        guard let children = try? dockApp.children(),
              let list = children.first(where: { (try? $0.role()) == kAXListRole as String }),
              let dockItems = try? list.children() else { return }

        for item in dockItems {
            guard let subrole = try? item.subrole(),
                  subrole == "AXApplicationDockItem",
                  let title = try? item.title(),
                  title == appName else { continue }

            lock.lock()
            if let statusLabel = try? item.attribute("AXStatusLabel", as: String.self) {
                badges[pid] = statusLabel
            } else {
                badges.removeValue(forKey: pid)
            }
            lock.unlock()
            return
        }

        lock.lock()
        badges.removeValue(forKey: pid)
        lock.unlock()
    }
}
