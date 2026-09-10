import AppKit
import Foundation

/// Dictation as it is spoken. Each stretch of speech the engine settles on is typed straight into
/// the app, the words still in the air are shown on the panel, and a long enough pause ends the
/// take without a second keypress.
///
/// The recorded-take path is still what runs under whisper, and is still what ends a live take:
/// the hotkey means the same thing either way.
extension SessionCoordinator {
    /// Starts a live take. False when this Mac cannot stream — the caller then records a WAV.
    func beginLiveDictation() -> Bool {
        guard let engine = LiveDictation.make(for: config) else { return false }
        live = engine
        liveText = ""
        engine.onVolatile = { [weak self] text in self?.showLive(guess: text) }
        engine.onFinal = { [weak self] text in self?.typeLive(text) }
        engine.onLevel = { [weak self] level in self?.panel.model.level = Double(level) }
        engine.onSilence = { [weak self] in self?.liveFellSilent() }
        engine.onFailure = { [weak self] error in self?.fail(error) }
        engine.start(config: config)
        return true
    }

    /// Ends one. False when the take was not live, so the caller finishes it the recorded way.
    func finishLiveDictation() -> Bool {
        guard let engine = live, engine.isRunning else { return false }
        sounds.play(.heard, config: config)
        engine.stop { [weak self] in
            guard let self else { return }
            self.live = nil
            let typed = self.liveText
            // Nothing above the noise floor, or nothing the engine could make out.
            guard !typed.isEmpty else {
                self.apply(.transcriptionEmpty)
                self.dismiss(after: 3)
                return
            }
            self.panel.model.transcript = typed
            self.apply(.transcribed(.dictation))
            self.apply(.injected)
        }
        return true
    }

    /// Esc, or a rebind mid-take. Whatever has already been typed stays typed — it is in the user's
    /// document now, and taking it back out is not Kestrel's to do.
    func cancelLiveDictation() {
        guard let engine = live else { return }
        live = nil
        engine.stop {}
    }

    // MARK: - Private

    private func typeLive(_ chunk: String) {
        let text = config.cleanupDictation ? DictationTidy.cleanFragment(chunk)
                                           : chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try TextInjector.inject(text, mode: config.injectMode, spaced: !liveText.isEmpty)
        } catch {
            cancelLiveDictation()
            return fail(error)
        }
        liveText += liveText.isEmpty ? text : " " + text
        panel.model.transcript = liveText
    }

    /// The engine's running guess, shown but never typed: it is rewritten with every syllable, and
    /// nothing that changes belongs in the user's document.
    private func showLive(guess: String) {
        let guessed = guess.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !guessed.isEmpty else { return }
        panel.model.transcript = liveText.isEmpty ? guessed : liveText + " " + guessed
    }

    private func liveFellSilent() {
        guard machine.state == .dictating else { return }
        apply(.dictateToggled)
    }
}
