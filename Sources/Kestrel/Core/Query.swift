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
    /// Clickable controls read from the Accessibility tree, offered to the model to choose from.
    var elements: [AXElementScanner.Element]
    /// Earlier turns, when this question continues a warm conversation.
    var history: [Conversation.Exchange]

    init(text: String, screenshot: URL? = nil, focusCrop: URL? = nil,
         mode: QueryMode = .ask, maxTokensHint: Int? = nil,
         elements: [AXElementScanner.Element] = [],
         history: [Conversation.Exchange] = []) {
        self.text = text
        self.screenshot = screenshot
        self.focusCrop = focusCrop
        self.mode = mode
        self.maxTokensHint = maxTokensHint
        self.elements = elements
        self.history = history
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

        static let zero = Target(x: 0, y: 0, w: 0, h: 0)
    }

    var n: Int
    var instruction: String
    /// The number of a control from the list Kestrel offered, when the Accessibility tree could be
    /// read. This is the accurate path: macOS reports the exact frame, so nothing is estimated.
    var element: Int?
    /// Fallback for apps with no usable Accessibility tree: coordinates in the model's own grid.
    var target: Target?
    var shape: String

    init(n: Int, instruction: String, element: Int? = nil, target: Target? = nil, shape: String = "rect") {
        self.n = n
        self.instruction = instruction
        self.element = element
        self.target = target
        self.shape = shape
    }

    /// Tolerant decoding: element-mode answers carry neither `shape` nor, sometimes, `n`, and a
    /// missing optional field must never throw away an otherwise good step.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        n = ((try? container.decodeIfPresent(Int.self, forKey: .n)) ?? nil) ?? 0
        instruction = ((try? container.decodeIfPresent(String.self, forKey: .instruction)) ?? nil) ?? ""
        element = (try? container.decodeIfPresent(Int.self, forKey: .element)) ?? nil
        target = (try? container.decodeIfPresent(Target.self, forKey: .target)) ?? nil
        shape = ((try? container.decodeIfPresent(String.self, forKey: .shape)) ?? nil) ?? "rect"
    }
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

    init(goal: String, steps: [WalkthroughStep], image: ImageSize? = nil, needs_more: Bool? = nil) {
        self.goal = goal
        self.steps = steps
        self.image = image
        self.needs_more = needs_more
    }

    /// The space every `target` in `steps` is expressed in.
    var space: ImageSize {
        guard let image, image.isUsable else { return .perMille }
        return image
    }
}
