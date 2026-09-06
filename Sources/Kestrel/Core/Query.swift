import Foundation

enum QueryMode: String { case ask, dictationCleanup, walkthrough }

/// What a backend is asked to do. Screenshots are passed as file paths: both CLIs read images off
/// disk, and this keeps large base64 payloads out of argv.
struct Query {
    var text: String
    var screenshot: URL?
    var focusCrop: URL?
    var mode: QueryMode
    var maxTokensHint: Int?

    init(text: String, screenshot: URL? = nil, focusCrop: URL? = nil,
         mode: QueryMode = .ask, maxTokensHint: Int? = nil) {
        self.text = text
        self.screenshot = screenshot
        self.focusCrop = focusCrop
        self.mode = mode
        self.maxTokensHint = maxTokensHint
    }

    /// Timeouts per spec §8.5.
    var timeout: TimeInterval {
        switch mode {
        case .ask, .walkthrough: return 120
        case .dictationCleanup: return 30
        }
    }
}

struct Answer {
    var text: String
    var raw: String
    var durationMs: Int
    var steps: [WalkthroughStep]?

    init(text: String, raw: String, durationMs: Int, steps: [WalkthroughStep]? = nil) {
        self.text = text
        self.raw = raw
        self.durationMs = durationMs
        self.steps = steps
    }
}

/// v2 walkthrough payload (spec §8.15). Decoded here so the schema lives with the other models.
struct WalkthroughStep: Codable, Equatable {
    struct Target: Codable, Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
    }

    var n: Int
    var instruction: String
    var target: Target
    var shape: String
}

struct Walkthrough: Codable, Equatable {
    var goal: String
    var steps: [WalkthroughStep]
    var needs_more: Bool?
}
