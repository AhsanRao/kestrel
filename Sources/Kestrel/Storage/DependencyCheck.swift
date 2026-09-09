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
            case .speech: return "Speech to text"
            case .whisperBinary: return "whisper-cli"
            case .whisperModel: return "Speech model"
            case .voice: return "Kokoro voice"
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
            case .speech: return "Turns your voice into text on this Mac. Nothing is uploaded."
            case .whisperBinary: return "The engine Kestrel was told to use instead of Apple's."
            case .whisperModel: return "The speech model whisper reads. About 148 MB."
            case .voice: return "A neural voice that reads answers aloud, better than the ones macOS ships. Skip it and the best system voice is used instead."
            case .claude: return "Answers your questions using your Claude subscription."
            case .codex: return "Optional second backend, using your ChatGPT subscription."
            }
        }

        /// False for things Kestrel can run without.
        ///
        /// Accessibility depends on how the ask hotkey is bound. A bare modifier chord — the
        /// default ⌃⌥ — cannot be registered with Carbon and is watched through an event tap, so
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

        /// A granted permission only takes effect after a relaunch.
        var needsRelaunch: Bool { self == .screenRecording }
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
                        detail: granted ? "Allowed" : "System Settings ▸ Privacy & Security ▸ Microphone")

        case .screenRecording:
            let granted = CGPreflightScreenCaptureAccess()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "Allowed" : "System Settings ▸ Privacy & Security ▸ Screen Recording")

        case .accessibility:
            let granted = AXIsProcessTrusted()
            return Item(requirement: requirement, ok: granted,
                        detail: granted ? "Allowed" : "Needed for the ask hotkey and dictation")

        case .speech:
            if config.effectiveTranscriptionEngine == .apple {
                return Item(requirement: requirement, ok: true, detail: "Apple, built in — nothing to install")
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
                return Item(requirement: requirement, ok: true, detail: "Using the macOS voices")
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
