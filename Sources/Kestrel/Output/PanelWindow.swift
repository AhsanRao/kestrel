import AppKit
import SwiftUI

/// The window the island lives in: non-activating, borderless, and hung from the top edge of the
/// display under the mouse (spec §8.11, amended — it was top-*centre* and floating).
///
/// The window follows the island rather than the island fitting the window. AppKit measures a
/// window from its bottom-left corner, so letting it resize itself around growing content pushed
/// the top edge up past the screen and the island off the display; here every size change is
/// applied as an explicit frame whose top edge is pinned to the screen, sprung on the island's own
/// numbers by `PanelFrameAnimator`, which is what makes opening look like one object growing
/// rather than two.
/// `sharingType = .none` keeps it out of every screenshot, including Kestrel's own.
final class PanelWindow: NSObject, NSWindowDelegate {
    let model = PanelModel()

    /// Internal, not private: the motion lives in `PanelWindow+Motion.swift`.
    var panel: NSPanel?
    private var hideTimer: DispatchWorkItem?
    /// The latest a hover may hold the island open. Reading pauses the clock; a pointer left near
    /// the notch is not reading, and without a limit it pins the island there for the rest of the
    /// session.
    private var holdDeadline: Date?
    /// Internal, not private: the motion lives in `PanelWindow+Motion.swift`.
    var frameAnimator: PanelFrameAnimator?
    /// True while the island is rolling back up into the top edge, so a question asked during the
    /// exit can call it off rather than let it finish and order the window out underneath.
    var isLeaving = false
    /// The island's own size, as SwiftUI last measured it.
    private var islandSize: CGSize = .zero
    /// True until the first frame has been placed, so the opening is not animated from nothing.
    var isPlacing = true

    var onOpenPermission: ((URL) -> Void)?

    func show() {
        let panel = ensurePanel()
        cancelHideTimer()
        cancelRollUp(panel)
        let wasVisible = panel.isVisible
        if !wasVisible {
            isPlacing = true
            holdDeadline = nil
        }
        position(panel)
        panel.orderFrontRegardless()
        if !wasVisible { animateIn(panel) }
    }

    /// Ordered out synchronously so the screenshot taken right after cannot contain the panel.
    func hideImmediately() {
        cancelHideTimer()
        holdDeadline = nil
        isLeaving = false
        frameAnimator?.stop()
        panel?.orderOut(nil)
    }

    func hide(after seconds: TimeInterval) {
        cancelHideTimer()
        if holdDeadline == nil {
            holdDeadline = Date().addingTimeInterval(PanelWindow.maximumHold)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Hovering means the user is reading or selecting; keep it up (spec §8.11).
            if self.canHoldForHover {
                self.hide(after: 3)
                return
            }
            self.rollUp()
        }
        hideTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// How long a hover may keep the island on screen past its own clock.
    static let maximumHold: TimeInterval = 90

    /// Whether the pointer resting on the island should still hold it open. Asked by the
    /// coordinator too, which runs the session's clock alongside the window's.
    var canHoldForHover: Bool {
        guard model.isHovering else { return false }
        guard let holdDeadline else { return true }
        return Date() < holdDeadline
    }

    /// Says a line to VoiceOver. The panel never takes focus — that is the point of it — so an
    /// answer arriving is otherwise something a screen reader has no reason to look at.
    func announce(_ text: String) {
        guard !text.isEmpty else { return }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func pulse() {
        model.pulse += 1
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// While Kestrel is clicking on the user's behalf the island must not catch the click: it
    /// sits top-centre, exactly where a browser keeps its address bar, and a click posted there
    /// landed on the island — "typed" text went nowhere, and the model tried again and again.
    func setClickThrough(_ on: Bool) {
        panel?.ignoresMouseEvents = on
    }

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
        frameAnimator = PanelFrameAnimator(window: panel)
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
        guard animated, panel.isVisible, !isPlacing else {
            frameAnimator?.place(size, on: screen)
            return
        }
        // On the island's own spring, so the black shape and the window holding it are one object
        // changing size — and so a size arriving mid-movement redirects it instead of restarting it.
        frameAnimator?.animate(to: size, on: screen)
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
