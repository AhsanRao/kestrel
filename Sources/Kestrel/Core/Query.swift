import Foundation

enum QueryMode: String { case ask, dictationCleanup }

/// What a backend is asked to do. Screenshots are passed as file paths: both CLIs read images off
/// disk, and this keeps large base64 payloads out of argv.
struct Query {
    var text: String
    var screenshot: URL?
    var focusCrop: URL?
    var mode: QueryMode
    var maxTokensHint: Int?
    /// Everything on screen the answer may point at — controls and content regions in one numbered
    /// list, so the model can name a card as easily as a button.
    var targets: [ScreenTarget]
    /// What the screen actually says, in reading order, and where it came from.
    var screenText: String?
    var pageURL: String?
    var document: String?
    /// Earlier turns, when this question continues a warm conversation.
    var history: [Conversation.Exchange]
    /// Per-app notes from `~/.kestrel/skills`, when the frontmost app has any.
    var skills: String?
    /// What else is open, when the question is about the desktop rather than the screen.
    var desktop: String?
    /// Where the CLI should run. Agent tasks get their own project folder; everything else runs
    /// in `~/.kestrel`.
    var workingDirectory: URL?
    /// Offer the six system tools (spec §8.18). The socket they are served on is `Paths.mcpSocket`.
    var tools: Bool
    /// The step budget, quoted to the model so it can plan inside it.
    var maximumSteps: Int

    init(text: String, screenshot: URL? = nil, focusCrop: URL? = nil,
         mode: QueryMode = .ask, maxTokensHint: Int? = nil,
         targets: [ScreenTarget] = [],
         screenText: String? = nil, pageURL: String? = nil, document: String? = nil,
         history: [Conversation.Exchange] = [], skills: String? = nil,
         desktop: String? = nil, workingDirectory: URL? = nil,
         tools: Bool = false, maximumSteps: Int = 10) {
        self.text = text
        self.screenshot = screenshot
        self.focusCrop = focusCrop
        self.mode = mode
        self.maxTokensHint = maxTokensHint
        self.targets = targets
        self.screenText = screenText
        self.pageURL = pageURL
        self.document = document
        self.history = history
        self.skills = skills
        self.desktop = desktop
        self.workingDirectory = workingDirectory
        self.tools = tools
        self.maximumSteps = maximumSteps
    }

    /// The page or document in front of the user, named for the model.
    var location: String? {
        var lines: [String] = []
        if let pageURL, !pageURL.isEmpty { lines.append("The page on screen is \(pageURL)") }
        if let document, !document.isEmpty {
            let name = URL(string: document)?.lastPathComponent ?? document
            lines.append("The open document is \(name.removingPercentEncoding ?? name)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Timeouts per spec §8.5. A question that may act takes as long as its steps do — a Safari
    /// cold start and a confirmation the user has to hear are both on this clock.
    var timeout: TimeInterval {
        switch mode {
        case .ask: return tools ? 300 : 75
        case .dictationCleanup: return 20
        }
    }
}

struct Answer {
    var text: String
    var raw: String
    var durationMs: Int

    init(text: String, raw: String, durationMs: Int) {
        self.text = text
        self.raw = raw
        self.durationMs = durationMs
    }
}
