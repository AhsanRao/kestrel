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
        panel.model.aside = nil
        cancelAcknowledgement()
        spokeAcknowledgement = false
    }

    /// Says "let me have a look", but only if the answer has not already started.
    ///
    /// Scheduled rather than said straight away: a question the model answers in a third of a
    /// second needs no filler, and stacking one in front of the answer would make the fast case
    /// slower for no gain. When the model does take a moment, this is what fills it.
    func acknowledge(_ question: String) {
        let line = Acknowledgement.line(for: question)
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .thinking = self.machine.state, !self.streamedSpeech else { return }
            self.panel.model.aside = line
            self.render()
            guard self.config.speakAnswers else { return }
            if self.speech.speak(line, config: self.config) { self.spokeAcknowledgement = true }
        }
        pendingAcknowledgement = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Acknowledgement.delay, execute: work)
    }

    func cancelAcknowledgement() {
        pendingAcknowledgement?.cancel()
        pendingAcknowledgement = nil
    }

    /// Circles what the answer is pointing at, while it is being said.
    ///
    /// The marks are dismissed on the same clock as the panel, and by Esc, so nothing Kestrel drew
    /// is ever left on the screen after the user has stopped listening.
    /// - Returns: the captions actually drawn, so the next question knows what "that one" meant.
    @discardableResult
    func showAnnotations(_ pointed: AnnotationParser.Result, targets: [ScreenTarget],
                         readContent: Bool = true) -> [String] {
        guard config.answerAnnotations else { annotations.hide(); return [] }
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
        guard !marks.isEmpty else { annotations.hide(); return [] }
        log.debug("annotating \(marks.count) control(s) alongside the answer")
        annotations.show(marks)
        // The marks can outlive the panel, so Esc has to keep reaching them after it has gone.
        updateEscapeWatch()
        return marks.map(\.caption)
    }

    /// One sentence of the answer, as it is written. Shows in the panel and is queued for speech,
    /// so the reply begins out loud while the rest is still arriving — the model's own first
    /// sentence is what the user hears first, not a filler line.
    func speakStreamed(_ sentence: String) {
        guard case .thinking = machine.state else { return }
        // The answer got here first, so the filler is not needed.
        cancelAcknowledgement()
        // The trailing marker line is an instruction to Kestrel, not part of the answer.
        guard !AnnotationParser.isMarker(sentence) else { return }
        // Everything from the DRAFT: line onward is the thing the user asked to be written, and
        // reading an email out loud is nobody's idea of help. The decision has to be made here,
        // sentence by sentence, because speech starts before the whole answer exists.
        if DraftParser.isDraftBoundary(sentence) { streamingDraft = true }
        guard !streamingDraft else { return }
        panel.model.answer = panel.model.answer.isEmpty ? sentence : panel.model.answer + " " + sentence
        panel.model.aside = nil
        guard config.speakAnswers else { return }
        // Only a first sentence with nothing in front of it may cut the queue. If the "let me look"
        // line is still being said, this goes behind it — interrupting it mid-word is worse than
        // the half-second it costs.
        let interrupts = !streamedSpeech && !spokeAcknowledgement
        let spoken = interrupts ? speech.speak(sentence, config: config)
                                : speech.enqueue(sentence, config: config)
        if spoken { streamedSpeech = true }
    }

    /// Plain spoken answer.
    func present(_ answer: Answer, alreadySpoken: Bool = false) {
        cancelAcknowledgement()
        sounds.play(.answered, config: config)
        panel.model.aside = nil
        panel.model.answer = answer.text
        apply(.answered)
        render()
        // Only when Kestrel is not about to read it out: two voices saying the same sentence is
        // worse than one.
        if !config.speakAnswers { panel.announce(answer.text) }
        // Streaming already read it out; saying it again would double up.
        // Behind the "let me look" line if that is still going, in front of nothing otherwise.
        if !alreadySpoken, config.speakAnswers {
            let started = spokeAcknowledgement ? speech.enqueue(answer.text, config: config)
                                               : speech.speak(answer.text, config: config)
            if started { return }
        }
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
            let line = opened ? "Opening \(app.name)." : "\(app.name) won't open — is it installed?"
            self.conversation.record(question: asked, answer: line, at: Date(),
                                     appBundleID: app.bundleID)
            self.present(Answer(text: line, raw: line, durationMs: 0))
        }
    }

    func runDictation(_ text: String) {
        var output = text
        if config.cleanupDictation {
            // Local rules first: punctuation, capitals and spoken commands do not need a model, and
            // a short line is finished by the time a process would have launched.
            output = DictationTidy.clean(text)
            if DictationTidy.needsModel(output) {
                // A cleanup failure must never cost the user their words: keep the tidied version.
                if let cleaned = try? router.ask(Query(text: output, mode: .dictationCleanup),
                                                 config: config),
                   !cleaned.text.isEmpty {
                    output = cleaned.text
                } else {
                    log.info("cleanup failed, injecting the locally tidied transcript")
                }
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
}
