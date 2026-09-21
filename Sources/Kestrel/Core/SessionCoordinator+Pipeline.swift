import AppKit
import Foundation

/// The transcribe → think → answer / clean → paste half of the session loop.
/// Split from `SessionCoordinator` only to keep both files readable.
extension SessionCoordinator {
    // MARK: - Pipeline

    /// - Parameter awaitCapture: blocks until the screenshot taken in parallel has landed, and
    ///   rethrows whatever went wrong with it.
    /// - Parameter stamp: the take this is (`generation`); nothing here outlives an Esc.
    func transcribe(_ wav: URL, intent: SessionIntent, stamp: Int, awaitCapture: (() throws -> Void)? = nil) {
        defer { try? FileManager.default.removeItem(at: wav) }
        let started = Date()
        do {
            let text = try transcriber.transcribe(wav, config: config)
            log.debug("transcript in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            guard stillCurrent(stamp) else { return }
            guard !text.isEmpty else {
                DispatchQueue.main.async {
                    guard self.isCurrent(stamp) else { return }
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
                guard self.isCurrent(stamp) else { return }
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
                runAsk(text, stamp: stamp)
            case .dictation:
                runDictation(text, stamp: stamp)
            }
        } catch {
            finish(with: error, stamp: stamp)
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
    func runAsk(_ text: String, stamp: Int, forceAnswer: Bool = false) {
        guard stillCurrent(stamp) else { return }
        // Read while the transcript was still being made, so none of it is on the clock. Only the
        // re-ask path arrives with nothing, and pays for its own scan.
        var screen = pendingScreen ?? ScreenSnapshot.read(bundleID: TextInjector.frontmostBundleID())
        pendingScreen = nil
        let bundleID = screen.bundleID
        // A question asked soon after the last one, in the same app, continues it.
        var history = conversation.context(now: Date(),
                                           window: TimeInterval(config.followUpSeconds),
                                           frontmostBundleID: bundleID)
        // What kind of request this is — a launch, a job for the hands, or a question for the
        // eyes — decided from the sentence before a model is spawned (spec §8.19).
        let triage = QuestionTriage.decide(text, frontmostApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                                           previous: history.last, controls: screen.targets, config: config)
        log.info("triage: \(triage.kind.rawValue, privacy: .public) via \(triage.source, privacy: .public)")
        if !triage.isFollowUp { history = [] }
        DispatchQueue.main.async { self.panel.model.isFollowUp = !history.isEmpty }
        // "Open Spotify" needs no model at all. "Open Spotify and play something" does, when the
        // model has hands; without them the app is opened and the rest is left, as before.
        guard stillCurrent(stamp) else { return }
        if !forceAnswer, triage.kind == .openApp, let app = triage.app {
            return openApp(app, asked: text, stamp: stamp)
        }

        // "Open Chrome and search for…": the opening is one verb and needs no model. Done here,
        // then the screen is read again — it is a different screen now — and the model gets the
        // request with the app already in front.
        var alreadyDone: String?
        if !forceAnswer, triage.kind == .act, triage.opensFirst, let app = triage.app {
            DispatchQueue.main.async { self.panel.model.aside = "Opening \(app.name)" }
            if AppLauncher.launch(bundleID: app.bundleID) {
                discardCapture()
                let gathered = DispatchQueue.main.sync { gatherScreen(stamp: stamp) }
                try? gathered()
                screen = pendingScreen ?? screen
                pendingScreen = nil
                alreadyDone = "\(app.name) is open and in front."
                log.info("opened \(app.name, privacy: .public) ahead of the model")
            }
            DispatchQueue.main.async { self.panel.model.aside = nil }
        }
        DispatchQueue.main.async { self.resetStreaming() }
        // Hands are offered only to a request that needs them: a plain question skips the tool
        // prompt and the MCP handshake, and cannot act by mistake.
        let acting = config.agentTools && triage.kind == .act
            ? beginActing(with: pendingCapture, request: text, elements: screen.elements) : nil
        // "Search for owls": a step or two Jev is sure of, run without a model. If a step fails,
        // the model picks up from there with the session's steps already on its count.
        if !forceAnswer, let macro = triage.macro, let acting {
            guard let trouble = run(macro, in: acting) else {
                let line = SessionCoordinator.describe(macro, in: bundleID)
                DispatchQueue.main.async {
                    self.endActing(acting)
                    guard self.isCurrent(stamp) else { return }
                    self.discardCapture()
                    self.conversation.record(question: text, answer: line, at: Date(), appBundleID: bundleID)
                    self.present(Answer(text: line, raw: line, durationMs: 0))
                }
                return
            }
            log.info("macro fell through: \(trouble, privacy: .public)")
            alreadyDone = (alreadyDone.map { $0 + " " } ?? "") + "Kestrel tried: \(SessionCoordinator.describe(macro, in: bundleID)) It stopped at: \(trouble)"
            discardCapture()
            let gathered = DispatchQueue.main.sync { gatherScreen(stamp: stamp) }
            try? gathered()
            screen = pendingScreen ?? screen
            pendingScreen = nil
            acting.refresh(capture: pendingCapture, elements: screen.elements)
        }
        let elements = screen.elements
        let targets = screen.targets
        DispatchQueue.main.async { self.scannedElements = elements }
        let query = Query(text: text, screenshot: pendingCapture?.url,
                          focusCrop: pendingCrop,
                          mode: .ask,
                          targets: targets,
                          screenText: screen.text, pageURL: screen.url,
                          document: screen.document,
                          history: history,
                          skills: SkillLibrary.notes(forBundleID: bundleID),
                          desktop: triage.needsDesktop ? DesktopSurvey.summary() : nil,
                          tools: acting != nil, maximumSteps: config.maxAgentSteps,
                          wantsDraft: triage.wantsDraft, alreadyDone: alreadyDone)
        do {
            let onDelta: ((String) -> Void)? = { [weak self] sentence in
                DispatchQueue.main.async { self?.speakStreamed(sentence) }
            }
            let answer = try router.ask(query, config: config, onDelta: onDelta)
            DispatchQueue.main.async {
                // Marks are numbered off the screen the question was asked about. Once something
                // has been done to it, that list describes a screen that is gone.
                let acted = (acting?.steps ?? 0) > 0 || alreadyDone != nil
                // A job the model had to work out is worth writing down for the app it was in.
                if let acting, !acting.hitCap, acting.recipe.count >= 2 {
                    let steps = acting.recipe
                    let app = TextInjector.frontmostBundleID()
                    self.work.async { SkillLibrary.remember(request: text, steps: steps, bundleID: app) }
                }
                self.endActing(acting)
                guard self.isCurrent(stamp) else { return }
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
                let marked = acted ? [] : self.showAnnotations(pointed, targets: targets,
                                                               readContent: screen.readContent)
                self.conversation.record(question: text, answer: written.spoken,
                                         at: Date(), appBundleID: bundleID, marked: marked)
                // "I'm working on the billing rewrite" is worth keeping; the rest of what was on
                // screen is not. Written off the main thread — it touches disk.
                self.work.async { MemoryWriter.note(question: text) }
                self.present(spoken, alreadySpoken: self.streamedSpeech)
            }
        } catch is CancellationError {
            DispatchQueue.main.async { self.endActing(acting) }
        } catch {
            DispatchQueue.main.async { self.endActing(acting) }
            finish(with: error, stamp: stamp)
        }
    }
}
