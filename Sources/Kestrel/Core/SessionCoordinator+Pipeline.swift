import AppKit
import Foundation

/// The transcribe → think → answer / clean → paste half of the session loop.
/// Split from `SessionCoordinator` only to keep both files readable.
extension SessionCoordinator {
    // MARK: - Pipeline

    func transcribe(_ wav: URL, intent: SessionIntent) {
        defer { try? FileManager.default.removeItem(at: wav) }
        let started = Date()
        do {
            let text = try transcriber.transcribe(wav, config: config)
            log.debug("transcript in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            guard !text.isEmpty else {
                DispatchQueue.main.async {
                    self.discardCapture()
                    self.apply(.transcriptionEmpty)
                    self.render()
                }
                return
            }
            DispatchQueue.main.async {
                self.panel.model.transcript = text
                self.apply(.transcribed(intent))
                self.render()
            }
            switch intent {
            case .ask: runAsk(text)
            case .dictation: runDictation(text)
            }
        } catch {
            finish(with: error)
        }
    }

    func runAsk(_ text: String) {
        // "How do I …?" is a request to be shown, not told (spec §8.15).
        let wantsSteps = WalkthroughDetector.wantsWalkthrough(text, config: config)
        // Walkthroughs get a gridded copy of the screenshot: the model reads coordinates off the
        // printed lines instead of guessing them. The user's own view is never touched.
        var gridded: URL?
        if wantsSteps, let original = pendingCapture?.url { gridded = GridAnnotator.annotate(original) }
        defer { if let gridded { try? FileManager.default.removeItem(at: gridded) } }

        let query = Query(text: text, screenshot: gridded ?? pendingCapture?.url,
                          mode: wantsSteps ? .walkthrough : .ask)
        do {
            let answer = try router.ask(query, config: config)
            DispatchQueue.main.async {
                if wantsSteps, let walkthrough = WalkthroughParser.parse(answer.text) {
                    self.present(walkthrough)
                } else {
                    self.discardCapture()
                    self.present(answer)
                }
            }
        } catch is CancellationError {
            discardCapture()
        } catch {
            discardCapture()
            finish(with: error)
        }
    }

    /// Plain spoken answer.
    func present(_ answer: Answer) {
        panel.model.answer = answer.text
        apply(.answered)
        render()
        if config.speakAnswers, speech.speak(answer.text, config: config) { return }
        scheduleAutoHide()
    }

    /// Drawn walkthrough, with a spoken fallback whenever the drawing cannot be trusted.
    func present(_ walkthrough: Walkthrough) {
        guard let capture = pendingCapture else { return spokenFallback(walkthrough) }
        var usable = walkthrough
        let space = walkthrough.space
        usable.steps = walkthrough.steps.filter { ScreenCapture.isPlausible($0.target, in: space) }
        guard !usable.steps.isEmpty else { return spokenFallback(walkthrough) }
        usable.steps = WalkthroughParser.sanitize(usable.steps)

        guard self.walkthrough.start(usable, capture: capture) else {
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
        apply(.walkthroughFinished)
        render()
    }

    private func speakStep(_ step: WalkthroughStep) {
        guard config.speakAnswers else { return }
        speech.speak(step.instruction, config: config)
    }

    func runDictation(_ text: String) {
        var output = text
        if config.cleanupDictation {
            // A cleanup failure must never cost the user their words: fall back to the raw transcript.
            if let cleaned = try? router.ask(Query(text: text, mode: .dictationCleanup), config: config),
               !cleaned.text.isEmpty {
                output = cleaned.text
            } else {
                log.info("cleanup failed, injecting raw transcript")
            }
        }
        DispatchQueue.main.async {
            do {
                try TextInjector.inject(output, mode: self.config.injectMode)
                self.panel.model.transcript = output
                self.apply(.injected)
                self.render()
                self.panel.hide(after: 3)
            } catch {
                self.fail(error)
            }
        }
    }

    // MARK: - Finishing

    func discardCapture() {
        if let capture = pendingCapture { try? FileManager.default.removeItem(at: capture.url) }
        pendingCapture = nil
    }

    func finish(with error: Error) {
        DispatchQueue.main.async { self.fail(error) }
    }

    func fail(_ error: Error) {
        discardCapture()
        let kestrelError = error as? KestrelError
        let message = kestrelError?.errorDescription ?? error.localizedDescription
        log.error("\(message, privacy: .public)")
        panel.model.permissionURL = kestrelError?.settingsURL
        apply(.failed(message))
        render()
        panel.show()
        panel.hide(after: 8)
    }

    func reset() {
        panel.model.transcript = ""
        panel.model.answer = ""
        panel.model.permissionURL = nil
        discardCapture()
    }

    func scheduleAutoHide() {
        guard case .answering = machine.state else { return }
        panel.hide(after: TimeInterval(config.panelAutoHideSeconds))
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(config.panelAutoHideSeconds)) { [weak self] in
            guard let self, case .answering = self.machine.state else { return }
            self.apply(.autoHideElapsed)
        }
    }

    func render() {
        panel.model.state = machine.state
        // While guiding, the overlay is the interface; re-showing the panel would double up on it.
        guard machine.state != .idle, machine.state != .guiding else { return }
        panel.show()
    }
}
