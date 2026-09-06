import AppKit
import SwiftUI

/// Non-activating floating panel, top-center of the display under the mouse (spec §8.11).
/// `sharingType = .none` keeps it out of every screenshot, including Kestrel's own.
final class PanelWindow: NSObject, NSWindowDelegate {
    let model = PanelModel()

    private var panel: NSPanel?
    private var hideTimer: DispatchWorkItem?
    private var levelTimer: Timer?

    var onOpenPermission: ((URL) -> Void)?

    func show() {
        let panel = ensurePanel()
        cancelHideTimer()
        let wasVisible = panel.isVisible
        position(panel)
        panel.orderFrontRegardless()
        if !wasVisible { animateIn(panel) }
        startLevelAnimation()
    }

    /// Arrives by dropping out of the top edge of the screen, so it reads as the notch opening
    /// rather than as a window appearing somewhere near it.
    private func animateIn(_ panel: NSPanel) {
        let settled = panel.frame
        panel.setFrameOrigin(NSPoint(x: settled.origin.x, y: settled.origin.y + settled.height))
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(settled, display: true)
        }
    }

    /// Fades out when it is leaving of its own accord, rather than blinking off.
    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        stopLevelAnimation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, let panel = self.panel, panel.alphaValue < 0.05 else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
        }
    }

    /// Ordered out synchronously so the screenshot taken right after cannot contain the panel.
    func hideImmediately() {
        cancelHideTimer()
        stopLevelAnimation()
        panel?.orderOut(nil)
    }

    func hide(after seconds: TimeInterval) {
        cancelHideTimer()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Hovering means the user is reading or selecting; keep it up (spec §8.11).
            if self.model.isHovering {
                self.hide(after: 3)
                return
            }
            self.fadeOut()
        }
        hideTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func pulse() {
        model.pulse += 1
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// For `PanelPreview` only: the window's number, and a way to lift the capture exclusion for
    /// long enough to photograph it.
    var windowNumber: Int? { panel?.windowNumber }
    var screenFrame: CGRect? { panel?.frame }

    func setExcludedFromCapture(_ excluded: Bool) {
        panel?.sharingType = excluded ? .none : .readOnly
    }

    // MARK: - Private

    private func cancelHideTimer() {
        hideTimer?.cancel()
        hideTimer = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let hosting = NSHostingController(rootView: PanelView(model: model) { [weak self] url in
            self?.onOpenPermission?(url)
        })
        // The panel grows as an answer arrives; letting AppKit follow SwiftUI's layout each frame
        // makes that a resize rather than a jump.
        hosting.sizingOptions = [.preferredContentSize]
        // Borderless, not a titled window with its titlebar hidden. A titled NSPanel still installs
        // a titlebar view above the content: with a clear window background and a rounded card
        // inside, that showed as a broken strip across the top edge. `.fullSizeContentView` only
        // means anything alongside `.titled`, so it goes too.
        // Built with its style mask, not assigned one afterwards: a borderless panel created
        // through `init(contentViewController:)` and restyled later ends up 1×0 points, because it
        // never picks up the hosting view's size.
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
                                  styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: false)
        panel.contentViewController = hosting
        panel.setContentSize(hosting.view.fittingSize)
        // Hung off the top edge of the display, not floated near it: dragging it away would break
        // the one thing that makes it read as part of the machine.
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // AppKit derives the shadow from the alpha of what is drawn, so the rounded card casts a
        // correct one outside the window. A SwiftUI shadow would be clipped by the window bounds.
        panel.hasShadow = true
        // Above the menu bar, or the panel would slide *under* the strip it is supposed to grow out
        // of. `.nonactivatingPanel` still keeps the user's app frontmost.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)))
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none          // excluded from screen capture
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        // The notch is read before the layout, because the panel's own width depends on it.
        let notch = NotchMetrics.current()
        if model.notch != notch { model.notch = notch }
        // Lay out before measuring, or the first showing is positioned against a stale size.
        panel.contentView?.layoutSubtreeIfNeeded()
        if let fitting = panel.contentViewController?.view.fittingSize, fitting.height > 1 {
            panel.setContentSize(fitting)
        }
        guard notch.screenFrame.width > 0 else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        // Flush with the very top of the display — not the visible frame, which starts below the
        // menu bar — and centred on the housing.
        let origin = NSPoint(x: notch.screenFrame.midX - size.width / 2,
                             y: notch.screenFrame.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    /// Cheap breathing animation while recording; no audio metering, so no extra tap on the input.
    private func startLevelAnimation() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.model.isRecording else { self.model.levelPhase = 0; return }
            self.model.levelPhase = self.model.levelPhase > 0.5 ? 0 : 1
        }
    }

    private func stopLevelAnimation() {
        levelTimer?.invalidate()
        levelTimer = nil
        model.levelPhase = 0
    }
}

/// A borderless panel that can still take the keyboard.
///
/// Borderless windows refuse key status by default, which would make the answer text unselectable
/// and the permission button unclickable. `.nonactivatingPanel` keeps it from activating Kestrel,
/// so the app the user was working in stays frontmost either way.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
