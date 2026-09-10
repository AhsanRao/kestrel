import AppKit
import Foundation

/// The transcribe → think → answer / clean → paste half of the session loop.
/// Split from `SessionCoordinator` only to keep both files readable.
extension SessionCoordinator {
    // MARK: - Pipeline

    /// - Parameter awaitCapture: blocks until the screenshot taken in parallel has landed, and
    ///   rethrows whatever went wrong with it.
    func transcribe(_ wav: URL, intent: SessionIntent, awaitCapture: (() throws -> Void)? = nil) {
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
                    // Nothing was heard, so there is nothing to read: the line is a nudge to say it
                    // again, not a message to study. Three seconds, the same as a finished
                    // dictation — an error worth reading gets the longer eight.
                    self.dismiss(after: 3)
                }
                return
            }
            DispatchQueue.main.async {
                self.panel.model.transcript = text
                self.apply(.transcribed(intent))
                self.render()
                // Everything from here is the model's clock. Whatever it costs, the user hears
                // something first.
                if intent == .ask { self.acknowledge(text) }
            }
            switch intent {
            case .ask:
                try awaitCapture?()
                runAsk(text)
            case .dictation:
                runDictation(text)
            }
        } catch {
            finish(with: error)
        }
    }

    /// Every question takes the same path now.
    ///
    /// "How do I…" used to open a *route*: a numbered plan drawn one step at a time, which waited
    /// for the user to click the current target, then photographed the screen again and asked for
    /// the next stretch. It was the wrong shape for the thing. Kestrel is not driving — the user
    /// is — and taking the drawing away the moment they clicked, to think about a screen they had
    /// already moved past, meant the answer vanished exactly when they went to act on it. Now the
    /// answer says what to do in a sentence, marks the one or two things it names, and stops. The
    /// user acts, and asks again if they want the next part; that question gets a fresh screen.
    func runAsk(_ text: String, forceAnswer: Bool = false) {
        // Read while the transcript was still being made, so none of it is on the clock. Only the
        // re-ask path arrives with nothing, and pays for its own scan.
        let screen = pendingScreen ?? ScreenSnapshot.read(bundleID: TextInjector.frontmostBundleID())
        pendingScreen = nil
        let bundleID = screen.bundleID
        // A question asked soon after the last one, in the same app, continues it.
        let history = conversation.context(now: Date(),
                                           window: TimeInterval(config.followUpSeconds),
                                           frontmostBundleID: bundleID)
        DispatchQueue.main.async { self.panel.model.isFollowUp = !history.isEmpty }
        // "Open Spotify" is the one thing Kestrel still does rather than describes.
        if !forceAnswer, let app = AppLauncher.requestedApp(in: text) {
            return openApp(app, asked: text)
        }
        let elements = screen.elements
        let targets = screen.targets
        DispatchQueue.main.async {
            self.resetStreaming()
            self.scannedElements = elements
        }
        let query = Query(text: text, screenshot: pendingCapture?.url,
                          focusCrop: pendingCrop,
                          mode: .ask,
                          targets: targets,
                          screenText: screen.text, pageURL: screen.url,
                          document: screen.document,
                          history: history,
                          skills: SkillLibrary.notes(forBundleID: bundleID),
                          desktop: DesktopContextDetector.needsDesktopContext(text)
                              ? DesktopSurvey.summary() : nil)
        do {
            let onDelta: ((String) -> Void)? = { [weak self] sentence in
                DispatchQueue.main.async { self?.speakStreamed(sentence) }
            }
            let answer = try router.ask(query, config: config, onDelta: onDelta)
            DispatchQueue.main.async {
                self.discardCapture()
                // The marker line is machine-readable and belongs on the screen, not in the
                // sentence: it is stripped before the answer is recorded, shown or spoken.
                let pointed = AnnotationParser.parse(answer.text)
                // A draft is shown, not said. Splitting it out here keeps the email out of the
                // spoken answer, out of the conversation history, and out of the panel's own
                // prose — it belongs on its own surface with a button that copies it.
                let written = DraftParser.parse(pointed.spoken)
                // …or a reply the model left in quotes inside its own sentence, which is the same
                // thing to the user and needs the same button.
                self.panel.model.draft = written.draft
                    ?? DraftParser.suggestion(forQuestion: text, in: written.spoken)
                var spoken = answer
                spoken.text = written.spoken
                let marked = self.showAnnotations(pointed, targets: targets,
                                                  readContent: screen.readContent)
                self.conversation.record(question: text, answer: written.spoken,
                                         at: Date(), appBundleID: bundleID, marked: marked)
                // "I'm working on the billing rewrite" is worth keeping; the rest of what was on
                // screen is not. Written off the main thread — it touches disk.
                self.work.async { MemoryWriter.note(question: text) }
                self.present(spoken, alreadySpoken: self.streamedSpeech)
            }
        } catch is CancellationError {
            discardCapture()
        } catch {
            discardCapture()
            finish(with: error)
        }
    }
}
