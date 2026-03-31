import Sparkle
import SwiftUI

@main
struct InputStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Dashboard", id: "dashboard") {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .defaultSize(width: 0, height: 0)

        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = StatsStore()
    lazy var eventMonitors = EventMonitors(store: store)
    lazy var micMonitor = SpeechDetector(store: store)
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel<AnyView>?
    private var onboardingWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitors.stop()
        micMonitor.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable state restoration so Dashboard doesn't reappear
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        let needsOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedSetup")
        if !needsOnboarding {
            eventMonitors.start()
            micMonitor.start()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "MenuBarIcon")
            button.image?.isTemplate = true
            #if DEBUG
            button.title = " DEV"
            button.imagePosition = .imageLeading
            #endif
            button.action = #selector(togglePanel)
            button.target = self
        }

        // Hide (don't close) any windows SwiftUI may have opened —
        // a hidden window is needed for NSEvent global monitors to work
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                guard window.level == .normal,
                      !(window is FloatingPanel<AnyView>),
                      window !== self.onboardingWindow else { continue }
                window.orderOut(nil)
            }
        }

        if needsOnboarding {
            showOnboarding()
        }
    }

    func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView {
            UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            // Relaunch so the fresh process picks up TCC permission grants
            self.relaunchApp()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    @objc private func togglePanel() {
        if let panel, panel.isVisible {
            closePanel()
            return
        }

        guard let button = statusItem.button else { return }

        let content = MenuBarView(
            store: store,
            micMonitor: micMonitor,
            updater: updaterController.updater,
            onClose: { [weak self] in self?.closePanel() },
            onShowSetup: { [weak self] in self?.showOnboarding() }
        )

        if let panel {
            panel.updateContent(AnyView(content))
            panel.show(relativeTo: button)
        } else {
            let newPanel = FloatingPanel { AnyView(content) }
            newPanel.onDismiss = { [weak self] in self?.setIconActive(false) }
            newPanel.show(relativeTo: button)
            panel = newPanel
        }

        setIconActive(true)
        panel?.makeKey()
    }

    func relaunchApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func closePanel() {
        panel?.dismiss()
        setIconActive(false)
    }

    private func setIconActive(_ active: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.layer?.backgroundColor = nil
    }
}
