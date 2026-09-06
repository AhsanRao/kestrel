import Foundation

/// `~/.kestrel/config.json`. Every key is optional; missing keys fall back to `Config.defaults`,
/// so a hand-written file with a single line is valid.
struct Config: Codable, Equatable {
    var backend: BackendKind
    var claudeModel: String?
    var codexModel: String?
    var autoRoute: Bool

    var whisperBinary: String
    var whisperModel: String
    var language: String

    var speakAnswers: Bool
    var voiceIdentifier: String?
    var voiceRate: Double

    var cleanupDictation: Bool
    var injectMode: InjectMode

    var hotkeys: Hotkeys
    var panelAutoHideSeconds: Int
    var screenshotMaxEdge: Int
    var launchAtLogin: Bool

    var apiKeys: APIKeys

    static let defaults = Config(
        backend: .claude,
        claudeModel: nil,
        codexModel: nil,
        autoRoute: false,
        whisperBinary: Paths.defaultWhisperBinary,
        whisperModel: Paths.defaultWhisperModel.path,
        language: "auto",
        speakAnswers: true,
        voiceIdentifier: nil,
        voiceRate: 0.52,
        cleanupDictation: true,
        injectMode: .paste,
        hotkeys: .defaults,
        panelAutoHideSeconds: 20,
        screenshotMaxEdge: 2048,
        launchAtLogin: false,
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

        static let defaults = Hotkeys(
            ask: HotkeyBinding(keyCode: 49, modifiers: ["control", "option"]),      // ⌃⌥Space
            dictate: HotkeyBinding(keyCode: 2, modifiers: ["control", "option"])    // ⌃⌥D
        )
    }

    enum InjectMode: String, Codable, CaseIterable { case paste, type }

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
        whisperBinary = v(.whisperBinary, d.whisperBinary)
        whisperModel = v(.whisperModel, d.whisperModel)
        language = v(.language, d.language)
        speakAnswers = v(.speakAnswers, d.speakAnswers)
        voiceIdentifier = opt(.voiceIdentifier)
        voiceRate = v(.voiceRate, d.voiceRate)
        cleanupDictation = v(.cleanupDictation, d.cleanupDictation)
        injectMode = v(.injectMode, d.injectMode)
        hotkeys = v(.hotkeys, d.hotkeys)
        panelAutoHideSeconds = v(.panelAutoHideSeconds, d.panelAutoHideSeconds)
        screenshotMaxEdge = v(.screenshotMaxEdge, d.screenshotMaxEdge)
        launchAtLogin = v(.launchAtLogin, d.launchAtLogin)
        apiKeys = v(.apiKeys, d.apiKeys)
        clamp()
    }

    init(backend: BackendKind, claudeModel: String?, codexModel: String?, autoRoute: Bool,
         whisperBinary: String, whisperModel: String, language: String, speakAnswers: Bool,
         voiceIdentifier: String?, voiceRate: Double, cleanupDictation: Bool, injectMode: InjectMode,
         hotkeys: Hotkeys, panelAutoHideSeconds: Int, screenshotMaxEdge: Int, launchAtLogin: Bool,
         apiKeys: APIKeys) {
        self.backend = backend; self.claudeModel = claudeModel; self.codexModel = codexModel
        self.autoRoute = autoRoute; self.whisperBinary = whisperBinary; self.whisperModel = whisperModel
        self.language = language; self.speakAnswers = speakAnswers; self.voiceIdentifier = voiceIdentifier
        self.voiceRate = voiceRate; self.cleanupDictation = cleanupDictation; self.injectMode = injectMode
        self.hotkeys = hotkeys; self.panelAutoHideSeconds = panelAutoHideSeconds
        self.screenshotMaxEdge = screenshotMaxEdge; self.launchAtLogin = launchAtLogin; self.apiKeys = apiKeys
        clamp()
    }

    /// Keeps hand-edited nonsense from reaching AVSpeechSynthesizer or the screenshot scaler.
    private mutating func clamp() {
        voiceRate = min(max(voiceRate, 0.3), 0.7)
        panelAutoHideSeconds = min(max(panelAutoHideSeconds, 2), 600)
        screenshotMaxEdge = min(max(screenshotMaxEdge, 512), 4096)
    }
}
