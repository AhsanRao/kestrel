import AppKit
import SwiftUI

/// Full-screen, transparent, click-through window that hosts the walkthrough drawing (spec §8.15).
/// It sits above everything at `.screenSaver` level, never takes focus, never takes a click, and
/// like the panel is excluded from screen capture so a follow-up question does not photograph it.
final class OverlayWindow {
    let model = OverlayModel()

    private var window: NSWindow?

    func show(on captureFrame: CGRect) {
        let window = ensureWindow()
        window.setFrame(captureFrame, display: true)
        window.orderFrontRegardless()
        model.breathing = true
    }

    func hide() {
        model.breathing = false
        window?.orderOut(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

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
