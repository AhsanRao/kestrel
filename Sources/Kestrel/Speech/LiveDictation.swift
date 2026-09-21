import Foundation

/// Dictation that types while you are still talking, rather than after you stop.
///
/// The batch path — record a WAV, transcribe it when the key is pressed again, paste the lot —
/// is still there underneath, and is what runs when this is unavailable. What it cannot do is
/// show a word before the sentence is over, or end itself when the room goes quiet.
protocol LiveDictating: AnyObject {
    /// A stretch of speech the engine has settled on. It will not change, so it can be typed.
    var onFinal: ((String) -> Void)? { get set }
    /// The engine's running guess at what is still being said. It changes with every syllable, so
    /// it belongs on the panel and nowhere else.
    var onVolatile: ((String) -> Void)? { get set }
    /// The speaker has stopped — see `SilenceWatch` for what that means.
    var onSilence: (() -> Void)? { get set }
    /// Smoothed input level, 0…1, on the main thread — the panel's waveform.
    var onLevel: ((Float) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }

    var isRunning: Bool { get }
    func start(config: Config)
    /// Arms the pause again after `onSilence`, for an engine that is kept running: the next
    /// stretch of speech will end with its own `onSilence`.
    func listenAgain()
    /// Settles whatever is still in flight, then calls back on the main thread.
    func stop(completion: @escaping () -> Void)
}

enum LiveDictation {
    /// Nil below macOS 26, or on a Mac that cannot run the model, or when the user has chosen
    /// whisper — none of which can transcribe a stream. Dictation then records a take and
    /// transcribes it when the hotkey is pressed again, exactly as it always did.
    static func make(for config: Config) -> LiveDictating? {
        guard config.effectiveTranscriptionEngine == .apple else { return nil }
        guard #available(macOS 26.0, *) else { return nil }
        return AppleLiveDictation()
    }
}
