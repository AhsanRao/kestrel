import AudioToolbox
import CoreAudio
import Foundation
import os

/// The front door for spoken answers (spec §8.9). Strips markdown, skips a muted output device,
/// and routes to the engine the config asks for. Both are held so neither is rebuilt mid-answer.
final class SpeechOutput: Speaker {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")

    private let system = SystemSpeaker()
    private let kokoro = KokoroSpeaker()

    /// The engine mid-sentence, so `stop()` and `isSpeaking` answer for the one actually talking.
    private var current: Speaker?

    var isSpeaking: Bool { current?.isSpeaking ?? false }

    var onFinish: (() -> Void)? {
        didSet {
            system.onFinish = onFinish
            kokoro.onFinish = onFinish
        }
    }

    /// A missing model is not an error — it is a skipped download, and the macOS voices still work.
    private func engine(for config: Config) -> Speaker {
        guard config.voiceEngine == .kokoro, KokoroInstall.isReady else { return system }
        return kokoro
    }

    @discardableResult
    func speak(_ text: String, config: Config) -> Bool {
        stop()
        return enqueue(text, config: config)
    }

    @discardableResult
    func enqueue(_ text: String, config: Config) -> Bool {
        let spoken = SpeechOutput.strippedForSpeech(text)
        guard !spoken.isEmpty else { return false }
        guard !SpeechOutput.isSystemOutputMuted else {
            Self.log.info("output muted, skipping speech")
            return false
        }
        let speaker = engine(for: config)
        // Or the old engine talks over the new one.
        if let current, current !== speaker { current.stop() }
        current = speaker
        return speaker.enqueue(spoken, config: config)
    }

    func stop() {
        system.stop()
        kokoro.stop()
        current = nil
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
