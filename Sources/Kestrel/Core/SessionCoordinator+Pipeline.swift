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
                }
                return
            }
            DispatchQueue.main.async {
                self.panel.model.transcript = text
                self.apply(.transcribed(intent))
                self.render()
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

    /// - Parameter asWalkthrough: forces the drawn branch, for a route being continued onto a new
    ///   screen where the phrasing of the follow-up question is Kestrel's own, not the user's.
    func runAsk(_ text: String, forceAnswer: Bool = false, asWalkthrough: Bool = false) {
        // A question asked soon after the last one, in the same app, continues it.
        let bundleID = TextInjector.frontmostBundleID()
        let history = conversation.context(now: Date(),
                                           window: TimeInterval(config.followUpSeconds),
                                           frontmostBundleID: bundleID)
        DispatchQueue.main.async { self.panel.model.isFollowUp = !history.isEmpty }
        // "Open Spotify" is the one thing Kestrel still does rather than describes.
        if !forceAnswer, let app = AppLauncher.requestedApp(in: text) {
            return openApp(app, asked: text)
        }
        let wantsSteps = asWalkthrough
            || (!forceAnswer && WalkthroughDetector.wantsWalkthrough(text, config: config))
        DispatchQueue.main.async { self.resetStreaming() }
        // The screen is read for a plain answer too, not only for a walkthrough: it is what lets
        // the answer point at something. "Click Share in the toolbar" spoken while the Share button
        // is circled is an assistant; the same sentence alone is a chatbot describing a photograph.
        // Controls *and* content, because half of what anyone asks about is not clickable.
        let elements = AXElementScanner.scanFrontmostApp()
        DispatchQueue.main.sync { self.scannedElements = elements }
        var targets = Array(elements.prefix(SessionCoordinator.maximumPointableControls))
            .map(\.asTarget)
        let screen = wantsSteps ? nil : AXContentReader.read(startingAt: targets.count + 1)
        targets += screen?.regions ?? []
        // Walkthroughs get a gridded copy of the screenshot: the model reads coordinates off the
        // printed lines instead of guessing them. The user's own view is never touched.
        // The Accessibility tree is the accurate way to point at a control; the gridded screenshot
        // is only the fallback for apps that expose nothing useful.
        var gridded: URL?
        if wantsSteps, elements.isEmpty {
            // No Accessibility tree to point with, so the model has to read positions off the grid
            // — and the grid can only be trusted if it covers everything a step might point at.
            // The default screenshot is the front window alone, which does not include the menu
            // bar; a step aiming at File then got coordinates mapped inside the window, and the
            // mark landed in the middle of the document. The whole display is captured instead.
            if config.captureMode == .window,
               let display = try? ScreenGrabber.capture(maxEdge: config.screenshotMaxEdge,
                                                        mode: .display) {
                let previous = pendingCapture
                DispatchQueue.main.sync { self.pendingCapture = display }
                if let previous { try? FileManager.default.removeItem(at: previous.url) }
            }
            if let original = pendingCapture?.url { gridded = GridAnnotator.annotate(original) }
        }
        defer { if let gridded { try? FileManager.default.removeItem(at: gridded) } }

        let query = Query(text: text, screenshot: gridded ?? pendingCapture?.url,
                          focusCrop: pendingCrop,
                          mode: wantsSteps ? .walkthrough : .ask,
                          elements: wantsSteps ? elements : [],
                          targets: wantsSteps ? [] : targets,
                          screenText: screen?.text, pageURL: screen?.url,
                          document: screen?.document,
                          history: history,
                          skills: SkillLibrary.notes(forBundleID: bundleID),
                          desktop: DesktopContextDetector.needsDesktopContext(text)
                              ? DesktopSurvey.summary() : nil)
        do {
            // A walkthrough answer is JSON, which must never be read out; a spoken answer streams.
            let onDelta: ((String) -> Void)? = wantsSteps ? nil : { [weak self] sentence in
                DispatchQueue.main.async { self?.speakStreamed(sentence) }
            }
            let answer = try router.ask(query, config: config, onDelta: onDelta)
            DispatchQueue.main.async {
                if wantsSteps, let walkthrough = WalkthroughParser.parse(answer.text) {
                    self.present(walkthrough)
                } else {
                    self.discardCapture()
                    // The marker line is machine-readable and belongs on the screen, not in the
                    // sentence: it is stripped before the answer is recorded, shown or spoken.
                    let pointed = AnnotationParser.parse(answer.text)
                    var spoken = answer
                    spoken.text = pointed.spoken
                    self.conversation.record(question: text, answer: pointed.spoken,
                                             at: Date(), appBundleID: bundleID)
                    // "I'm working on the billing rewrite" is worth keeping; the rest of what was
                    // on screen is not. Written off the main thread — it touches disk.
                    self.work.async { MemoryWriter.note(question: text) }
                    self.showAnnotations(pointed, targets: targets,
                                         readContent: !(screen?.text.isEmpty ?? true))
                    self.present(spoken, alreadySpoken: self.streamedSpeech)
                }
            }
        } catch is CancellationError {
            discardCapture()
        } catch {
            discardCapture()
            finish(with: error)
        }
    }
}
