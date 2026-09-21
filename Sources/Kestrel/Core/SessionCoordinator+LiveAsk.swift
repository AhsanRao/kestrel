import AppKit
import Foundation

/// A question heard as it is said (spec §5.2).
///
/// The chord used to be a shutter: hold, speak, release, and only then did the words go anywhere.
/// Now the same streaming engine that types dictation listens while the chord is held, and the
/// first pause sends the phrase so far — "open Spotify" is on its way while the user is drawing
/// breath for "and play something". The microphone stays open; whatever is said next is the next
/// question, queued behind the one in flight and asked in turn. A phrase said while Kestrel is
/// asking whether to go ahead is the answer to that.
extension SessionCoordinator {
    /// Starts hearing a question live. False when the engine cannot stream, or the user has
    /// turned it off — the caller then records a WAV and transcribes it on release, as before.
    func beginLiveAsk() -> Bool {
        guard config.liveAsk, let engine = makeLiveEngine(config) else { return false }
        live = engine
        liveText = ""
        liveGuess = ""
        phrases = []
        engine.onVolatile = { [weak self] text in self?.heardGuess(text) }
        engine.onFinal = { [weak self] text in self?.heardSettled(text) }
        engine.onLevel = { [weak self] level in self?.panel.model.level = Double(level) }
        engine.onSilence = { [weak self] in self?.phraseEnded() }
        engine.onFailure = { [weak self] error in self?.fail(error) }
        // The dictation engine reads its pause from the dictation setting; a question's is shorter.
        var tuned = config
        tuned.dictationSilenceSeconds = config.askSilenceSeconds
        engine.start(config: tuned)
        return true
    }

    /// The chord came up. False when the take was not live, so the caller finishes it the
    /// recorded way. Whatever was said since the last pause goes off now.
    func finishLiveAsk() -> Bool {
        guard let engine = live, engine.isRunning else { return false }
        // The circle gesture ends with the chord, whatever the phrase did.
        if dragTracker.isTracking {
            focusRegion = dragTracker.end()
            selection.settle(focusRegion)
        }
        engine.stop { [weak self] in
            guard let self else { return }
            self.live = nil
            let tail = self.currentPhrase()
            if !tail.isEmpty {
                self.sounds.play(.heard, config: self.config)
                self.heard(tail)
            } else if case .transcribing = self.machine.state {
                // The release moved the machine on before this ran, and there was nothing said
                // since the last phrase — or nothing at all. Not a question.
                self.apply(.cancelled)
                self.panel.hideImmediately()
            }
        }
        return true
    }

    /// The last question is done with; the next one the user said, if any, goes now — once the
    /// answer has finished being read out, since the user asked it expecting to hear it.
    func askNextPhrase() {
        guard !phrases.isEmpty else { return }
        guard !speech.isSpeaking else {
            return DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.askNextPhrase() }
        }
        heard(phrases.removeFirst())
    }

    // MARK: - Private

    private func heardGuess(_ text: String) {
        liveGuess = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = [liveText, liveGuess].filter { !$0.isEmpty }.joined(separator: " ")
        if !shown.isEmpty { panel.model.transcript = shown }
    }

    private func heardSettled(_ text: String) {
        let settled = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !settled.isEmpty else { return }
        liveText += liveText.isEmpty ? settled : " " + settled
        liveGuess = ""
        panel.model.transcript = liveText
    }

    /// What has been said since the last phrase went off, taking the engine's running guess when
    /// its settled result has not caught up.
    private func currentPhrase() -> String {
        let phrase = liveText.isEmpty ? liveGuess : liveText
        liveText = ""
        liveGuess = ""
        return phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The room went quiet: the phrase so far is a question. The microphone stays open for the next.
    private func phraseEnded() {
        let phrase = currentPhrase()
        live?.listenAgain()
        guard !phrase.isEmpty else { return }
        sounds.play(.heard, config: config)
        heard(phrase)
    }

    /// Routes a phrase by what Kestrel is doing: a question now, an answer to a confirmation, or
    /// the next question in the queue.
    func heard(_ phrase: String) {
        switch machine.state {
        // `.transcribing` here is the release having moved the machine on ahead of the engine
        // stopping: the phrase is still the first one, and goes now.
        case .listening, .transcribing, .answering, .error, .idle:
            startAsk(phrase)
        case .confirming(let what):
            let text = phrase
            work.async { [weak self] in
                guard let self else { return }
                let yes = ActionJudge.isYes(text, to: what, config: self.config) ?? Confirmation.isYes(text)
                DispatchQueue.main.async { self.decide(yes) }
            }
        default:
            phrases.append(phrase)
        }
    }

    /// A phrase becomes a question: the screen is read now, since it is what the phrase is about.
    private func startAsk(_ text: String) {
        if dragTracker.isTracking {
            focusRegion = dragTracker.end()
            selection.settle(focusRegion)
        }
        panel.show()
        let stamp = beginGeneration()
        apply(.phraseHeard)
        panel.model.transcript = text
        apply(.transcribed(.ask))
        render()
        acknowledge(text)
        let awaitScreen = gatherScreen(stamp: stamp)
        work.async { [weak self] in
            guard let self else { return }
            do {
                try awaitScreen()
                self.runAsk(text, stamp: stamp)
            } catch {
                self.finish(with: error, stamp: stamp)
            }
        }
    }
}
