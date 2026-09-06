import AppKit
import CoreGraphics
import os

/// Runs one walkthrough: draws the current step, watches for a click inside its target, advances,
/// and stops on Esc or after the last step (spec §8.15).
///
/// Clicks and Esc arrive through a single listen-only `CGEventTap`, which needs Accessibility —
/// the same grant dictation already asks for. Without it the caller falls back to spoken steps.
final class WalkthroughSession {
    let log = Logger(subsystem: "dev.0xash.kestrel", category: "walkthrough")
    private let overlay: OverlayWindow

    private let scanner = DispatchQueue(label: "dev.0xash.kestrel.walkthrough.scan", qos: .userInitiated)

    private var capture: ScreenCapture?
    private var missedClicks = 0
    /// Internal, not private: the tap itself lives in `WalkthroughTap.swift`.
    var tap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    /// Bumped on every advance so a relocation scan started for an earlier step is discarded.
    private var generation = 0
    private var needsMore = false
    /// The walkthrough currently on screen, kept so a `needs_more` hand-off knows what was shown.
    private var pending: Walkthrough?

    /// Called on the main thread when the walkthrough ends, either finished or cancelled.
    var onFinish: ((_ completed: Bool) -> Void)?
    /// Called when the user advances a step, so the panel can follow along.
    var onAdvance: ((_ step: WalkthroughStep) -> Void)?
    /// The route ran out on this screen but the goal is not reached. The coordinator takes a fresh
    /// screenshot and asks for the rest, so the user is not left staring at a finished overlay.
    var onNeedsMore: ((_ walkthrough: Walkthrough) -> Void)?

    var isRunning: Bool { tap != nil }

    init(overlay: OverlayWindow) {
        self.overlay = overlay
    }

    /// Returns false when Accessibility is missing, so the caller can fall back to speech.
    @discardableResult
    func start(_ walkthrough: Walkthrough, frames: [CGRect?], capture: ScreenCapture) -> Bool {
        stop(completed: false, notify: false)
        guard TextInjector.hasAccessibilityPermission else {
            log.info("no accessibility permission, cannot follow clicks")
            return false
        }
        guard !walkthrough.steps.isEmpty else { return false }

        self.capture = capture
        self.needsMore = walkthrough.needs_more == true
        self.pending = walkthrough
        missedClicks = 0
        generation += 1
        overlay.model.showsAnyClickHint = false
        overlay.model.frames = frames
        overlay.model.steps = walkthrough.steps
        overlay.model.goal = walkthrough.goal
        overlay.model.needsMore = needsMore
        overlay.model.index = 0
        overlay.show()

        guard installTap() else {
            overlay.hide()
            return false
        }
        log.info("walkthrough started: \(walkthrough.steps.count) steps")
        // The first step may itself point at something that only exists now — a menu the user had
        // already opened, say — so the same live scan runs for it as for every later step.
        relocateCurrentStep()
        return true
    }

    func stop(completed: Bool, notify: Bool = true) {
        removeTap()
        overlay.hide()
        capture = nil
        generation += 1
        let unfinished = completed && needsMore
        let walkthrough = pending
        needsMore = false
        pending = nil
        if unfinished, let walkthrough {
            onNeedsMore?(walkthrough)
            return
        }
        if notify { onFinish?(completed) }
    }

    // MARK: - Advancing

    /// A click in global AppKit points.
    ///
    /// The hit area is deliberately generous. Models locate controls in a screenshot to within
    /// roughly a button width, so a ring that is slightly off must not trap the user: after a
    /// couple of clicks that miss the ring, the overlay says so and the next click anywhere
    /// advances. The instruction text names the control, so the user is never actually stuck.
    func handleClick(at point: CGPoint) {
        guard overlay.model.currentStep != nil else { return }
        // A step whose control could not be found is described, not drawn, so any click is taken as
        // "done that". Refusing to advance would strand the user on a step with nothing to aim at.
        if let rect = overlay.model.currentFrame {
            // A frame straight from Accessibility is exact, so it needs far less slack than an estimate.
            let exact = overlay.model.currentStep?.element != nil || overlay.model.isCurrentFrameLive
            let slack = exact ? 8 : max(40, min(rect.width, rect.height) * 0.6)
            if !rect.insetBy(dx: -slack, dy: -slack).contains(point) {
                missedClicks += 1
                overlay.model.showsAnyClickHint = missedClicks >= 2
                guard missedClicks > 2 else { return }
            }
        }
        missedClicks = 0
        overlay.model.showsAnyClickHint = false

        let next = overlay.model.index + 1
        if next < overlay.model.steps.count {
            overlay.model.index = next
            generation += 1
            if let advanced = overlay.model.currentStep { onAdvance?(advanced) }
            relocateCurrentStep()
        } else {
            log.info("walkthrough completed")
            stop(completed: true)
        }
    }

    // MARK: - Live re-targeting

    /// Finds the current step's control on the screen as it is *now*.
    ///
    /// This is the fix for a route that died at step one: the frames worked out when the answer
    /// arrived describe the screen before the user clicked anything, and a menu item does not exist
    /// until its menu is open. So after every advance the Accessibility tree is read again and the
    /// step's control is matched by name. The scan is retried a few times because menus open with
    /// an animation, and the first read can land before the items are there.
    private func relocateCurrentStep(attempt: Int = 0) {
        guard let step = overlay.model.currentStep else { return }
        // A step the model picked out of the control list already has the frame macOS reported for
        // that exact control. Looking it up again by name could only find a different control with
        // the same words on it, so it is left alone.
        guard step.element == nil || overlay.model.currentFrame == nil else { return }
        let mine = generation
        let delays: [Double] = [0.18, 0.45, 0.9, 1.6]
        guard attempt < delays.count else { return }
        // Menu items live one level deeper than the list the model chose from, and this is exactly
        // where they matter, so the live scan reaches further down than the planning scan did.
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self, self.isRunning, mine == self.generation else { return }
            self.scanner.async { [weak self] in
                let elements = AXElementScanner.scanFrontmostApp(menuDepth: AXElementScanner.deepMenuDepth)
                DispatchQueue.main.async {
                    guard let self, self.isRunning, mine == self.generation else { return }
                    if let frame = WalkthroughResolver.relocate(step, in: elements) {
                        self.overlay.model.setLiveFrame(frame)
                        self.log.debug("relocated step \(step.n) live")
                    } else {
                        self.relocateCurrentStep(attempt: attempt + 1)
                    }
                }
            }
        }
    }

    func handleEscape() {
        log.info("walkthrough cancelled with Esc")
        stop(completed: false)
    }

    /// CGEvent coordinates are flipped and measured from the top-left of the primary display.
    static func appKitPoint(from cgPoint: CGPoint) -> CGPoint {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let height = primary?.frame.height ?? 0
        return CGPoint(x: cgPoint.x, y: height - cgPoint.y)
    }
}
