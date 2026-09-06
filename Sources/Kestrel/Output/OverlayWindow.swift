import AppKit
import SwiftUI

/// Full-screen, transparent, click-through window that hosts the walkthrough drawing (spec §8.15).
/// It sits above everything at `.screenSaver` level, never takes focus, never takes a click, and
/// like the panel is excluded from screen capture so a follow-up question does not photograph it.
final class OverlayWindow {
    let model = OverlayModel()

    private var window: NSWindow?

    /// Covers every display, not just the window that was photographed.
    ///
    /// The screenshot Kestrel sends is usually the front window alone, and the first step of a
    /// route is very often in the menu bar — outside that window. An overlay sized to the capture
    /// clipped exactly the mark the user needed most, so it spans the whole desktop instead and the
    /// marks are placed from global coordinates.
    func show() {
        let bounds = OverlayModel.desktopBounds
        model.windowFrame = bounds
        let window = ensureWindow()
        window.setFrame(bounds, display: true)
        window.orderFrontRegardless()
        model.breathing = true
    }

    func hide() {
        model.breathing = false
        window?.orderOut(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// For `OverlayPreview` only: lift the capture exclusion so the drawing can be photographed.
    func setExcludedFromCapture(_ excluded: Bool) {
        window?.sharingType = excluded ? .none : .readOnly
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true           // click-through: the app underneath still gets it
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}
