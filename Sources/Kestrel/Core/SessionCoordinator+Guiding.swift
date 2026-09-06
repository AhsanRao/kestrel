import AppKit
import Foundation

/// Showing a route instead of describing one: drawing it, following the user through it, and
/// picking it up again when it runs off the edge of this screen.
extension SessionCoordinator {
    /// Drawn walkthrough, with a spoken fallback whenever the drawing cannot be trusted.
    func present(_ walkthrough: Walkthrough) {
        guard let capture = pendingCapture else { return spokenFallback(walkthrough) }

        let resolved = WalkthroughResolver.resolve(walkthrough, elements: scannedElements, capture: capture)
        // Steps are kept even when they cannot be placed yet, so the route survives to its end;
        // but if not one of them can be drawn, there is nothing to show and it is read out instead.
        guard resolved.contains(where: { $0.frame != nil }) else { return spokenFallback(walkthrough) }
        var usable = walkthrough
        // Deliberately not re-sanitized: `frames` is parallel to these steps, and dropping one here
        // would slide every mark onto the wrong instruction.
        usable.steps = resolved.map(\.step)
        let frames = resolved.map(\.frame)
        log.debug("walkthrough: \(resolved.filter(\.isExact).count)/\(resolved.count) steps located")

        guard self.walkthrough.start(usable, frames: frames, capture: capture) else {
            // Following clicks needs Accessibility; ask once, then read the steps out instead.
            TextInjector.requestAccessibilityPermission()
            return spokenFallback(walkthrough)
        }
        panel.model.answer = WalkthroughParser.spokenSummary(usable)
        apply(.walkthroughReady)
        render()
        panel.hideImmediately()          // the overlay is the UI now
        speakStep(usable.steps[0])
    }

    /// The route reached the end of what this screen could show, and said so. Rather than leaving
    /// the user in front of a freshly opened menu with the drawing gone, Kestrel photographs the
    /// new screen and asks for the next stretch of the same goal.
    func continueWalkthrough(after done: Walkthrough) {
        guard walkthroughContinuations < SessionCoordinator.maximumContinuations else {
            log.info("walkthrough continuation limit reached")
            return walkthroughEnded()
        }
        walkthroughContinuations += 1
        apply(.walkthroughContinuing)
        let goal = done.goal
        let covered = done.steps.map(\.instruction).joined(separator: "; ")
        let maxEdge = config.screenshotMaxEdge
        let mode = config.captureMode
        work.async { [weak self] in
            guard let self else { return }
            do {
                // The screen has moved on, so the old screenshot and the old control list are both
                // stale; everything the next stretch is planned from is taken again here.
                let capture = try ScreenGrabber.capture(maxEdge: maxEdge, mode: mode)
                DispatchQueue.main.sync { self.pendingCapture = capture }
                self.runAsk("Continue showing me how to \(goal). Already done: \(covered). "
                            + "Give only the steps that come next.", asWalkthrough: true)
            } catch {
                DispatchQueue.main.async { self.walkthroughEnded() }
            }
        }
    }

    private func spokenFallback(_ walkthrough: Walkthrough) {
        discardCapture()
        let summary = WalkthroughParser.spokenSummary(walkthrough)
        present(Answer(text: summary, raw: summary, durationMs: 0, steps: walkthrough.steps))
    }

    func walkthroughAdvanced(to step: WalkthroughStep) {
        apply(.walkthroughAdvanced)
        speakStep(step)
    }

    func walkthroughEnded() {
        walkthroughContinuations = 0
        apply(.walkthroughFinished)
        render()
    }

    private func speakStep(_ step: WalkthroughStep) {
        guard config.speakAnswers else { return }
        speech.speak(step.instruction, config: config)
    }
}
