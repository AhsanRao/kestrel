import AVFoundation
import Foundation
import Speech
import os

/// macOS 26's on-device speech engine — the same one system dictation runs on (spec §8.4).
///
/// API verified against the macOS 26.5 SDK's `Speech.swiftinterface` (2026-09-08):
///   `SpeechTranscriber(locale:preset:)`            `.transcription` = final results only
///   `AssetInventory.assetInstallationRequest(_:)`  nil once installed; ~100 ms warm, seconds cold
///   `SpeechAnalyzer.analyzeSequence(from:)`        takes an `AVAudioFile`, converts format itself
///   `AnalysisContext.contextualStrings[.general]`  vocabulary hints, whisper's `--prompt` twin
///
/// English only, deliberately: `SpeechTranscriber.supportedLocales` covers 30 locales and Urdu is
/// not among them, and Kestrel's Roman Urdu is spoken into an English transcript regardless.
@available(macOS 26.0, *)
final class AppleSpeechTranscriber: Transcriber {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "apple-speech")
    private let lock = NSLock()
    private var running: Task<Void, Never>?

    static let locale = Locale(identifier: "en-US")

    /// False on a Mac that cannot run the model at all, which sends the session back to whisper.
    static var isSupported: Bool { SpeechTranscriber.isAvailable }

    func cancel() {
        lock.lock(); let task = running; lock.unlock()
        task?.cancel()
    }

    /// Bridges the async engine to the blocking `Transcriber` contract. The coordinator calls this
    /// from its serial background queue — never the main thread, never a cooperative-pool thread —
    /// so parking that thread on a semaphore cannot deadlock the executor.
    func transcribe(_ wav: URL, config: Config) throws -> String {
        let box = OutcomeBox()
        let semaphore = DispatchSemaphore(value: 0)
        let started = Date()
        let task = Task<Void, Never> {
            do { box.outcome = .success(try await AppleSpeechTranscriber.run(wav, config: config)) }
            catch { box.outcome = .failure(error) }
            semaphore.signal()
        }
        lock.lock(); running = task; lock.unlock()
        defer { lock.lock(); running = nil; lock.unlock() }

        guard semaphore.wait(timeout: .now() + 120) == .success else {
            task.cancel()
            throw KestrelError.transcriptionFailed("Apple speech timed out")
        }
        switch box.outcome {
        case .success(let text):
            log.debug("transcribed \(text.count) chars in \(Int(Date().timeIntervalSince(started) * 1000))ms")
            return text
        case .failure(let error):
            throw AppleSpeechTranscriber.readable(error)
        case nil:
            throw KestrelError.transcriptionFailed("Apple speech returned nothing")
        }
    }

    private static func run(_ wav: URL, config: Config) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // Cheap once the model is on disk; the first ever call downloads it from Apple.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: wav)

        let context = AnalysisContext()
        let hints = vocabulary(config.transcriptionHint)
        if !hints.isEmpty { context.contextualStrings[.general] = hints }

        // Results must be drained while the file is being consumed, not after: the sequence is
        // live, and `analyzeSequence` will not return until something is reading it.
        let collector = Task { () -> [String] in
            var pieces: [String] = []
            for try await result in transcriber.results { pieces.append(String(result.text.characters)) }
            return pieces
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            try await analyzer.setContext(context)
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            throw error
        }
        return clean(try await collector.value)
    }

    /// Segments arrive with their own leading spaces, so they concatenate rather than join.
    ///
    /// Splitting on whitespace and rejoining collapses a run of any length. Replacing `"  "` with
    /// `" "` once, as this first did, only ever halves a run — the engine's own padding either side
    /// of a segment boundary makes four spaces, and four became two rather than one.
    static func clean(_ pieces: [String]) -> String {
        pieces.joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The same comma-separated hint field whisper passes to `--prompt`, split into the list of
    /// phrases this engine wants instead. Names and Roman Urdu words live here.
    static func vocabulary(_ hint: String?) -> [String] {
        guard let hint else { return [] }
        return hint.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func readable(_ error: Error) -> Error {
        if error is CancellationError { return KestrelError.transcriptionFailed("cancelled") }
        return KestrelError.transcriptionFailed(
            String(error.localizedDescription.prefix(200)))
    }

    /// Carries the task's result back across the semaphore. Written once inside the task, read
    /// once after `wait` returns, so the two accesses cannot overlap.
    private final class OutcomeBox: @unchecked Sendable {
        var outcome: Result<String, Error>?
    }
}
