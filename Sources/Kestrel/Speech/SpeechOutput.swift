import AVFoundation
import CoreAudio
import Foundation
import os

/// Speaks answers with `AVSpeechSynthesizer`. Markdown is stripped for speech only; the panel keeps
/// the formatted text (spec §8.9).
/// `@unchecked Sendable`: `AVSpeechSynthesizerDelegate` is implicitly Sendable, but the
/// synthesizer it holds is not. Every method here is called on the main thread.
final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")
    private let synthesizer = AVSpeechSynthesizer()

    /// True while audio is actually playing, so the coordinator can hold the panel open.
    private(set) var isSpeaking = false
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Returns false when nothing was spoken because system output is muted.
    @discardableResult
    func speak(_ text: String, config: Config) -> Bool {
        stop()
        let spoken = SpeechOutput.strippedForSpeech(text)
        guard !spoken.isEmpty else { return false }
        guard !SpeechOutput.isSystemOutputMuted else {
            log.info("output muted, skipping speech")
            return false
        }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.rate = Float(config.voiceRate)
        utterance.voice = SpeechOutput.voice(config: config)
        isSpeaking = true
        synthesizer.speak(utterance)
        return true
    }

    func stop() {
        guard synthesizer.isSpeaking else { isSpeaking = false; return }
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        DispatchQueue.main.async { self.onFinish?() }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    // MARK: - Voice

    /// Configured voice, else the best installed English voice (premium > enhanced > default).
    static func voice(config: Config) -> AVSpeechSynthesisVoice? {
        if let identifier = config.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return bestAvailableVoice()
    }

    static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(preferred) || $0.language.hasPrefix("en") }
        func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return candidates.max(by: { rank($0) < rank($1) })
    }

    // MARK: - Text

    /// Markdown reads terribly out loud: asterisks become "asterisk", fences become noise.
    static func strippedForSpeech(_ text: String) -> String {
        var lines: [String] = []
        var insideFence = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                insideFence.toggle()
                continue
            }
            if insideFence { continue }
            line = line.replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^\\s*[-*+]\\s+", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "^\\s*>\\s?", with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: "`", with: "")
            line = line.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "(?<!\\w)\\*(.+?)\\*(?!\\w)", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\[(.+?)\\]\\((.+?)\\)", with: "$1", options: .regularExpression)
            line = line.replacingOccurrences(of: "\\s*—\\s*", with: ", ", options: .regularExpression)
            line = line.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
            lines.append(line.trimmingCharacters(in: .whitespaces))
        }
        return lines.filter { !$0.isEmpty }.joined(separator: ". ")
            .replacingOccurrences(of: "..", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Mute detection

    /// Default output device muted, or its volume at zero.
    static var isSystemOutputMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        if let muted: UInt32 = property(device, kAudioDevicePropertyMute), muted == 1 { return true }
        if let volume: Float32 = property(device, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) {
            return volume < 0.01
        }
        return false
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func property<T>(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
