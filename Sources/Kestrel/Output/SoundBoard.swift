import AVFoundation
import Foundation
import os

/// Short tones marking each state change, so Kestrel feels responsive before it has said anything.
///
/// The tones are synthesised rather than shipped: no audio files in the repo, nothing to license,
/// and the shape of each cue is code that can be tested. They are deliberately quiet and under a
/// fifth of a second — a cue, not a jingle.
final class SoundBoard {
    enum Cue: String, CaseIterable {
        case listening      // hotkey down, recording started
        case heard          // hotkey released, transcribing
        case answered       // an answer arrived
        case inserted       // dictated text landed in the app
        case failed         // something went wrong

        /// Rising for progress, falling for failure. Frequencies in hertz.
        var tones: [Double] {
            switch self {
            case .listening: return [660, 880]
            case .heard: return [780]
            case .answered: return [880, 1174]
            case .inserted: return [990]
            case .failed: return [440, 330]
            }
        }

        var toneDuration: Double {
            switch self {
            case .heard, .inserted: return 0.055
            default: return 0.075
            }
        }

        var level: Float {
            switch self {
            case .failed: return 0.16
            default: return 0.11
            }
        }
    }

    static let sampleRate: Double = 44_100

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "sound")
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var started = false

    /// Whether a cue should be heard at all: enabled, and the Mac not muted.
    static func shouldPlay(config: Config, muted: Bool) -> Bool {
        config.sounds && !muted
    }

    func play(_ cue: Cue, config: Config) {
        guard SoundBoard.shouldPlay(config: config, muted: SpeechOutput.isSystemOutputMuted) else { return }
        guard let format = ensureEngine() else { return }
        let samples = SoundBoard.render(cue)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        guard started else { return }
        player.stop()
        engine.stop()
        started = false
    }

    private func ensureEngine() -> AVAudioFormat? {
        if started, let format { return format }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundBoard.sampleRate, channels: 1)
        else { return nil }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            log.error("could not start audio engine: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.format = format
        started = true
        return format
    }

    // MARK: - Synthesis

    /// The samples for one cue: its tones back to back, each shaped by an envelope so it starts and
    /// ends silently. Without the fades every tone would begin and end with an audible click.
    static func render(_ cue: Cue) -> [Float] {
        var samples: [Float] = []
        for frequency in cue.tones {
            samples += tone(frequency: frequency, duration: cue.toneDuration, level: cue.level)
        }
        return samples
    }

    static func tone(frequency: Double, duration: Double, level: Float) -> [Float] {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return [] }
        let fade = max(1, count / 6)
        return (0..<count).map { index in
            let phase = 2 * Double.pi * frequency * Double(index) / sampleRate
            // Linear in, cosine out: a soft attack and a tail that does not thud.
            let envelope: Double
            if index < fade {
                envelope = Double(index) / Double(fade)
            } else if index > count - fade {
                envelope = Double(count - index) / Double(fade)
            } else {
                envelope = 1
            }
            return Float(sin(phase) * envelope) * level
        }
    }
}
