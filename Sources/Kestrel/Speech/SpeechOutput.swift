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

    /// Replaces anything being said. Returns false when nothing was spoken because system output
    /// is muted.
    @discardableResult
    func speak(_ text: String, config: Config) -> Bool {
        stop()
        return enqueue(text, config: config)
    }

    /// Adds to what is already queued, so an answer arriving sentence by sentence is read as one
    /// continuous reply rather than restarting on every fragment.
    @discardableResult
    func enqueue(_ text: String, config: Config) -> Bool {
        let spoken = SpeechOutput.strippedForSpeech(text)
        guard !spoken.isEmpty else { return false }
        guard !SpeechOutput.isSystemOutputMuted else {
            log.info("output muted, skipping speech")
            return false
        }
        synthesizer.speak(utterance(spoken, config: config))
        isSpeaking = true
        return true
    }

    /// Rate and pitch matter as much as the voice: the stock 0.5 rate with a flat pitch is what
    /// makes system speech sound robotic. Slightly slower, very slightly lower, with a beat of
    /// silence between sentences, reads as someone talking rather than a machine reciting.
    private func utterance(_ text: String, config: Config) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SpeechOutput.voice(config: config)
        utterance.rate = Float(config.voiceRate)
        utterance.pitchMultiplier = Float(config.voicePitch)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.12
        return utterance
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

    /// Configured voice, else the best installed one.
    static func voice(config: Config) -> AVSpeechSynthesisVoice? {
        if let identifier = config.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return bestAvailableVoice()
    }

    /// macOS ships several tiers under the same names. The compact voices are the ones that sound
    /// synthetic; premium and enhanced are neural and are what Kestrel wants. Among equals, prefer
    /// the voices Apple built for reading long passages, which are the calmest.
    static let preferredNames = ["Ava", "Zoe", "Serena", "Allison", "Samantha", "Evan", "Tom", "Nathan", "Joelle"]

    static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        rankedVoices().first
    }

    /// Every usable voice, best first — what the settings picker shows.
    static func rankedVoices() -> [AVSpeechSynthesisVoice] {
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(preferredLanguage) || $0.language.hasPrefix("en") }
            .filter { !$0.identifier.contains("eloquence") }        // the 1980s-sounding set
            .sorted { rank($0) > rank($1) }
    }

    static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score: Int
        switch voice.quality {
        case .premium: score = 300
        case .enhanced: score = 200
        default: score = 100
        }
        if let index = preferredNames.firstIndex(where: { voice.name.hasPrefix($0) }) {
            score += 50 - index
        }
        // A voice matching the user's own region needs no accent adjustment from the listener.
        if voice.language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") { score += 10 }
        return score
    }

    /// True when only the robotic compact voices are installed, so the UI can offer to fix it.
    static var hasOnlyCompactVoices: Bool {
        !rankedVoices().contains { $0.quality != .default }
    }

    static func describe(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Compact"
        }
        return "\(voice.name) · \(quality)"
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
