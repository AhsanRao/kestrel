import Foundation

/// `~/.kestrel/config.json`. Every key is optional; missing keys fall back to `Config.defaults`,
/// so a hand-written file with a single line is valid.
struct Config: Codable, Equatable {
    var backend: BackendKind
    var claudeModel: String?
    var codexModel: String?
    var autoRoute: Bool
    var allowMCPServers: Bool

    var transcriptionEngine: TranscriptionEngine
    var whisperBinary: String
    var whisperModel: String
    var transcriptionHint: String?

    var speakAnswers: Bool
    var sounds: Bool
    var voiceEngine: VoiceEngine
    var voiceIdentifier: String?
    var kokoroVoice: String

    var cleanupDictation: Bool
    /// How long a pause ends a live dictation. 0 leaves it running until the hotkey is pressed again.
    var dictationSilenceSeconds: Double
    var injectMode: InjectMode

    var hotkeys: Hotkeys
    var panelAutoHideSeconds: Int
    var followUpSeconds: Int
    var screenshotMaxEdge: Int
    var captureMode: CaptureMode
    var launchAtLogin: Bool
    /// Circle and point at what a spoken answer refers to, instead of describing where it is.
    var answerAnnotations: Bool
    var spatialContext: Bool
    var onboardingCompleted: Bool

    /// Let the model act on the Mac — open apps, run scripts, click and type — not just answer.
    var agentTools: Bool
    /// Tool calls one question may make before Kestrel says it couldn't finish.
    var maxAgentSteps: Int
    /// Executables `run_shell` may start; anything else is refused.
    var shellAllowlist: [String]
    /// Words that make an action worth checking with the user first.
    var sensitivePatterns: [String]

    var apiKeys: APIKeys

    static let defaults = Config(
        backend: .claude,
        claudeModel: nil,
        codexModel: nil,
        autoRoute: false,
        allowMCPServers: false,
        transcriptionEngine: .apple,
        whisperBinary: Paths.defaultWhisperBinary,
        whisperModel: Paths.defaultWhisperModel.path,
        transcriptionHint: nil,
        speakAnswers: true,
        sounds: true,
        voiceEngine: .kokoro,
        voiceIdentifier: nil,
        kokoroVoice: KokoroVoice.default.id,
        cleanupDictation: true,
        dictationSilenceSeconds: 2.5,
        injectMode: .paste,
        hotkeys: .defaults,
        panelAutoHideSeconds: 20,
        followUpSeconds: 90,
        screenshotMaxEdge: 2048,
        captureMode: .window,
        launchAtLogin: false,
        answerAnnotations: true,
        spatialContext: true,
        onboardingCompleted: false,
        agentTools: true,
        maxAgentSteps: 10,
        shellAllowlist: ActionPolicy.defaultShellAllowlist,
        sensitivePatterns: ActionPolicy.defaultSensitivePatterns,
        apiKeys: APIKeys(anthropic: nil, openai: nil)
    )

    var actionPolicy: ActionPolicy {
        ActionPolicy(sensitivePatterns: sensitivePatterns, shellAllowlist: shellAllowlist)
    }

    // Expanded, absolute paths for the two whisper settings, which may be written as `~/...`.
    var whisperBinaryURL: URL { URL(fileURLWithPath: (whisperBinary as NSString).expandingTildeInPath) }
    var whisperModelURL: URL { URL(fileURLWithPath: (whisperModel as NSString).expandingTildeInPath) }

    struct APIKeys: Codable, Equatable {
        var anthropic: String?
        var openai: String?
    }

    struct Hotkeys: Codable, Equatable {
        var ask: HotkeyBinding
        var dictate: HotkeyBinding

        /// Asking is held down for as long as you are talking, so it wants to be a chord rather
        /// than a chord *plus* a letter — ⌃⌥ is one shape the hand already makes, and holding it is
        /// the whole gesture. macOS claims nothing on ⌃⌥ alone, and because there is no letter it
        /// cannot collide with an app's shortcut either.
        ///
        /// The cost is that Carbon cannot register a bare chord, so it is watched through an event
        /// tap and therefore needs Accessibility — which dictation already required. It also waits
        /// out a short dwell before firing, so that ⌃⌥ on its way to some other shortcut is not
        /// mistaken for a question (see `ModifierChordDetector`).
        ///
        /// Dictation stays a keyed hotkey: it is a tap, not a hold, and a bare chord cannot be
        /// tapped twice in a row without the second tap looking like the first still being held.
        ///
        /// Its modifiers must not be the ask chord's. ⌃⌥D was tried and both hotkeys fired from the
        /// one gesture: holding ⌃⌥ on the way to D is a question starting, and the D then aborted
        /// it. ⌃⌘ shares nothing with ⌃⌥, so the two cannot be confused for each other.
        ///
        /// The letter is K rather than D because macOS reserves four ⌃⌘ combinations — Space, D, F
        /// and Q — and ⌃⌘D is Look Up. Taking it would mean dictation and the dictionary fighting
        /// over the same press, in whichever app happened to be in front.
        static let defaults = Hotkeys(
            ask: HotkeyBinding(keyCode: nil, modifiers: ["control", "option"]),      // ⌃⌥ held
            dictate: HotkeyBinding(keyCode: 40, modifiers: ["control", "command"])   // ⌃⌘K
        )
    }

    enum InjectMode: String, Codable, CaseIterable { case paste, type }

    /// Which local engine turns audio into text. Kestrel is English-only either way: Apple's
    /// engine has no Urdu locale, and Roman Urdu is spoken into an English transcript anyway.
    enum TranscriptionEngine: String, Codable, CaseIterable {
        /// macOS 26+ `SpeechAnalyzer`, the system dictation engine. Falls back to whisper below 26.
        case apple
        case whisper

        var title: String {
            switch self {
            case .apple: return "Apple (macOS 26+)"
            case .whisper: return "whisper.cpp"
            }
        }
    }

    /// Which engine reads answers aloud. Kokoro sounds markedly better; the macOS voices need
    /// nothing installed, and are the fallback when the download is skipped.
    enum VoiceEngine: String, Codable, CaseIterable {
        case kokoro
        case system

        var title: String {
            switch self {
            case .kokoro: return "Kokoro (neural, on this Mac)"
            case .system: return "macOS built-in voices"
            }
        }
    }

    /// What a question is asked *about*. Capturing just the frontmost window spends every pixel on
    /// the thing the user means, instead of shrinking a whole 5K desktop until the labels blur.
    enum CaptureMode: String, Codable, CaseIterable {
        case window
        case display

        var title: String {
            switch self {
            case .window: return "Front window"
            case .display: return "Whole screen"
            }
        }
    }


    /// Keeps hand-edited nonsense from reaching AVSpeechSynthesizer or the screenshot scaler.
    private mutating func clamp() {
        panelAutoHideSeconds = min(max(panelAutoHideSeconds, 2), 600)
        followUpSeconds = min(max(followUpSeconds, 0), 900)
        screenshotMaxEdge = min(max(screenshotMaxEdge, 512), 4096)
        maxAgentSteps = min(max(maxAgentSteps, 1), 50)
        // Under a second, an ordinary pause mid-sentence would end the dictation.
        dictationSilenceSeconds = dictationSilenceSeconds <= 0 ? 0 : min(max(dictationSilenceSeconds, 1), 30)
    }
}


/// Tolerant decoding: every key optional, anything unreadable falls back to `defaults`.
///
/// In an extension, not the struct body — a struct that declares an `init` of its own loses the
/// synthesised memberwise one, and hand-writing that twin is twenty-five parameters of nothing.
extension Config {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
        }
        func opt<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        backend = v(.backend, d.backend)
        claudeModel = opt(.claudeModel)
        codexModel = opt(.codexModel)
        autoRoute = v(.autoRoute, d.autoRoute)
        allowMCPServers = v(.allowMCPServers, d.allowMCPServers)
        transcriptionEngine = v(.transcriptionEngine, d.transcriptionEngine)
        whisperBinary = v(.whisperBinary, d.whisperBinary)
        whisperModel = v(.whisperModel, d.whisperModel)
        transcriptionHint = opt(.transcriptionHint)
        speakAnswers = v(.speakAnswers, d.speakAnswers)
        sounds = v(.sounds, d.sounds)
        voiceEngine = v(.voiceEngine, d.voiceEngine)
        voiceIdentifier = opt(.voiceIdentifier)
        kokoroVoice = v(.kokoroVoice, d.kokoroVoice)
        cleanupDictation = v(.cleanupDictation, d.cleanupDictation)
        dictationSilenceSeconds = v(.dictationSilenceSeconds, d.dictationSilenceSeconds)
        injectMode = v(.injectMode, d.injectMode)
        hotkeys = v(.hotkeys, d.hotkeys)
        panelAutoHideSeconds = v(.panelAutoHideSeconds, d.panelAutoHideSeconds)
        followUpSeconds = v(.followUpSeconds, d.followUpSeconds)
        screenshotMaxEdge = v(.screenshotMaxEdge, d.screenshotMaxEdge)
        captureMode = v(.captureMode, d.captureMode)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        answerAnnotations = v(.answerAnnotations, d.answerAnnotations)
        spatialContext = v(.spatialContext, d.spatialContext)
        onboardingCompleted = v(.onboardingCompleted, d.onboardingCompleted)
        agentTools = v(.agentTools, d.agentTools)
        maxAgentSteps = v(.maxAgentSteps, d.maxAgentSteps)
        shellAllowlist = v(.shellAllowlist, d.shellAllowlist)
        sensitivePatterns = v(.sensitivePatterns, d.sensitivePatterns)
        apiKeys = v(.apiKeys, d.apiKeys)
        clamp()
    }
}
