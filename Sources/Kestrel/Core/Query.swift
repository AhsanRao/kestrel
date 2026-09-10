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

    init(text: String, screenshot: URL? = nil, focusCrop: URL? = nil,
         mode: QueryMode = .ask, maxTokensHint: Int? = nil,
         targets: [ScreenTarget] = [],
         screenText: String? = nil, pageURL: String? = nil, document: String? = nil,
         history: [Conversation.Exchange] = [], skills: String? = nil,
         desktop: String? = nil, workingDirectory: URL? = nil) {
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

    /// Timeouts per spec §8.5.
    var timeout: TimeInterval {
        switch mode {
        case .ask: return 75
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
