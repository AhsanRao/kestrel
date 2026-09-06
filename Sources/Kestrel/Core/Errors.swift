import Foundation

/// Every error the user can see. Messages are written to be actionable in a 420 pt panel:
/// what went wrong, and the exact command that fixes it.
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

    var errorDescription: String? {
        switch self {
        case .whisperBinaryMissing(let path):
            return "whisper-cli not found at \(path) — run: brew install whisper-cpp"
        case .whisperModelMissing(let path):
            return "Whisper model missing at \(path) — run: scripts/download-whisper-model.sh"
        case .transcriptionFailed(let detail):
            return "Transcription failed: \(detail)"
        case .emptyTranscript:
            return "Didn't catch that — try again, closer to the mic"
        case .microphoneDenied:
            return "Microphone access denied — System Settings ▸ Privacy & Security ▸ Microphone"
        case .screenRecordingDenied:
            return "Screen Recording permission needed — System Settings ▸ Privacy & Security ▸ Screen Recording, then relaunch Kestrel"
        case .screenshotFailed(let detail):
            return "Could not capture the screen: \(detail)"
        case .backendMissing(let name):
            return name == "codex"
                ? "codex not found — run: npm i -g @openai/codex && codex login"
                : "claude not found — install Claude Code, then run: claude auth"
        case .backendFailed(let name, let stderr):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name) failed: \(trimmed.isEmpty ? "no output" : String(trimmed.prefix(400)))"
        case .backendTimedOut(let name, let seconds):
            return "\(name) timed out after \(seconds)s"
        case .quotaExhausted(let name):
            return "\(name) usage limit reached — switch backend from the menu bar, or set an API key in ~/.kestrel/config.json"
        case .accessibilityDenied:
            return "Accessibility permission needed to paste — System Settings ▸ Privacy & Security ▸ Accessibility"
        case .hotkeyRegistrationFailed(let combo):
            return "Hotkey \(combo) is already taken by another app — pick a different one in Settings"
        case .hotkeyNeedsAccessibility(let combo):
            return "The \(combo) hotkey needs Accessibility to be seen — System Settings ▸ Privacy & Security ▸ Accessibility, then switch Kestrel on"
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
