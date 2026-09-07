import AppKit
import Foundation

/// How a spoken answer reaches the user: read out as it streams, marked on the screen where it
/// points at something, and taken away again. Drawn routes live in `SessionCoordinator+Guiding`.
extension SessionCoordinator {
    /// Clears the streamed-speech flag for a new turn. Call before the query goes out so the first
    /// sentence that streams back is recognised as the first.
    func resetStreaming() {
        streamedSpeech = false
        streamingDraft = false
        panel.model.draft = nil
    }

    /// Circles what the answer is pointing at, while it is being said.
    ///
    /// The marks are dismissed on the same clock as the panel, and by Esc, so nothing Kestrel drew
    /// is ever left on the screen after the user has stopped listening.
    func showAnnotations(_ pointed: AnnotationParser.Result, targets: [ScreenTarget],
                         readContent: Bool = true) {
        guard config.answerAnnotations else { return annotations.hide() }
        // An answer that named nothing still gets a mark if Kestrel can work out what it meant:
        // saying "tighten the card spacing" and highlighting nothing leaves the user hunting.
        var marks = AnnotationParser.annotations(for: pointed, targets: targets)
        // Unless there was no content to read. Chrome does not put the page in its Accessibility
        // tree — measured: 268 elements under the window, not one of them from the page — so on a
        // web page the whole list is the browser's own toolbar and tabs. Guessing among those is
        // how an answer about the page ends up marked on the bookmarks bar. Better to say it in
        // words than to point confidently at the wrong thing.
        if marks.isEmpty, !pointed.declaredNothing, readContent {
            marks = AnnotationParser.inferred(from: pointed.spoken, targets: targets)
        }
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
        // Everything from the DRAFT: line onward is the thing the user asked to be written, and
        // reading an email out loud is nobody's idea of help. The decision has to be made here,
        // sentence by sentence, because speech starts before the whole answer exists.
        if DraftParser.isDraftBoundary(sentence) { streamingDraft = true }
        guard !streamingDraft else { return }
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

    /// The one thing Kestrel still does to the Mac rather than describing.
    ///
    /// Deliberately not a plan and not a confirmation: opening an app is a single, obvious,
    /// harmless act, and asking permission for it would be theatre. Once it is open, the answer is
    /// spoken like any other — and the next question will be about the app that is now in front.
    func openApp(_ app: (bundleID: String, name: String), asked: String) {
        discardCapture()
        let opened = AppLauncher.launch(bundleID: app.bundleID)
        DispatchQueue.main.async {
            let line = opened ? "Opening \(app.name)." : "I couldn't open \(app.name)."
            self.conversation.record(question: asked, answer: line, at: Date(),
                                     appBundleID: app.bundleID)
            self.present(Answer(text: line, raw: line, durationMs: 0))
        }
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
        dismiss(after: 8)
    }

    /// Takes a line down again once it has been read, and puts the session back to idle with it.
    ///
    /// Hiding the window is not enough on its own. The machine stays in `.error` with the failed
    /// message in it, so the next press starts out of an error state carrying a stale transcript;
    /// worse, an error that arrives on a path which never calls this at all — an empty transcript
    /// used to be one — leaves the island open on screen with nothing to dismiss it.
    func dismiss(after seconds: TimeInterval) {
        panel.hide(after: seconds)
        // A beat behind the window, which fades over 0.2s: clearing the text on the same tick
        // empties the island while the user can still see it.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.3) { [weak self] in
            // Only if nothing has happened since: a question asked inside the window is now the
            // live session, and clearing it would take the user's own answer off the screen.
            guard let self, case .error = self.machine.state else { return }
            // Hovering means it is being read, and the panel pauses its own timer for exactly
            // that. The state has to wait with it, or the message goes blank under the pointer.
            guard !self.panel.model.isHovering else { return self.dismiss(after: 3) }
            self.apply(.autoHideElapsed)
        }
    }

    func reset() {
        panel.model.transcript = ""
        panel.model.answer = ""
        panel.model.draft = nil
        panel.model.permissionURL = nil
        discardCapture()
    }

    func scheduleAutoHide() {
        guard case .answering = machine.state else { return }
        panel.hide(after: TimeInterval(config.panelAutoHideSeconds))
        // A mark outlives the panel a little: the user is usually still looking at the control.
        // How much longer depends on how many marks there are, because they are drawn one after
        // another — see `AnnotationOverlay.lifetime`.
        annotations.hide(after: AnnotationOverlay.lifetime(
            forMarks: annotations.markCount,
            atLeast: TimeInterval(config.panelAutoHideSeconds) + 4))
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(config.panelAutoHideSeconds)) { [weak self] in
            guard let self, case .answering = self.machine.state else { return }
            self.apply(.autoHideElapsed)
        }
    }

    func render() {
        panel.model.state = machine.state
        guard machine.state != .idle else { return }
        panel.show()
    }
}
