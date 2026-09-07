import AVFoundation
import CoreGraphics
import Foundation

/// One source of truth for "can Kestrel actually work right now", used by the onboarding window,
/// the menu bar's dependency report, and `scripts/check-deps.sh`'s in-app twin.
enum DependencyCheck {
    enum Requirement: String, CaseIterable {
        case microphone, screenRecording, accessibility
        case whisperBinary, whisperModel, claude, codex

        var title: String {
            switch self {
            case .microphone: return "Microphone"
            case .screenRecording: return "Screen Recording"
            case .accessibility: return "Accessibility"
            case .whisperBinary: return "whisper-cli"
            case .whisperModel: return "Speech model"
            case .claude: return "Claude Code CLI"
            case .codex: return "Codex CLI"
            }
        }

        /// Why Kestrel wants it, in the user's terms.
        var reason: String {
            switch self {
            case .microphone: return "To hear the question you hold the hotkey to ask."
            case .screenRecording: return "To see the screen you are asking about."
            case .accessibility: return "To hold ⌃⌥ as a hotkey, to paste dictated text, and to circle part of the screen."
            case .whisperBinary: return "Turns your voice into text on this Mac. Nothing is uploaded."
            case .whisperModel: return "The speech model whisper reads. About 148 MB."
            case .claude: return "Answers your questions using your Claude subscription."
            case .codex: return "Optional second backend, using your ChatGPT subscription."
            }
        }

        /// False for things Kestrel can run without.
        var isRequired: Bool {
            switch self {
            case .codex, .accessibility: return false
            default: return true
            }
        }

        /// A granted permission only takes effect after a relaunch.
        var needsRelaunch: Bool { self == .screenRecording }
    }

    struct Item {
        var requirement: Requirement
        var ok: Bool
        var detail: String

        var name: String { requirement.title }
    }

    struct Report {
        var items: [Item]

        var allGood: Bool { items.allSatisfy(\.ok) }
        var readyToUse: Bool { items.filter { $0.requirement.isRequired }.allSatisfy(\.ok) }
        var summary: String {
            items.map { "\($0.ok ? "✓" : "✗")  \($0.name) — \($0.detail)" }.joined(separator: "\n")
        }

        func item(_ requirement: Requirement) -> Item? {
            items.first { $0.requirement == requirement }
        }
    }

    static func run(config: Config) -> Report {
        Report(items: Requirement.allCases.map { check($0, config: config) })
    }

    static func check(_ requirement: Requirement, config: Config) -> Item {
        switch requirement {
        case .microphone:
            let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "Allowed" : "System Settings ▸ Privacy & Security ▸ Microphone")

        case .screenRecording:
            let granted = CGPreflightScreenCaptureAccess()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "Allowed" : "System Settings ▸ Privacy & Security ▸ Screen Recording")

        case .accessibility:
            let granted = AXIsProcessTrusted()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "Allowed" : "Needed for the ask hotkey and dictation")

        case .whisperBinary:
            let url = config.whisperBinaryURL
            let found = FileManager.default.isExecutableFile(atPath: url.path)
            return Item(requirement: requirement, ok: found,
                        detail: found ? url.path : "brew install whisper-cpp")

        case .whisperModel:
            let url = config.whisperModelURL
            let found = FileManager.default.fileExists(atPath: url.path)
            return Item(requirement: requirement, ok: found,
                        detail: found ? Paths.tildeAbbreviated(url) : "./scripts/download-whisper-model.sh")

        case .claude, .codex:
            let name = requirement == .claude ? "claude" : "codex"
            if let url = CLIRunner.locate(name) {
                return Item(requirement: requirement, ok: true, detail: url.path)
            }
            let fix = requirement == .claude
                ? "Install Claude Code, then run: claude auth"
                : "npm i -g @openai/codex && codex login"
            return Item(requirement: requirement, ok: false, detail: fix)
        }
    }

    /// The shell command that fixes a missing dependency, for the onboarding window's copy button.
    static func fixCommand(for requirement: Requirement) -> String? {
        switch requirement {
        case .whisperBinary: return "brew install whisper-cpp"
        case .whisperModel: return "./scripts/download-whisper-model.sh"
        case .codex: return "npm i -g @openai/codex && codex login"
        case .claude: return "claude auth"
        default: return nil
        }
    }
}
