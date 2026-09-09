import AVFoundation
import Foundation
import os

/// Kokoro through sherpa-onnx's offline synthesizer, spawned per sentence — the whisper-fallback
/// shape, keeping a C++ runtime out of the app.
///
/// Synthesis runs while the previous sentence plays, so only the first one waits.
///
/// `@unchecked Sendable`: state is main-thread only; just the subprocess runs on `synthQueue`.
final class KokoroSpeaker: NSObject, Speaker, AVAudioPlayerDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")

    /// Serial, so sentences come back in order.
    private let synthQueue = DispatchQueue(label: "dev.0xash.kestrel.kokoro", qos: .userInitiated)

    private var player: AVAudioPlayer?
    private var playing: URL?
    /// Synthesized, waiting to play.
    private var ready: [URL] = []
    /// Still synthesizing. The answer is not over until this hits zero.
    private var outstanding = 0
    /// Bumped by `stop()`, so work already in flight is discarded rather than talked over.
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
            // Nothing queued and nothing synthesizing: the answer is read out.
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

    /// One sentence, one process — the model loads in ~0.2 s, cheap enough to pay each time.
    ///
    /// Flags from `sherpa-onnx-offline-tts --help`, v1.13.7. `--sid` is an index, not a name;
    /// `--kokoro-lexicon` is required for v1.0; four threads measured fastest on Apple Silicon.
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
