import Foundation
import os

/// Swappable speech-to-text. Only local implementations ship: audio never leaves the Mac.
protocol Transcriber: AnyObject {
    /// Blocking. Returns the cleaned transcript, or throws `KestrelError`.
    func transcribe(_ wav: URL, config: Config) throws -> String
    func cancel()
}

/// Chooses the engine per call, so editing `transcriptionEngine` in `config.json` takes effect
/// without a relaunch. Apple's engine is the default — measured at roughly 6× whisper's speed on
/// the same clip, with no model to download and no invented words on silence — and whisper stays
/// for macOS 14 and 15, and for anyone who would rather run it.
final class RoutingTranscriber: Transcriber {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "transcriber")
    private let whisper = WhisperTranscriber()
    private let lock = NSLock()
    private var appleTranscriber: Transcriber?
    private var inFlight: Transcriber?

    /// Nil below macOS 26, or where the model cannot run on this Mac at all.
    private func apple() -> Transcriber? {
        guard #available(macOS 26.0, *), AppleSpeechTranscriber.isSupported else { return nil }
        lock.lock(); defer { lock.unlock() }
        if appleTranscriber == nil { appleTranscriber = AppleSpeechTranscriber() }
        return appleTranscriber
    }

    func engine(for config: Config) -> Transcriber {
        guard config.effectiveTranscriptionEngine == .apple, let apple = apple() else { return whisper }
        return apple
    }

    func transcribe(_ wav: URL, config: Config) throws -> String {
        let engine = engine(for: config)
        lock.lock(); inFlight = engine; lock.unlock()
        defer { lock.lock(); inFlight = nil; lock.unlock() }
        return try engine.transcribe(wav, config: config)
    }

    func cancel() {
        lock.lock(); let engine = inFlight; lock.unlock()
        engine?.cancel()
    }
}

extension Config {
    /// The engine that will actually run. Asking for Apple's below macOS 26 quietly gets whisper,
    /// which is what the dependency check has to report and what the settings pane has to explain.
    var effectiveTranscriptionEngine: TranscriptionEngine {
        guard transcriptionEngine == .apple else { return .whisper }
        if #available(macOS 26.0, *), AppleSpeechTranscriber.isSupported { return .apple }
        return .whisper
    }
}
