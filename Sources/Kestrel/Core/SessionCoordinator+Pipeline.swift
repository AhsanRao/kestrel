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
                    self.discardScreenshot()
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
        let query = Query(text: text, screenshot: pendingScreenshot, mode: .ask)
        do {
            let answer = try router.ask(query, config: config)
            discardScreenshot()
            DispatchQueue.main.async {
                self.panel.model.answer = answer.text
                self.apply(.answered)
                self.render()
                if self.config.speakAnswers, self.speech.speak(answer.text, config: self.config) { return }
                self.scheduleAutoHide()
            }
        } catch is CancellationError {
            discardScreenshot()
        } catch {
            discardScreenshot()
            finish(with: error)
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

    func discardScreenshot() {
        if let url = pendingScreenshot { try? FileManager.default.removeItem(at: url) }
        pendingScreenshot = nil
    }

    func finish(with error: Error) {
        DispatchQueue.main.async { self.fail(error) }
    }

    func fail(_ error: Error) {
        discardScreenshot()
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
        discardScreenshot()
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
        if machine.state != .idle { panel.show() }
    }
}
