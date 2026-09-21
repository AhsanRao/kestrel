import Foundation

/// A streaming engine that says what it is told to, on a clock, for exercising the live-ask flow
/// without a microphone: `KESTREL_SAY="open Finder;what app is this" KESTREL_SAY_RELEASE=5`.
///
/// Each phrase arrives as one settled result followed by the pause, a beat and a half apart, the
/// way a person saying two things in a row sounds to `SilenceWatch`.
final class ScriptedMicrophone: LiveDictating {
    var onFinal: ((String) -> Void)?
    var onVolatile: ((String) -> Void)?
    var onSilence: (() -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?
    private(set) var isRunning = false

    private let phrases: [String]
    private let gap: TimeInterval
    private var next = 0

    init(phrases: [String], gap: TimeInterval = 1.5) {
        self.phrases = phrases
        self.gap = gap
    }

    func start(config: Config) {
        isRunning = true
        say()
    }

    func listenAgain() {
        guard isRunning else { return }
        say()
    }

    func stop(completion: @escaping () -> Void) {
        isRunning = false
        DispatchQueue.main.async(execute: completion)
    }

    private func say() {
        guard next < phrases.count else { return }
        let phrase = phrases[next]
        next += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + gap) { [weak self] in
            guard let self, self.isRunning else { return }
            self.onVolatile?(String(phrase.prefix(phrase.count / 2)))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isRunning else { return }
                self.onFinal?(phrase)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.isRunning else { return }
                    self.onSilence?()
                }
            }
        }
    }
}
