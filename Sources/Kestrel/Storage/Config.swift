import Foundation

/// `~/.kestrel/config.json`. Every key is optional; missing keys fall back to `Config.defaults`,
/// so a hand-written file with a single line is valid.
struct Config: Codable, Equatable {
    var backend: BackendKind
    var claudeModel: String?
    var codexModel: String?
    var autoRoute: Bool
    var allowMCPServers: Bool

    var whisperBinary: String
    var whisperModel: String
    var language: String
    var transcriptionHint: String?

    var speakAnswers: Bool
    var sounds: Bool
    var voiceIdentifier: String?

    var cleanupDictation: Bool
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

    var apiKeys: APIKeys

    static let defaults = Config(
        backend: .claude,
        claudeModel: nil,
        codexModel: nil,
        autoRoute: false,
        allowMCPServers: false,
        whisperBinary: Paths.defaultWhisperBinary,
        whisperModel: Paths.defaultWhisperModel.path,
        language: "auto",
        transcriptionHint: nil,
        speakAnswers: true,
        sounds: true,
        voiceIdentifier: nil,
        cleanupDictation: true,
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
        apiKeys: APIKeys(anthropic: nil, openai: nil)
    )

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
        /// Dictation stays a keyed hotkey: it is a tap, not a hold, and ⌃⌘ is the quietest pair on
        /// macOS — the system claims only ⌃⌘Space, ⌃⌘D, ⌃⌘F and ⌃⌘Q, and K is free in it.
        static let defaults = Hotkeys(
            ask: HotkeyBinding(keyCode: nil, modifiers: ["control", "option"]),       // ⌃⌥ held
            dictate: HotkeyBinding(keyCode: 40, modifiers: ["control", "command"])    // ⌃⌘K
        )
    }

    enum InjectMode: String, Codable, CaseIterable { case paste, type }

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

    // MARK: - Tolerant decoding

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
        whisperBinary = v(.whisperBinary, d.whisperBinary)
        whisperModel = v(.whisperModel, d.whisperModel)
        language = v(.language, d.language)
        transcriptionHint = opt(.transcriptionHint)
        speakAnswers = v(.speakAnswers, d.speakAnswers)
        sounds = v(.sounds, d.sounds)
        voiceIdentifier = opt(.voiceIdentifier)
        cleanupDictation = v(.cleanupDictation, d.cleanupDictation)
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
        apiKeys = v(.apiKeys, d.apiKeys)
        clamp()
    }

    init(backend: BackendKind, claudeModel: String?, codexModel: String?, autoRoute: Bool,
         allowMCPServers: Bool,
         whisperBinary: String, whisperModel: String, language: String, transcriptionHint: String?,
         speakAnswers: Bool, sounds: Bool,
         voiceIdentifier: String?,
         cleanupDictation: Bool, injectMode: InjectMode,
         hotkeys: Hotkeys, panelAutoHideSeconds: Int, followUpSeconds: Int,
         screenshotMaxEdge: Int, captureMode: CaptureMode,
         launchAtLogin: Bool,
         answerAnnotations: Bool, spatialContext: Bool, onboardingCompleted: Bool, apiKeys: APIKeys) {
        self.backend = backend; self.claudeModel = claudeModel; self.codexModel = codexModel
        self.autoRoute = autoRoute; self.allowMCPServers = allowMCPServers; self.whisperBinary = whisperBinary; self.whisperModel = whisperModel
        self.language = language; self.transcriptionHint = transcriptionHint
        self.speakAnswers = speakAnswers; self.sounds = sounds
        self.voiceIdentifier = voiceIdentifier
        self.cleanupDictation = cleanupDictation; self.injectMode = injectMode
        self.hotkeys = hotkeys; self.panelAutoHideSeconds = panelAutoHideSeconds
        self.followUpSeconds = followUpSeconds
        self.screenshotMaxEdge = screenshotMaxEdge; self.captureMode = captureMode
        self.launchAtLogin = launchAtLogin
        self.answerAnnotations = answerAnnotations
        self.spatialContext = spatialContext
        self.onboardingCompleted = onboardingCompleted
        self.apiKeys = apiKeys
        clamp()
    }

    /// Keeps hand-edited nonsense from reaching AVSpeechSynthesizer or the screenshot scaler.
    private mutating func clamp() {
        panelAutoHideSeconds = min(max(panelAutoHideSeconds, 2), 600)
        followUpSeconds = min(max(followUpSeconds, 0), 900)
        screenshotMaxEdge = min(max(screenshotMaxEdge, 512), 4096)
    }
}
