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

    func runAsk(_ text: String) {
        // "How do I …?" is a request to be shown, not told (spec §8.15).
        let wantsSteps = WalkthroughDetector.wantsWalkthrough(text, config: config)
        // Say something straight away. The model takes seconds; silence for those seconds is what
        // made Kestrel feel slow, more than the seconds themselves.
        DispatchQueue.main.async { self.acknowledge() }
        // Walkthroughs get a gridded copy of the screenshot: the model reads coordinates off the
        // printed lines instead of guessing them. The user's own view is never touched.
        // The Accessibility tree is the accurate way to point at a control; the gridded screenshot
        // is only the fallback for apps that expose nothing useful.
        var gridded: URL?
        if wantsSteps {
            let elements = AXElementScanner.scanFrontmostApp()
            DispatchQueue.main.sync { self.scannedElements = elements }
            if elements.isEmpty, let original = pendingCapture?.url {
                gridded = GridAnnotator.annotate(original)
            }
        }
        defer { if let gridded { try? FileManager.default.removeItem(at: gridded) } }

        let query = Query(text: text, screenshot: gridded ?? pendingCapture?.url,
                          focusCrop: pendingCrop,
                          mode: wantsSteps ? .walkthrough : .ask,
                          elements: wantsSteps ? scannedElements : [])
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
                    self.present(answer, alreadySpoken: self.streamedSpeech)
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
