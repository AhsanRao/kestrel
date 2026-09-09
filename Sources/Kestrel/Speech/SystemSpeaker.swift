import AVFoundation
import Foundation
import os

/// Speaks with `AVSpeechSynthesizer`, the voices macOS ships — including a Personal Voice, if the
/// user has trained one. Kestrel's fallback engine, and the only one that needs nothing installed.
///
/// `@unchecked Sendable`: `AVSpeechSynthesizerDelegate` is implicitly Sendable, but the synthesizer
/// it holds is not. Every method here is called on the main thread.
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

    /// Rate and pitch are left at `AVSpeechUtterance`'s defaults, so a voice sounds here exactly as
    /// it does in System Settings' own preview — no Kestrel-specific tuning to fight against.
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

    /// A Personal Voice is the user's own voice, trained on-device (macOS 14+). It is hidden from
    /// `speechVoices()` until the app asks for it, so ask once at launch, long before the first
    /// answer needs speaking. The system remembers the answer per bundle id; when the user has
    /// already allowed apps to use it in Accessibility settings, nothing is shown on screen.
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
        rank(quality: voice.quality,
             name: voice.name,
             language: voice.language,
             isPersonal: voice.voiceTraits.contains(.isPersonalVoice))
    }

    /// The ranking itself, over plain values, because `AVSpeechSynthesisVoice` cannot be
    /// constructed in a test and a personal voice exists only on the Mac that trained one.
    static func rank(quality: AVSpeechSynthesisVoiceQuality,
                     name: String,
                     language: String,
                     isPersonal: Bool) -> Int {
        // The user's own voice wins outright. It reports `.default` quality — the same tier as the
        // robotic compact voices — so ranking it by quality would bury it at the bottom.
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
