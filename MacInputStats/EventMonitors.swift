import AppKit
import IOKit.hid

@MainActor
final class EventMonitors: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var store: StatsStore

    // Count distinct scroll gestures — a new gesture starts after 300ms of silence
    private nonisolated(unsafe) static var lastScrollTime: Date = .distantPast
    private static let scrollGestureGap: TimeInterval = 0.3

    // Foreground app screen time tracking
    private var activeApp: String?
    private var activeAppSince: Date?
    private var screenTimeTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

    init(store: StatsStore) {
        self.store = store
    }

    func start() {
        startEventTap()
        startScreenTimeTracking()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        flushScreenTime()
        screenTimeTimer?.invalidate()
        screenTimeTimer = nil
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    private var frontmostAppName: String {
        NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
    }

    // MARK: - CGEvent Tap

    private func startEventTap() {
        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, eventType, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EventMonitors>.fromOpaque(userInfo).takeUnretainedValue()

                // Re-enable the tap if the system disabled it
                if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                DispatchQueue.main.async {
                    monitor.handleCGEvent(type: eventType)
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleCGEvent(type: CGEventType) {
        let app = frontmostAppName

        switch type {
        case .keyDown:
            store.incrementKeystroke(app: app)

        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            store.incrementPointerClick(app: app)

        case .scrollWheel:
            let now = Date()
            if now.timeIntervalSince(Self.lastScrollTime) > Self.scrollGestureGap {
                store.incrementScroll(app: app)
            }
            Self.lastScrollTime = now

        default:
            break
        }
    }

    // MARK: - Screen Time Tracking

    private func startScreenTimeTracking() {
        activeApp = frontmostAppName
        activeAppSince = Date()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.flushScreenTime()
                self.activeApp = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .localizedName ?? "Unknown"
                self.activeAppSince = Date()
            }
        }

        screenTimeTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.flushScreenTime()
                self?.activeAppSince = Date()
            }
        }
    }

    private func flushScreenTime() {
        guard let app = activeApp, let since = activeAppSince else { return }
        let elapsed = Date().timeIntervalSince(since)
        if elapsed > 0.5 {
            store.addScreenTime(elapsed, app: app)
        }
    }
}
