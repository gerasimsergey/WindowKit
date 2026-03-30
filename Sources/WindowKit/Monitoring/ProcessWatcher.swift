import Cocoa
import Combine

public enum ProcessEvent: Sendable {
    case applicationWillLaunch(NSRunningApplication)
    case applicationLaunched(NSRunningApplication)
    case applicationTerminated(pid_t)
    case applicationActivated(NSRunningApplication)
    case applicationDeactivated(NSRunningApplication)
    case spaceChanged
    case showDesktopEntered
    case showDesktopExited
}

public final class ProcessWatcher {
    public let events: AnyPublisher<ProcessEvent, Never>
    private let eventSubject = PassthroughSubject<ProcessEvent, Never>()
    private var observations: [NSObjectProtocol] = []

    private var dockObserver: AXObserver?
    private var dockElement: AXUIElement?

    public private(set) var frontmostApplication: NSRunningApplication?
    public private(set) var isShowingDesktop: Bool = false

    public init() {
        self.events = eventSubject.eraseToAnyPublisher()
        frontmostApplication = NSWorkspace.shared.frontmostApplication
        setupObservers()
        setupDockObserver()
    }

    deinit { stopWatching() }

    public func startWatching() {
        guard observations.isEmpty else { return }
        setupObservers()
        setupDockObserver()
    }

    public func stopWatching() {
        let center = NSWorkspace.shared.notificationCenter
        observations.forEach { center.removeObserver($0) }
        observations.removeAll()
        teardownDockObserver()
    }

    public func runningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    }

    private func setupObservers() {
        let center = NSWorkspace.shared.notificationCenter

        observations.append(center.addObserver(
            forName: NSWorkspace.willLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.eventSubject.send(.applicationWillLaunch(app))
        })

        observations.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.eventSubject.send(.applicationLaunched(app))
        })

        observations.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.eventSubject.send(.applicationTerminated(app.processIdentifier))
        })

        observations.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self.frontmostApplication = app
            self.eventSubject.send(.applicationActivated(app))
        })

        observations.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular else { return }
            self?.eventSubject.send(.applicationDeactivated(app))
        })

        observations.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.eventSubject.send(.spaceChanged)
        })
    }

    // MARK: - Dock AX Observer (Show Desktop)

    private static let dockShowDesktop = "AXExposeShowDesktop"
    private static let dockExposeExit = "AXExposeExit"

    private func setupDockObserver() {
        guard dockObserver == nil else { return }

        guard let dockApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.dock"
        ).first else { return }

        let dockPID = dockApp.processIdentifier
        let element = AXUIElementCreateApplication(dockPID)
        self.dockElement = element

        var observer: AXObserver?
        let result = AXObserverCreate(dockPID, dockAXCallback, &observer)
        guard result == .success, let observer else { return }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, Self.dockShowDesktop as CFString, userData)
        AXObserverAddNotification(observer, element, Self.dockExposeExit as CFString, userData)

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )

        self.dockObserver = observer
    }

    private func teardownDockObserver() {
        guard let observer = dockObserver, let element = dockElement else { return }
        AXObserverRemoveNotification(observer, element, Self.dockShowDesktop as CFString)
        AXObserverRemoveNotification(observer, element, Self.dockExposeExit as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        dockObserver = nil
        dockElement = nil
    }

    fileprivate func handleDockNotification(_ name: String) {
        switch name {
        case Self.dockShowDesktop:
            isShowingDesktop = true
            eventSubject.send(.showDesktopEntered)
        case Self.dockExposeExit:
            guard isShowingDesktop else { return }
            isShowingDesktop = false
            eventSubject.send(.showDesktopExited)
        default:
            break
        }
    }
}

private let dockAXCallback: AXObserverCallback = { _, _, notification, userData in
    guard let userData else { return }
    let watcher = Unmanaged<ProcessWatcher>.fromOpaque(userData).takeUnretainedValue()
    watcher.handleDockNotification(notification as String)
}
