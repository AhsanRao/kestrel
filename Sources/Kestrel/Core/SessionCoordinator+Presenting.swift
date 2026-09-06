import AppKit
import Foundation

/// How a spoken answer reaches the user: read out as it streams, marked on the screen where it
/// points at something, and taken away again. Drawn routes live in `SessionCoordinator+Guiding`.
extension SessionCoordinator {
    /// Clears the streamed-speech flag for a new turn. Call before the query goes out so the first
    /// sentence that streams back is recognised as the first.
    func resetStreaming() {
        streamedSpeech = false
    }

    /// Circles what the answer is pointing at, while it is being said.
    ///
    /// The marks are dismissed on the same clock as the panel, and by Esc, so nothing Kestrel drew
    /// is ever left on the screen after the user has stopped listening.
    func showAnnotations(_ pointed: AnnotationParser.Result, elements: [AXElementScanner.Element]) {
        guard config.answerAnnotations, !pointed.isEmpty else { return annotations.hide() }
        let marks = AnnotationParser.annotations(for: pointed, elements: elements)
        guard !marks.isEmpty else { return annotations.hide() }
        log.debug("annotating \(marks.count) control(s) alongside the answer")
        annotations.show(marks)
        // Esc takes the marks off, and the tap is torn down as soon as they are gone either way —
        // an event tap left running after the drawing has faded is a tap for no reason.
        annotations.onHide = { [weak self] in self?.escapeWatcher.stop() }
        escapeWatcher.onEscape = { [weak self] in self?.annotations.hide() }
        escapeWatcher.start()
    }

    /// One sentence of the answer, as it is written. Shows in the panel and is queued for speech,
    /// so the reply begins out loud while the rest is still arriving — the model's own first
    /// sentence is what the user hears first, not a filler line.
    func speakStreamed(_ sentence: String) {
        guard case .thinking = machine.state else { return }
        // The trailing marker line is an instruction to Kestrel, not part of the answer.
        guard !AnnotationParser.isMarker(sentence) else { return }
        panel.model.answer = panel.model.answer.isEmpty ? sentence : panel.model.answer + " " + sentence
        guard config.speakAnswers else { return }
        let isFirstSentence = !streamedSpeech
        let spoken = isFirstSentence ? speech.speak(sentence, config: config)
                                      : speech.enqueue(sentence, config: config)
        if spoken { streamedSpeech = true }
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
        // A mark outlives the panel a little: the user is usually still looking at the control.
        annotations.hide(after: TimeInterval(config.panelAutoHideSeconds) + 4)
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
