import Foundation
import os

/// Ends a live dictation once the speaker has stopped, so a take does not have to be closed by
/// hand every time.
///
/// Two clocks, because neither is enough alone. The microphone level falls the moment someone
/// stops talking but says nothing about what is still being recognised; recognised words are
/// unambiguous but arrive up to two seconds late, and a take ended on those alone would cut the
/// start of the next sentence off — measured here, doing exactly that. So the take ends when the
/// room has been quiet for the configured pause *and* nothing has come back from the transcriber
/// for a moment either.
final class SilenceWatch {
    /// Below this the meter is reading a quiet room rather than a quiet voice. Measured on a
    /// built-in mic: room tone sits at 0.000–0.003, ordinary speech peaks above 0.15.
    static let quietBelow: Float = 0.03
    /// How long after the last recognised word the transcriber is assumed to have caught up.
    static let recognitionGrace: TimeInterval = 0.8

    /// How long the quiet has to last. 0 turns the whole thing off.
    private(set) var seconds: TimeInterval = 0
    var onSilence: (() -> Void)?

    private let lock = NSLock()
    /// Distant future until the first sound: a dictation that has heard nothing yet is waiting for
    /// the user to begin, not sitting in a silence worth ending.
    private var lastSound = Date.distantFuture
    private var lastWords = Date.distantFuture
    private var timer: Timer?
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "silence")

    /// The pure decision, so the timing can be tested without waiting for real time to pass.
    ///
    /// Ordinarily the room going quiet ends the take, once the transcriber has had a moment to
    /// catch up. A room that never goes quiet — a fan, a café, a machine with its own noise — would
    /// hold a take open forever on that rule alone, so a long enough spell with nothing recognised
    /// ends it regardless: if no words have come back in twice the pause, nobody is talking.
    static func isQuiet(sound lastSound: Date, words lastWords: Date,
                        now: Date, seconds: TimeInterval) -> Bool {
        guard seconds > 0 else { return false }
        let quietRoom = now.timeIntervalSince(lastSound) > seconds
        let quietTranscriber = now.timeIntervalSince(lastWords) > SilenceWatch.recognitionGrace
        if quietRoom && quietTranscriber { return true }
        return now.timeIntervalSince(lastWords) > seconds * 2
    }

    /// The microphone is hearing something. Callable from the audio thread.
    func heardSound() {
        lock.lock(); lastSound = Date(); lock.unlock()
    }

    /// The transcriber has produced something. Callable from the analysis thread.
    func heardWords() {
        lock.lock(); lastWords = Date(); lock.unlock()
    }

    /// Main thread. Does nothing when the pause is configured off.
    func start(seconds: TimeInterval) {
        stop()
        self.seconds = seconds
        lock.lock(); lastSound = .distantFuture; lastWords = .distantFuture; lock.unlock()
        guard seconds > 0 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            self.lock.lock()
            let sound = self.lastSound, words = self.lastWords
            self.lock.unlock()
            guard SilenceWatch.isQuiet(sound: sound, words: words, now: Date(), seconds: self.seconds)
            else { return }
            self.log.debug("quiet for \(self.seconds, format: .fixed(precision: 1))s — ending the take")
            self.stop()
            self.onSilence?()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
