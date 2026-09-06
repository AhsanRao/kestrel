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

    /// Arrives by falling a few points into place. Short enough not to delay the answer, long
    /// enough that the panel does not appear to teleport.
    private func animateIn(_ panel: NSPanel) {
        let settled = panel.frame
        panel.setFrameOrigin(NSPoint(x: settled.origin.x, y: settled.origin.y + 12))
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
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .titled, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none          // excluded from screen capture
        panel.delegate = self
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2,
                             y: frame.maxY - size.height - 24)
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
