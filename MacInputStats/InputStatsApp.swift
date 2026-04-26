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

    // Claude Code, Cursor & Codex activity tracking
    let claudeStore = ClaudeSessionStore()
    let cursorStore = CursorSessionStore()
    let codexStore = CodexSessionStore()
    private var claudeServer: ClaudeSocketServer?

    let projectStore = ProjectStore()

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel<AnyView>?
    private var onboardingWindow: NSWindow?
    private var monthlySidePanel: NSPanel?
    private var monthlySideClickMonitor: Any?
    private var settingsSidePanel: NSPanel?
    private var settingsSideClickMonitor: Any?

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
            if event.sessionId.hasPrefix("cursor-") {
                self?.cursorStore.handleEvent(event)
            } else if event.sessionId.hasPrefix("codex-") {
                self?.codexStore.handleEvent(event)
            } else {
                self?.claudeStore.handleEvent(event)
            }
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
                      window !== self.onboardingWindow,
                      window !== self.monthlySidePanel,
                      window !== self.settingsSidePanel else { continue }
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

    private func toggleMonthlyStats() {
        if let existing = monthlySidePanel, existing.isVisible {
            dismissMonthlySidePanel()
            return
        }

        dismissSettingsSidePanel()

        guard let mainPanel = panel, mainPanel.isVisible else { return }

        let view = MonthlyStatsView(
            store: store,
            claudeStore: claudeStore,
            cursorStore: cursorStore,
            codexStore: codexStore,
            projectStore: projectStore,
            onClose: { [weak self] in self?.dismissMonthlySidePanel() }
        )

        let hosting = NSHostingView(rootView: view)
        let fittingSize = hosting.fittingSize

        let sidePanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        sidePanel.isFloatingPanel = true
        sidePanel.level = mainPanel.level
        sidePanel.isOpaque = false
        sidePanel.backgroundColor = .clear
        sidePanel.hasShadow = false
        sidePanel.isMovable = false
        sidePanel.isReleasedWhenClosed = false

        sidePanel.contentView = hosting

        // Position to the left of the main panel with a small gap
        let mainFrame = mainPanel.frame
        let gap: CGFloat = 8
        let x = mainFrame.minX - fittingSize.width - gap
        let y = mainFrame.maxY - fittingSize.height
        sidePanel.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true)

        sidePanel.alphaValue = 0
        sidePanel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sidePanel.animator().alphaValue = 1
        }

        monthlySidePanel = sidePanel

        // Dismiss when clicking outside both panels
        monthlySideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismissMonthlySidePanel()
        }
    }

    private func dismissMonthlySidePanel() {
        if let monitor = monthlySideClickMonitor {
            NSEvent.removeMonitor(monitor)
            monthlySideClickMonitor = nil
        }
        guard let sidePanel = monthlySidePanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            sidePanel.animator().alphaValue = 0
        }, completionHandler: {
            sidePanel.orderOut(nil)
        })
    }

    private func toggleSettings() {
        if let existing = settingsSidePanel, existing.isVisible {
            dismissSettingsSidePanel()
            return
        }

        dismissMonthlySidePanel()

        guard let mainPanel = panel, mainPanel.isVisible else { return }

        let view = SettingsView(
            projectStore: projectStore,
            store: store,
            onClose: { [weak self] in self?.dismissSettingsSidePanel() }
        )

        let hosting = NSHostingView(rootView: view)
        let fittingSize = hosting.fittingSize

        let sidePanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: fittingSize.width, height: fittingSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        sidePanel.isFloatingPanel = true
        sidePanel.level = mainPanel.level
        sidePanel.isOpaque = false
        sidePanel.backgroundColor = .clear
        sidePanel.hasShadow = false
        sidePanel.isMovable = false
        sidePanel.isReleasedWhenClosed = false

        sidePanel.contentView = hosting

        let mainFrame = mainPanel.frame
        let gap: CGFloat = 8
        let x = mainFrame.minX - fittingSize.width - gap
        let y = mainFrame.maxY - fittingSize.height
        sidePanel.setFrame(NSRect(x: x, y: y, width: fittingSize.width, height: fittingSize.height), display: true)

        sidePanel.alphaValue = 0
        sidePanel.orderFront(nil)
        panel?.suppressResignDismiss = true
        sidePanel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            sidePanel.animator().alphaValue = 1
        }

        settingsSidePanel = sidePanel

        DispatchQueue.main.async { [weak self] in
            self?.settingsSideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismissSettingsSidePanel()
            }
        }
    }

    private func dismissSettingsSidePanel() {
        if let monitor = settingsSideClickMonitor {
            NSEvent.removeMonitor(monitor)
            settingsSideClickMonitor = nil
        }
        panel?.suppressResignDismiss = false
        guard let sidePanel = settingsSidePanel else { return }
        self.settingsSidePanel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            sidePanel.animator().alphaValue = 0
        }, completionHandler: {
            sidePanel.orderOut(nil)
        })
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
            cursorStore: cursorStore,
            codexStore: codexStore,
            projectStore: projectStore,
            updater: updaterController.updater,
            onClose: { [weak self] in self?.closePanel() },
            onOpenSettings: { [weak self] in self?.toggleSettings() },
            onOpenMonthlyStats: { [weak self] in self?.toggleMonthlyStats() }
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
        dismissMonthlySidePanel()
        dismissSettingsSidePanel()
        panel?.dismiss()
        setIconActive(false)
    }

    private func setIconActive(_ active: Bool) {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.layer?.backgroundColor = nil
    }
}

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            makeKey()
        }
        super.sendEvent(event)
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
