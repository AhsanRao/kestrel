import AVFoundation
import Foundation
import os

/// `AVSpeechSynthesizer` and the voices macOS ships, a trained Personal Voice included. The
/// fallback engine, and the only one needing nothing installed.
///
/// `@unchecked Sendable`: the synthesizer is not Sendable; every method here runs on the main
/// thread.
final class SystemSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var isSpeaking = false
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    @discardableResult
    func speak(_ text: String, config: Config) -> Bool {
        stop()
        return enqueue(text, config: config)
    }

    @discardableResult
    func enqueue(_ text: String, config: Config) -> Bool {
        guard !text.isEmpty else { return false }
        synthesizer.speak(utterance(text, config: config))
        isSpeaking = true
        return true
    }

    /// Rate and pitch stay at their defaults, so a voice sounds as it does in System Settings.
    private func utterance(_ text: String, config: Config) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SystemSpeaker.voice(config: config)
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

    /// A Personal Voice is hidden from `speechVoices()` until asked for, so ask at launch. The
    /// answer is remembered per bundle id, and is silent when Accessibility already allows it.
    static func requestPersonalVoice() {
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
            log.info("personal voice authorization: \(status.rawValue, privacy: .public)")
        }
    }

    /// Configured voice, else the best installed one.
    static func voice(config: Config) -> AVSpeechSynthesisVoice? {
        if let identifier = config.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return bestAvailableVoice()
    }

    /// Compact voices are the synthetic-sounding tier; premium and enhanced are neural. Among
    /// equals, prefer the voices Apple built for long passages — the calmest.
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
        rank(quality: voice.quality,
             name: voice.name,
             language: voice.language,
             isPersonal: voice.voiceTraits.contains(.isPersonalVoice))
    }

    /// Over plain values: `AVSpeechSynthesisVoice` cannot be built in a test, and a Personal Voice
    /// exists only on the Mac that trained it.
    static func rank(quality: AVSpeechSynthesisVoiceQuality,
                     name: String,
                     language: String,
                     isPersonal: Bool) -> Int {
        // Wins outright: it reports `.default` quality, so ranking by quality would bury it.
        if isPersonal { return 400 }
        var score: Int
        switch quality {
        case .premium: score = 300
        case .enhanced: score = 200
        default: score = 100
        }
        if let index = preferredNames.firstIndex(where: { name.hasPrefix($0) }) {
            score += 50 - index
        }
        // A voice matching the user's own region needs no accent adjustment from the listener.
        if language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") { score += 10 }
        return score
    }

    /// True when only the robotic compact voices are installed, so the UI can offer to fix it.
    static var hasOnlyCompactVoices: Bool {
        !rankedVoices().contains { $0.quality != .default || $0.voiceTraits.contains(.isPersonalVoice) }
    }

    static func describe(_ voice: AVSpeechSynthesisVoice) -> String {
        if voice.voiceTraits.contains(.isPersonalVoice) { return "\(voice.name) · Personal" }
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Compact"
        }
        return "\(voice.name) · \(quality)"
    }
}
