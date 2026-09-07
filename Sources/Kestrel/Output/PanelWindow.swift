import AppKit
import SwiftUI

/// The window the island lives in: non-activating, borderless, and hung from the top edge of the
/// display under the mouse (spec §8.11, amended — it was top-*centre* and floating).
///
/// The window follows the island rather than the island fitting the window. AppKit measures a
/// window from its bottom-left corner, so letting it resize itself around growing content pushed
/// the top edge up past the screen and the island off the display; here every size change is
/// applied as an explicit frame whose top edge is pinned to the screen, and animated, which is
/// also what makes opening look like one object growing rather than two.
/// `sharingType = .none` keeps it out of every screenshot, including Kestrel's own.
final class PanelWindow: NSObject, NSWindowDelegate {
    let model = PanelModel()

    /// Internal, not private: the motion lives in `PanelWindow+Motion.swift`.
    var panel: NSPanel?
    private var hideTimer: DispatchWorkItem?
    /// Internal, not private: the motion lives in `PanelWindow+Motion.swift`.
    var levelTimer: Timer?
    /// The island's own size, as SwiftUI last measured it.
    private var islandSize: CGSize = .zero
    /// True until the first frame has been placed, so the opening is not animated from nothing.
    var isPlacing = true

    var onOpenPermission: ((URL) -> Void)?

    func show() {
        let panel = ensurePanel()
        cancelHideTimer()
        let wasVisible = panel.isVisible
        if !wasVisible { isPlacing = true }
        position(panel)
        panel.orderFrontRegardless()
        if !wasVisible { animateIn(panel) }
        startLevelAnimation()
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
        // Off deliberately: the window is placed by `apply(size:)`, pinned to the top of the
        // screen. Letting AppKit size it from the content as well means two owners of one frame,
        // and the one that measures from the bottom-left wins by moving the island off screen.
        hosting.sizingOptions = []
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
        model.onSizeChange = { [weak self] size in self?.apply(size: size) }
        // Hung off the top edge of the display, not floated near it: dragging it away would break
        // the one thing that makes it read as part of the machine.
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // AppKit derives the shadow from the alpha of what is drawn, so the rounded card casts a
        // correct one outside the window. A SwiftUI shadow would be clipped by the window bounds.
        // The island draws its own shadow: a window shadow would be cast by the window's rectangle,
        // and the whole point of the shape is that its corners are not the window's corners.
        panel.hasShadow = false
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
        // The notch is read before the layout, because the island's own width depends on it.
        let notch = NotchMetrics.current()
        if model.notch != notch { model.notch = notch }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = panel.contentViewController?.view.fittingSize ?? .zero
        let size = islandSize.height > 1 ? islandSize : fitting
        apply(size: size, animated: false)
    }

    /// Places the window at the size the island reported, flush with the top of the display — the
    /// real top, not the visible frame, which starts below the menu bar — and centred on the
    /// housing.
    private func apply(size: CGSize, animated: Bool = true) {
        guard size.width > 1, size.height > 1 else { return }
        islandSize = size
        guard let panel else { return }
        let screen = model.notch.screenFrame
        guard screen.width > 0 else { return }
        // The island sits at the top of the window with a margin around the rest of it, so the
        // window's own top edge is the island's top edge.
        let frame = NSRect(x: (screen.midX - size.width / 2).rounded(),
                           y: (screen.maxY - size.height).rounded(),
                           width: size.width.rounded(), height: size.height.rounded())
        guard frame != panel.frame else { return }
        guard animated, panel.isVisible, !isPlacing else {
            panel.setFrame(frame, display: true)
            return
        }
        // Matched to the island's own spring closely enough that the black shape and the window
        // holding it appear to be the same object changing size.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(frame, display: true)
        }
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
