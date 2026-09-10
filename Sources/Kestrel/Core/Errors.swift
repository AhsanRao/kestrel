import Foundation

/// Every error the user can see. Written the way Kestrel talks — a person telling you what
/// happened and what to do about it, in a 420 pt panel. Never a status code, never "unable to".
enum KestrelError: LocalizedError, Equatable {
    case whisperBinaryMissing(String)
    case whisperModelMissing(String)
    case transcriptionFailed(String)
    case emptyTranscript
    case microphoneDenied
    case screenRecordingDenied
    case screenshotFailed(String)
    case backendMissing(String)
    case backendFailed(name: String, stderr: String)
    case backendTimedOut(name: String, seconds: Int)
    case quotaExhausted(String)
    case accessibilityDenied
    case hotkeyRegistrationFailed(String)
    case hotkeyNeedsAccessibility(String)
    case actionDenied(String)
    case actionFailed(String)
    case speech(String)

    var errorDescription: String? {
        switch self {
        case .whisperBinaryMissing(let path):
            return "I can't find whisper-cli at \(path). Run: brew install whisper-cpp"
        case .whisperModelMissing(let path):
            return "The speech model isn't at \(path) yet. Run: scripts/download-whisper-model.sh"
        case .transcriptionFailed(let detail):
            return "I couldn't make that out — \(detail)"
        case .emptyTranscript:
            return "Didn't catch that. Have another go, a bit closer to the mic"
        case .microphoneDenied:
            return "I need the microphone to hear you. System Settings ▸ Privacy & Security ▸ Microphone"
        case .screenRecordingDenied:
            return "I can't see your screen yet. System Settings ▸ Privacy & Security ▸ Screen Recording, then start me again"
        case .screenshotFailed(let detail):
            return "The screenshot didn't come through — \(detail)"
        case .backendMissing(let name):
            return name == "codex"
                ? "Codex isn't installed. Run: npm i -g @openai/codex && codex login"
                : "Claude Code isn't installed. Install it, then run: claude auth"
        case .backendFailed(let name, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name) stopped short — \(trimmed.isEmpty ? "it said nothing at all" : String(trimmed.prefix(400)))"
        case .backendTimedOut(let name, let seconds):
            return "\(name) is taking too long — I gave up after \(seconds)s. Ask me again"
        case .quotaExhausted(let name):
            return "You're out of \(name) for now. Switch brains from the menu bar, or add an API key in Settings ▸ Advanced"
        case .accessibilityDenied:
            return "I need Accessibility to type and click for you. System Settings ▸ Privacy & Security ▸ Accessibility, then switch me on"
        case .hotkeyRegistrationFailed(let combo):
            return "Something else already owns \(combo). Pick another in Settings ▸ Shortcuts"
        case .actionDenied(let what):
            return "I'm not allowed to \(what). Edit ~/.kestrel/policy.json if you want me to"
        case .actionFailed(let what):
            return "I tried to \(what), but it didn't respond"
        case .speech(let detail):
            return detail
        case .hotkeyNeedsAccessibility(let combo):
            return "I can't see \(combo) without Accessibility. System Settings ▸ Privacy & Security ▸ Accessibility, then switch me on"
        }
    }

    /// Privacy pane to deep-link to from the panel, when the error is a permission problem.
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .screenRecordingDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibilityDenied, .hotkeyNeedsAccessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        default:
            return nil
        }
    }
}
