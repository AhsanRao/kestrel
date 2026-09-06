import AppKit
import SwiftUI

/// Shows what Kestrel is about to touch while it works.
///
/// Automation that happens invisibly is unnerving, and unnerving is the same as untrustworthy. A
/// marker on the control, the action in words, the step count, and Esc to stop — that is the whole
/// contract, and it is why HeyClicky draws an agent cursor too.
final class AgentOverlay {
    let model = AgentOverlayModel()
    private var window: NSWindow?

    func show() {
        let window = ensureWindow()
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }
        model.origin = screen.frame.origin
        model.size = screen.frame.size
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        model.reset()
        window?.orderOut(nil)
    }

    var isVisible: Bool { window?.isVisible ?? false }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: AgentOverlayView(model: model))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}

/// Drawing state for the agent overlay, and the small amount of logic worth testing.
final class AgentOverlayModel: ObservableObject {
    @Published var goal: String = ""
    @Published var describe: String = ""
    @Published var stepIndex: Int = 0
    @Published var stepCount: Int = 0
    /// Where the current control is, in global AppKit points.
    @Published var target: CGRect?
    @Published var isFinishing = false

    var origin: CGPoint = .zero
    var size: CGSize = .zero

    /// "Step 2 of 5" — or nothing when there is only one thing to do.
    var progress: String {
        guard stepCount > 1 else { return "" }
        return "Step \(min(stepIndex + 1, stepCount)) of \(stepCount)"
    }

    /// The target in the overlay window's top-left drawing space.
    var targetInView: CGRect? {
        guard let target else { return nil }
        return CGRect(x: target.minX - origin.x,
                      y: size.height - (target.maxY - origin.y),
                      width: target.width, height: target.height)
    }

    func begin(goal: String, stepCount: Int) {
        self.goal = goal
        self.stepCount = stepCount
        stepIndex = 0
        describe = ""
        target = nil
        isFinishing = false
    }

    func show(_ action: Action, at frame: CGRect?, index: Int) {
        describe = action.describe
        stepIndex = index
        target = frame
    }

    func reset() {
        goal = ""
        describe = ""
        stepIndex = 0
        stepCount = 0
        target = nil
        isFinishing = false
    }
}
