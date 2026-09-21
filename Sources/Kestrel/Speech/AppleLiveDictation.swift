import AVFoundation
import Foundation
import Speech
import os

/// The same on-device engine as `AppleSpeechTranscriber`, fed the microphone as it is spoken
/// instead of a finished file (spec §8.4).
///
/// API verified against the macOS 26.5 SDK's `Speech.swiftinterface` (2026-09-10):
///   `SpeechTranscriber(locale:preset:)` with `.progressiveTranscription` — volatile results while
///     the words are still being said, then one final result per settled stretch
///   `SpeechAnalyzer.start(inputSequence:)`         an `AsyncSequence` of `AnalyzerInput(buffer:)`
///   `SpeechAnalyzer.bestAvailableAudioFormat(_:)`  the format the tap has to be converted into
///   `SpeechAnalyzer.finalizeAndFinishThroughEndOfInput()` settles the tail and ends `results`
///
/// Lock-guarded rather than actor-isolated: the audio tap runs on a real-time thread that cannot
/// await anything, and every callback is hopped to the main queue before it leaves.
@available(macOS 26.0, *)
final class AppleLiveDictation: LiveDictating, @unchecked Sendable {
    var onFinal: ((String) -> Void)?
    var onVolatile: ((String) -> Void)?
    var onSilence: (() -> Void)?
    var onLevel: ((Float) -> Void)?
    var onFailure: ((Error) -> Void)?

    internal let log = Logger(subsystem: "dev.0xash.kestrel", category: "live-dictation")
    internal let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    internal var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var collector: Task<Void, Never>?
    internal var converter: AVAudioConverter?
    internal var meter = LevelMeter()
    internal var lastLevelSent = Date.distantPast
    internal let silence = SilenceWatch()
    internal var silenceSeconds: TimeInterval = 0

    private(set) var isRunning = false

    func start(config: Config) {
        guard !isRunning else { return }
        isRunning = true
        silenceSeconds = config.dictationSilenceSeconds
        meter.reset()
        silence.onSilence = { [weak self] in self?.onSilence?() }

        Task { [weak self] in
            guard let self else { return }
            do { try await self.begin(config: config) } catch { self.fail(error) }
        }
    }

    func listenAgain() {
        guard isRunning else { return }
        silence.start(seconds: silenceSeconds)
    }

    func stop(completion: @escaping () -> Void) {
        guard isRunning else { return completion() }
        isRunning = false
        silence.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        continuation?.finish()
        continuation = nil

        let analyzer = self.analyzer
        let collector = self.collector
        self.analyzer = nil
        self.collector = nil
        Task { [weak self] in
            do { try await analyzer?.finalizeAndFinishThroughEndOfInput() }
            catch { self?.log.error("finalize: \(error.localizedDescription, privacy: .public)") }
            // The last final result arrives on the way out; waiting for the collector is what makes
            // the tail of a sentence land in the app rather than being dropped with the engine.
            _ = await collector?.value
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Private

    private func begin(config: Config) async throws {
        let transcriber = SpeechTranscriber(locale: AppleSpeechTranscriber.locale,
                                            preset: .progressiveTranscription)
        // Cheap once the model is on disk; the first ever call downloads it from Apple.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let context = AnalysisContext()
        let hints = AppleSpeechTranscriber.vocabulary(config.transcriptionHint)
        if !hints.isEmpty { context.contextualStrings[.general] = hints }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.setContext(context)
        try await analyzer.start(inputSequence: stream)
        let target = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        guard isRunning else { return continuation.finish() }
        self.analyzer = analyzer
        self.continuation = continuation
        self.collector = collect(from: transcriber)
        try startEngine(feeding: target)
        log.debug("live dictation running at \(target?.sampleRate ?? 0) Hz")
    }

    private func collect(from transcriber: SpeechTranscriber) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    guard let self else { return }
                    // Half of what decides the pause. `SpeechDetector`, the framework's own
                    // voice-activity module, was tried here first and reported nothing at all on
                    // this machine.
                    self.silence.heardWords()
                    DispatchQueue.main.async {
                        isFinal ? self.onFinal?(text) : self.onVolatile?(text)
                    }
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        guard isRunning else { return }
        DispatchQueue.main.async { [weak self] in self?.onFailure?(error) }
    }
}
