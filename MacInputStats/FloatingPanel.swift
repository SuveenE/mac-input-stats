import AppKit
import SwiftUI

/// Hit test view that only responds to clicks within the visible panel shape.
/// Clicks outside pass through to the menu bar and other apps.
final class PanelHitTestView: NSView {
    var activeRect: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return nil }
        let screenPoint = window.convertPoint(toScreen: convert(point, to: nil))
        guard activeRect.contains(screenPoint) else { return nil }
        return super.hitTest(point)
    }
}

/// Transparent NSHostingView that strips out AppKit's default background.
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((CGSize) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.clearBackgroundViews()
        }
    }

    override func layout() {
        super.layout()
        clearBackgroundViews()
        onSizeChange?(fittingSize)
    }

    private func clearBackgroundViews() {
        for child in subviews {
            let name = String(describing: type(of: child))
            if name.contains("BackgroundColor") || name.contains("Background") {
                child.wantsLayer = true
                child.layer?.backgroundColor = .clear
                child.isHidden = true
            }
        }
    }
}

/// A borderless, floating NSPanel that renders above the menu bar.
final class FloatingPanel<Content: View>: NSPanel {
    private let hostingView: TransparentHostingView<Content>
    private let hitTestView = PanelHitTestView()
    var onDismiss: (() -> Void)?
    var suppressResignDismiss = false

    /// The top edge of the panel in screen coordinates (kept fixed during resize).
    private var anchoredTopY: CGFloat = 0
    private var panelWidth: CGFloat = 340
    private var lastKnownHeight: CGFloat = 0
    private var readyForResize = false

    init(content: () -> Content) {
        hostingView = TransparentHostingView(rootView: content())

        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .mainMenu + 3
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        hitTestView.wantsLayer = true
        hitTestView.layer?.backgroundColor = .clear

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hitTestView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: hitTestView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: hitTestView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: hitTestView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: hitTestView.trailingAnchor),
        ])

        contentView = hitTestView

        hostingView.onSizeChange = { [weak self] newSize in
            guard let self, self.readyForResize else { return }
            let h = max(newSize.height, 100)
            // Only resize if height changed meaningfully
            if abs(h - self.lastKnownHeight) > 2 {
                self.resizeKeepingTop(newHeight: h)
            }
        }
    }

    func updateContent(_ content: Content) {
        hostingView.rootView = content
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonBoundsInWindow = button.convert(button.bounds, to: nil)
        let buttonScreenRect = buttonWindow.convertToScreen(buttonBoundsInWindow)

        readyForResize = false

        let fittingSize = hostingView.fittingSize
        let panelHeight = max(fittingSize.height, 100)
        lastKnownHeight = panelHeight

        let x = buttonScreenRect.midX - panelWidth / 2
        // Top edge flush below the button (overlap 1px for seamless join)
        anchoredTopY = buttonScreenRect.minY + 1
        let y = anchoredTopY - panelHeight

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        hitTestView.activeRect = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.readyForResize = true
        })
    }

    /// Resize the panel while keeping the top edge anchored to the menu bar.
    private func resizeKeepingTop(newHeight: CGFloat) {
        guard isVisible else { return }
        lastKnownHeight = newHeight
        let currentFrame = frame
        let newY = anchoredTopY - newHeight

        let newFrame = NSRect(x: currentFrame.origin.x, y: newY, width: panelWidth, height: newHeight)
        setFrame(newFrame, display: true, animate: true)
        hitTestView.activeRect = newFrame
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    override func resignKey() {
        super.resignKey()
        if suppressResignDismiss { return }
        dismiss()
        onDismiss?()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
