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

    // Claude Code activity tracking
    let claudeStore = ClaudeSessionStore()
    private var claudeServer: ClaudeSocketServer?

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
        claudeServer?.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable state restoration so Dashboard doesn't reappear
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

        eventMonitors.start()
        micMonitor.start()

        // Claude Code activity tracking
        HookInstaller.install()
        claudeServer = ClaudeSocketServer { [weak self] event in
            self?.claudeStore.handleEvent(event)
        }
        claudeServer?.start()

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

        // Show onboarding on first launch
        if !UserDefaults.standard.bool(forKey: "hasCompletedSetup") {
            showOnboarding()
        }
    }

    private func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
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
            claudeStore: claudeStore,
            updater: updaterController.updater,
            onClose: { [weak self] in self?.closePanel() },
            onOpenSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === onboardingWindow else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        onboardingWindow = nil
    }
}
