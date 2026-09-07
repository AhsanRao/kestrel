import CoreGraphics
import Foundation

/// One thing on screen that the answer is talking about, and where it is.
struct Annotation: Equatable {
    /// Global AppKit points.
    var frame: CGRect
    /// The thing's own label, shown beside the mark.
    var caption: String
    var shape: Shape
    /// A block of content rather than a control. Drawn as a tinted area with its name attached,
    /// because a hairline circle round half a page reads as a mistake.
    var isRegion: Bool

    enum Shape: Equatable { case circle, rect }

    init(frame: CGRect, caption: String, shape: Shape, isRegion: Bool = false) {
        self.frame = frame
        self.caption = caption
        self.shape = shape
        self.isRegion = isRegion
    }

    /// Long paragraph text makes a useless badge; the first few words do not.
    static func shorten(_ label: String) -> String {
        let clean = label.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 38 else { return clean }
        return String(clean.prefix(36)) + "…"
    }
}

/// Pulls the "point at these" markers out of a spoken answer.
///
/// A voice assistant that says "click the button in the centre of the screen" has made the user do
/// the pointing. The answer is spoken as prose, and a single trailing line names the controls it
/// referred to, which Kestrel then circles on the real screen. Keeping the marker out of the prose
/// means the answer still reads and sounds like a sentence, and an older model that ignores the
/// convention simply gets no drawing rather than a broken one.
enum AnnotationParser {
    static let marker = "MARK:"
    /// What the marker used to be called. Still accepted, because a model that has seen the older
    /// wording should not silently stop pointing at anything.
    static let legacyMarker = "POINT:"

    struct Result: Equatable {
        /// The answer with the marker line removed — what is spoken and shown.
        var spoken: String
        /// Element numbers from the offered control list.
        var elements: [Int]
        /// Labels, for when the model named a control rather than numbering it.
        var labels: [String]
        /// The model wrote a marker line, even if it named nothing in it. "MARK: none" is a
        /// decision — that the answer is about nothing on screen — and guessing over the top of it
        /// would be Kestrel overruling the only thing that actually read the question.
        var declaredNothing = false

        var isEmpty: Bool { elements.isEmpty && labels.isEmpty }
    }

    /// True for a streamed sentence that is really the marker line, so it is never read out loud.
    static func isMarker(_ sentence: String) -> Bool {
        let head = sentence.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return head.hasPrefix(marker) || head.hasPrefix(legacyMarker)
    }

    static func parse(_ raw: String) -> Result {
        var kept: [String] = []
        var elements: [Int] = []
        var labels: [String] = []
        var sawMarker = false

        for line in raw.components(separatedBy: .newlines) {
            guard isMarker(line) else { kept.append(line); continue }
            sawMarker = true
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = trimmed.uppercased().hasPrefix(marker) ? marker.count : legacyMarker.count
            let body = trimmed.dropFirst(head)
            for token in body.components(separatedBy: ",") {
                let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”.·—-[]()"))
                guard !cleaned.isEmpty, cleaned.lowercased() != "none" else { continue }
                if let number = Int(cleaned) { elements.append(number) } else { labels.append(cleaned) }
            }
        }

        let spoken = kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Result(spoken: spoken, elements: Array(elements.prefix(maximumMarks)),
                            labels: Array(labels.prefix(maximumMarks)))
        result.declaredNothing = sawMarker && result.isEmpty
        return result
    }

    /// The ceiling, not the target: a pointed question still gets one or two marks. Six is what a
    /// question about the whole screen needs — "what's happening here" over an editor with a
    /// terminal, a source control pane and a graph in it has five or six real areas, and marking
    /// two of them while the answer names five leaves the user hunting for the rest.
    static let maximumMarks = 6

    /// Turns the marker into things to draw, against the numbered list the model chose from.
    ///
    /// When the model named nothing, the answer is searched for the labels of things on screen and
    /// the best match is marked anyway. That fallback is the point: an assistant that says "tighten
    /// the card spacing" and highlights nothing has handed the user a puzzle, and the whole promise
    /// here is that it points at what it is talking about.
    static func annotations(for result: Result, targets: [ScreenTarget]) -> [Annotation] {
        let byID = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [Annotation] = []
        var seen = Set<String>()

        func append(_ target: ScreenTarget) {
            // Where it is now, not where it was when the screen was read — that was before the
            // model was even asked, and anything that scrolled since has moved it out from under
            // the mark. Something that can no longer be found is not drawn at all: a mark in the
            // wrong place is worse than no mark.
            guard let frame = target.currentFrame
                    ?? (AXElementScanner.isOnScreen(target.frame) ? target.frame : nil) else { return }
            // The whole rect, not just its corner: a cell and the text inside it share a top-left
            // corner all over an Accessibility tree, and keying on the corner threw the second mark
            // away — leaving one mark where the answer had named two things.
            let key = "\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
            guard seen.insert(key).inserted else { return }
            found.append(Annotation(frame: frame, caption: Annotation.shorten(target.label),
                                    shape: target.preferredShape, isRegion: target.kind == .region))
        }

        for id in result.elements {
            if let target = byID[id] { append(target) }
        }
        for label in result.labels {
            if let target = match(label, in: targets) { append(target) }
        }
        return Array(found.prefix(maximumMarks))
    }

    /// The thing on screen an answer is most likely talking about, when the model named nothing.
    ///
    /// Quoted phrases first, because a model that writes "click **Share**" has already told you
    /// what it means. Then the longest label that appears in the answer verbatim — longest because
    /// "Save" matches half a screen and "Save as PDF" matches one thing.
    static func inferred(from answer: String, targets: [ScreenTarget]) -> [Annotation] {
        let lowered = answer.lowercased()
        var candidates: [ScreenTarget] = []

        for phrase in quotedPhrases(in: answer) {
            if let target = match(phrase, in: targets) { candidates.append(target) }
        }
        if candidates.isEmpty {
            let mentioned = targets
                .filter { $0.label.count >= 4 && AnnotationParser.containsWords(lowered, $0.label) }
                .sorted { $0.label.count > $1.label.count }
            if let best = mentioned.first { candidates.append(best) }
        }
        guard !candidates.isEmpty else { return [] }
        var result = Result(spoken: answer, elements: candidates.map(\.id), labels: [])
        result.elements = Array(result.elements.prefix(2))
        return annotations(for: result, targets: targets)
    }

    /// "…" and "…" — what the answer put in quotes or emphasis.
    static func quotedPhrases(in text: String) -> [String] {
        var phrases: [String] = []
        for pattern in ["\"([^\"]{2,40})\"", "\u{201C}([^\u{201D}]{2,40})\u{201D}",
                        "\\*\\*([^*]{2,40})\\*\\*"] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges > 1, let found = Range(match.range(at: 1), in: text)
                else { continue }
                phrases.append(String(text[found]))
            }
        }
        return phrases
    }
}
