import AppKit
import Foundation

/// How an answer reaches the user: spoken as it streams, drawn as a walkthrough, or read out when
/// the drawing cannot be trusted. Split from the pipeline only to keep both files readable.
extension SessionCoordinator {
    /// A short "let me look" while the model is still reading the screen.
    func acknowledge() {
        streamedSpeech = false
        guard config.speakAnswers, config.acknowledgeWhileThinking else { return }
        speech.speak(BundleResources.randomAcknowledgement(), config: config)
    }

    /// One sentence of the answer, as it is written. Shows in the panel and is queued for speech,
    /// so the reply begins out loud while the rest is still arriving.
    func speakStreamed(_ sentence: String) {
        guard case .thinking = machine.state else { return }
        panel.model.answer = panel.model.answer.isEmpty ? sentence : panel.model.answer + " " + sentence
        guard config.speakAnswers else { return }
        if speech.enqueue(sentence, config: config) { streamedSpeech = true }
    }

    /// Plain spoken answer.
    func present(_ answer: Answer, alreadySpoken: Bool = false) {
        sounds.play(.answered, config: config)
        panel.model.answer = answer.text
        apply(.answered)
        render()
        // Streaming already read it out; saying it again would double up.
        if !alreadySpoken, config.speakAnswers, speech.speak(answer.text, config: config) { return }
        if alreadySpoken, speech.isSpeaking { return }
        scheduleAutoHide()
    }

    /// Drawn walkthrough, with a spoken fallback whenever the drawing cannot be trusted.
    func present(_ walkthrough: Walkthrough) {
        guard let capture = pendingCapture else { return spokenFallback(walkthrough) }

        let resolved = WalkthroughResolver.resolve(walkthrough, elements: scannedElements, capture: capture)
        guard !resolved.isEmpty else { return spokenFallback(walkthrough) }
        var usable = walkthrough
        usable.steps = WalkthroughParser.sanitize(resolved.map(\.step))
        let frames = resolved.map(\.frame)
        log.debug("walkthrough: \(resolved.filter(\.isExact).count)/\(resolved.count) steps from accessibility")

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
        if let crop = pendingCrop { try? FileManager.default.removeItem(at: crop) }
        pendingCapture = nil
        pendingCrop = nil
        focusRegion = nil
    }

    func finish(with error: Error) {
        DispatchQueue.main.async { self.fail(error) }
    }

    func fail(_ error: Error) {
        sounds.play(.failed, config: config)
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
