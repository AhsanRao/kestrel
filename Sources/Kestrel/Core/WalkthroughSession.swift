import AppKit
import CoreGraphics
import os

/// Runs one walkthrough: draws the current step, watches for a click inside its target, advances,
/// and stops on Esc or after the last step (spec §8.15).
///
/// Clicks and Esc arrive through a single listen-only `CGEventTap`, which needs Accessibility —
/// the same grant dictation already asks for. Without it the caller falls back to spoken steps.
final class WalkthroughSession {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "walkthrough")
    private let overlay: OverlayWindow

    private var capture: ScreenCapture?
    private var missedClicks = 0
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Called on the main thread when the walkthrough ends, either finished or cancelled.
    var onFinish: ((_ completed: Bool) -> Void)?
    /// Called when the user advances a step, so the panel can follow along.
    var onAdvance: ((_ step: WalkthroughStep) -> Void)?

    var isRunning: Bool { tap != nil }

    init(overlay: OverlayWindow) {
        self.overlay = overlay
    }

    /// Returns false when Accessibility is missing, so the caller can fall back to speech.
    @discardableResult
    func start(_ walkthrough: Walkthrough, capture: ScreenCapture) -> Bool {
        stop(completed: false, notify: false)
        guard TextInjector.hasAccessibilityPermission else {
            log.info("no accessibility permission, cannot follow clicks")
            return false
        }
        guard !walkthrough.steps.isEmpty else { return false }

        self.capture = capture
        missedClicks = 0
        overlay.model.capture = capture
        overlay.model.showsAnyClickHint = false
        overlay.model.space = walkthrough.space
        overlay.model.steps = walkthrough.steps
        overlay.model.goal = walkthrough.goal
        overlay.model.index = 0
        overlay.show(on: capture.displayFrame)

        guard installTap() else {
            overlay.hide()
            return false
        }
        log.info("walkthrough started: \(walkthrough.steps.count) steps")
        return true
    }

    func stop(completed: Bool, notify: Bool = true) {
        removeTap()
        overlay.hide()
        capture = nil
        if notify { onFinish?(completed) }
    }

    // MARK: - Advancing

    /// A click in global AppKit points.
    ///
    /// The hit area is deliberately generous. Models locate controls in a screenshot to within
    /// roughly a button width, so a ring that is slightly off must not trap the user: after a
    /// couple of clicks that miss the ring, the overlay says so and the next click anywhere
    /// advances. The instruction text names the control, so the user is never actually stuck.
    fileprivate func handleClick(at point: CGPoint) {
        guard let capture, let step = overlay.model.currentStep else { return }
        let rect = capture.screenRect(for: step.target, in: overlay.model.space)
        let slack = max(40, min(rect.width, rect.height) * 0.6)
        let target = rect.insetBy(dx: -slack, dy: -slack)

        if !target.contains(point) {
            missedClicks += 1
            overlay.model.showsAnyClickHint = missedClicks >= 2
            guard missedClicks > 2 else { return }
        }
        missedClicks = 0
        overlay.model.showsAnyClickHint = false

        let next = overlay.model.index + 1
        if next < overlay.model.steps.count {
            overlay.model.index = next
            if let advanced = overlay.model.currentStep { onAdvance?(advanced) }
        } else {
            log.info("walkthrough completed")
            stop(completed: true)
        }
    }

    fileprivate func handleEscape() {
        log.info("walkthrough cancelled with Esc")
        stop(completed: false)
    }

    /// CGEvent coordinates are flipped and measured from the top-left of the primary display.
    fileprivate static func appKitPoint(from cgPoint: CGPoint) -> CGPoint {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let height = primary?.frame.height ?? 0
        return CGPoint(x: cgPoint.x, y: height - cgPoint.y)
    }

    // MARK: - Event tap

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: walkthroughTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("could not create event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// C callback for the tap. Listen-only, so the event is always passed straight through.
private let walkthroughTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<WalkthroughSession>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        session.reenableTap()
    case .leftMouseDown, .rightMouseDown:
        let point = WalkthroughSession.appKitPoint(from: event.location)
        DispatchQueue.main.async { session.handleClick(at: point) }
    case .keyDown:
        if event.getIntegerValueField(.keyboardEventKeycode) == 53 {   // Esc
            DispatchQueue.main.async { session.handleEscape() }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
