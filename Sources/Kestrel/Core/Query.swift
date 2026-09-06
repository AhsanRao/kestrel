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

    /// Timeouts per spec §8.5. Walkthroughs get longer: the model has to locate several controls
    /// in the image, which measured well over a plain answer in testing.
    var timeout: TimeInterval {
        switch mode {
        case .ask: return 120
        case .walkthrough: return 180
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
    /// The coordinate grid the model measured in. Vendors resize screenshots before the model sees
    /// them, and the model cannot know the original size, so it is asked to declare its own frame
    /// and Kestrel rescales from that. Absent means "assume per-mille".
    struct ImageSize: Codable, Equatable {
        var w: Double
        var h: Double

        static let perMille = ImageSize(w: 1000, h: 1000)
        var isUsable: Bool { w > 1 && h > 1 }
    }

    var goal: String
    var steps: [WalkthroughStep]
    var image: ImageSize?
    var needs_more: Bool?

    /// The space every `target` in `steps` is expressed in.
    var space: ImageSize {
        guard let image, image.isUsable else { return .perMille }
        return image
    }
}
