import AVFoundation
import CoreGraphics
import Foundation

/// One source of truth for "can Kestrel actually work right now", used by the onboarding window,
/// the menu bar's dependency report, and `scripts/check-deps.sh`'s in-app twin.
enum DependencyCheck {
    enum Requirement: String, CaseIterable {
        case microphone, screenRecording, accessibility
        case speech, whisperBinary, whisperModel, voice, claude, codex

        var title: String {
            switch self {
            case .microphone: return "Microphone"
            case .screenRecording: return "Screen Recording"
            case .accessibility: return "Accessibility"
            case .speech: return "Hearing you"
            case .whisperBinary: return "whisper-cli"
            case .whisperModel: return "Speech model"
            case .voice: return "My voice"
            case .claude: return "Claude"
            case .codex: return "Codex"
            }
        }

        /// Why Kestrel wants it, in the user's terms.
        var reason: String {
            switch self {
            case .microphone: return "So I can hear you when you hold the hotkey."
            case .screenRecording: return "So I can see the screen you're asking about."
            case .accessibility: return "So ⌘⌥ works as a hotkey, dictation can paste, and you can circle things."
            case .speech: return "Turns your voice into text, right here. Nothing gets uploaded."
            case .whisperBinary: return "The engine you told me to use instead of Apple's."
            case .whisperModel: return "The model whisper reads from. About 148 MB."
            case .voice: return "My proper voice. Skip it and I'll use one of macOS's instead."
            case .claude: return "How I think. Runs on your Claude subscription."
            case .codex: return "A second brain, on your ChatGPT subscription."
            }
        }

        /// False for things Kestrel can run without.
        ///
        /// Accessibility depends on how the ask hotkey is bound. A bare modifier chord — the
        /// default ⌘⌥ — cannot be registered with Carbon and is watched through an event tap, so
        /// without the grant the hotkey cannot fire at all and the app is not reduced but unusable.
        /// Bound to an ordinary keyed shortcut it is merely recommended: dictation and circling
        /// need it, asking does not.
        func isRequired(for config: Config) -> Bool {
            switch self {
            case .codex, .voice: return false
            case .accessibility: return config.hotkeys.ask.isModifierOnly
            default: return true
            }
        }

    }

    struct Item {
        var requirement: Requirement
        var ok: Bool
        var detail: String
        /// Decided when the report is built, because it depends on the config — see
        /// `Requirement.isRequired(for:)`. Carried here so the window and the launch check cannot
        /// disagree about what is optional.
        var isRequired: Bool = true

        var name: String { requirement.title }
    }

    struct Report {
        var items: [Item]

        var allGood: Bool { items.allSatisfy(\.ok) }
        var readyToUse: Bool { items.filter(\.isRequired).allSatisfy(\.ok) }
        var summary: String {
            items.map { "\($0.ok ? "✓" : "✗")  \($0.name) — \($0.detail)" }.joined(separator: "\n")
        }

        func item(_ requirement: Requirement) -> Item? {
            items.first { $0.requirement == requirement }
        }
    }

    /// Apple's speech engine needs no binary and no model file, so on macOS 26 the two whisper
    /// rows are not shown at all rather than shown as something missing.
    static func run(config: Config) -> Report {
        let usesWhisper = config.effectiveTranscriptionEngine == .whisper
        let requirements = Requirement.allCases.filter {
            usesWhisper || ($0 != .whisperBinary && $0 != .whisperModel)
        }
        return Report(items: requirements.map { requirement in
            var item = check(requirement, config: config)
            item.isRequired = requirement.isRequired(for: config)
            return item
        })
    }

    static func check(_ requirement: Requirement, config: Config) -> Item {
        switch requirement {
        case .microphone:
            let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "All good" : "System Settings ▸ Privacy & Security ▸ Microphone")

        case .screenRecording:
            let granted = CGPreflightScreenCaptureAccess()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "All good" : "System Settings ▸ Privacy & Security ▸ Screen Recording")

        case .accessibility:
            let granted = AXIsProcessTrusted()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "All good" : "Needed for the hotkey and for dictation")

        case .speech:
            if config.effectiveTranscriptionEngine == .apple {
                return Item(requirement: requirement, ok: true, detail: "Apple's, built in — nothing to install")
            }
            let ready = check(.whisperBinary, config: config).ok && check(.whisperModel, config: config).ok
            return Item(requirement: requirement, ok: ready,
                        detail: ready ? "whisper.cpp" : "whisper.cpp — see the two rows below")

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

        case .voice:
            if config.voiceEngine == .system {
                return Item(requirement: requirement, ok: true, detail: "Using a macOS voice")
            }
            let installed = KokoroInstall.isReady
            return Item(requirement: requirement, ok: installed,
                        detail: installed ? Paths.tildeAbbreviated(KokoroInstall.root)
                                          : KokoroInstall.downloadSummary)

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
