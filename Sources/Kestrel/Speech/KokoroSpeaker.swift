import AVFoundation
import Foundation
import os

/// Speaks with Kokoro, an 82 M-parameter neural voice model, run through sherpa-onnx's offline
/// synthesizer as a subprocess — the same shape as the whisper fallback, and for the same reason:
/// it keeps a C++ runtime out of the app while staying entirely on this Mac.
///
/// Synthesis is slower than playback is fast (about 1.5× real time), so sentences are synthesized
/// on a serial queue *while the previous one is still playing*. Only the first sentence of an
/// answer waits; after that the pipeline stays ahead of the ear.
///
/// `@unchecked Sendable`: every stored property is read and written on the main thread; only the
/// subprocess call itself runs on `synthQueue`.
final class KokoroSpeaker: NSObject, Speaker, AVAudioPlayerDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")

    /// Serial, so sentences come back in the order they were asked for.
    private let synthQueue = DispatchQueue(label: "dev.0xash.kestrel.kokoro", qos: .userInitiated)

    private var player: AVAudioPlayer?
    private var playing: URL?
    /// Synthesized and waiting for the ear.
    private var ready: [URL] = []
    /// Still inside the synthesizer. The answer is not over until this reaches zero.
    private var outstanding = 0
    /// Bumped by `stop()`, so a sentence that was already being synthesized is thrown away when it
    /// arrives instead of talking over whatever replaced it.
    private var generation = 0

    private(set) var isSpeaking = false
    var onFinish: (() -> Void)?

    @discardableResult
    func speak(_ text: String, config: Config) -> Bool {
        stop()
        return enqueue(text, config: config)
    }

    @discardableResult
    func enqueue(_ text: String, config: Config) -> Bool {
        guard KokoroInstall.isReady else { return false }
        let voice = KokoroVoice.named(config.kokoroVoice)
        let generation = self.generation
        outstanding += 1
        isSpeaking = true
        synthQueue.async { [weak self] in
            let url = KokoroSpeaker.synthesize(text, voice: voice)
            DispatchQueue.main.async {
                guard let self else { KokoroSpeaker.discard(url); return }
                guard generation == self.generation else { KokoroSpeaker.discard(url); return }
                self.outstanding -= 1
                if let url { self.ready.append(url) }
                self.playNextIfIdle()
            }
        }
        return true
    }

    func stop() {
        generation += 1
        player?.stop()
        player = nil
        KokoroSpeaker.discard(playing)
        playing = nil
        ready.forEach { KokoroSpeaker.discard($0) }
        ready.removeAll()
        outstanding = 0
        isSpeaking = false
    }

    // MARK: - Playback

    private func playNextIfIdle() {
        guard player == nil else { return }
        guard !ready.isEmpty else {
            // Nothing to play and nothing still cooking: the answer has been read out.
            if outstanding == 0, isSpeaking {
                isSpeaking = false
                onFinish?()
            }
            return
        }
        let url = ready.removeFirst()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1
            self.player = player
            playing = url
            player.play()
        } catch {
            Self.log.error("kokoro playback failed: \(error.localizedDescription, privacy: .public)")
            KokoroSpeaker.discard(url)
            playNextIfIdle()
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            KokoroSpeaker.discard(self.playing)
            self.playing = nil
            self.playNextIfIdle()
        }
    }

    // MARK: - Synthesis

    /// One sentence, one process. The model costs about 0.2 s to load, which is cheap enough to
    /// pay per sentence and buys back the memory between answers.
    ///
    /// Flags recorded from `sherpa-onnx-offline-tts --help`, v1.13.7:
    ///   --kokoro-model / --kokoro-voices / --kokoro-tokens   the model and its tables
    ///   --kokoro-data-dir                                    espeak-ng data, for phonemes
    ///   --kokoro-lexicon                                     pronunciations; required for v1.0
    ///   --sid                                                speaker index, not a name
    ///   --num-threads=4                                      measured fastest on Apple Silicon
    private static func synthesize(_ text: String, voice: KokoroVoice) -> URL? {
        let output = Paths.temporaryFile(ext: "wav")
        let process = Process()
        process.executableURL = KokoroInstall.binary
        process.arguments = [
            "--kokoro-model=\(KokoroInstall.model.path)",
            "--kokoro-voices=\(KokoroInstall.voices.path)",
            "--kokoro-tokens=\(KokoroInstall.tokens.path)",
            "--kokoro-data-dir=\(KokoroInstall.espeakData.path)",
            "--kokoro-lexicon=\(KokoroInstall.lexicon.path)",
            "--num-threads=4",
            "--sid=\(voice.speakerID)",
            "--output-filename=\(output.path)",
            text,
        ]
        let errors = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        do {
            try process.run()
        } catch {
            log.error("kokoro failed to start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path) else {
            let detail = String(data: stderr, encoding: .utf8)?.suffix(300) ?? ""
            log.error("kokoro synthesis failed: \(String(detail), privacy: .public)")
            return nil
        }
        return output
    }

    private static func discard(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
