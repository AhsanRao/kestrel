import CoreGraphics
import Foundation

/// One thing on screen that the answer is talking about, and where it is.
struct Annotation: Equatable {
    /// Global AppKit points.
    var frame: CGRect
    /// The control's own label, shown next to the mark when there is more than one.
    var caption: String
    var shape: Shape

    enum Shape: Equatable { case circle, rect }
}

/// Pulls the "point at these" markers out of a spoken answer.
///
/// A voice assistant that says "click the button in the centre of the screen" has made the user do
/// the pointing. The answer is spoken as prose, and a single trailing line names the controls it
/// referred to, which Kestrel then circles on the real screen. Keeping the marker out of the prose
/// means the answer still reads and sounds like a sentence, and an older model that ignores the
/// convention simply gets no drawing rather than a broken one.
enum AnnotationParser {
    static let marker = "POINT:"

    struct Result: Equatable {
        /// The answer with the marker line removed — what is spoken and shown.
        var spoken: String
        /// Element numbers from the offered control list.
        var elements: [Int]
        /// Labels, for when the model named a control rather than numbering it.
        var labels: [String]

        var isEmpty: Bool { elements.isEmpty && labels.isEmpty }
    }

    /// True for a streamed sentence that is really the marker line, so it is never read out loud.
    static func isMarker(_ sentence: String) -> Bool {
        sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .hasPrefix(marker)
    }

    static func parse(_ raw: String) -> Result {
        var kept: [String] = []
        var elements: [Int] = []
        var labels: [String] = []

        for line in raw.components(separatedBy: .newlines) {
            guard isMarker(line) else { kept.append(line); continue }
            let body = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .dropFirst(marker.count)
            for token in body.components(separatedBy: ",") {
                let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”.·—-[]()"))
                guard !cleaned.isEmpty, cleaned.lowercased() != "none" else { continue }
                if let number = Int(cleaned) { elements.append(number) } else { labels.append(cleaned) }
            }
        }

        let spoken = kept.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(spoken: spoken, elements: Array(elements.prefix(maximumMarks)),
                      labels: Array(labels.prefix(maximumMarks)))
    }

    /// More than a few marks is a diagram, not a gesture; the screen stops being readable.
    static let maximumMarks = 4

    /// Turns the marker into things to draw, using the same control list the model chose from and,
    /// failing that, a match on the control's visible name.
    static func annotations(for result: Result,
                            elements: [AXElementScanner.Element]) -> [Annotation] {
        let byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [Annotation] = []
        var seen = Set<String>()

        func append(_ element: AXElementScanner.Element) {
            // Where it is now, not where it was when the app was scanned — that was before the
            // model was even asked, and anything that scrolled since has moved the control out
            // from under the mark. A control that can no longer be found is not drawn at all,
            // because a mark in the wrong place is worse than no mark.
            guard let frame = AXElementScanner.currentFrame(of: element)
                    ?? (AXElementScanner.isOnScreen(element.frame) ? element.frame : nil) else { return }
            let key = "\(Int(frame.minX)),\(Int(frame.minY))"
            guard seen.insert(key).inserted else { return }
            // A wide control reads better with a box round it; a small square one with a circle.
            let ratio = frame.width / max(frame.height, 1)
            found.append(Annotation(frame: frame, caption: element.label,
                                    shape: ratio > 2.2 ? .rect : .circle))
        }

        for id in result.elements {
            if let element = byID[id] { append(element) }
        }
        for label in result.labels {
            let step = WalkthroughStep(n: 0, instruction: label, label: label)
            guard let frame = WalkthroughResolver.relocate(step, in: elements),
                  let element = elements.first(where: { $0.frame == frame }) else { continue }
            append(element)
        }
        return Array(found.prefix(maximumMarks))
    }
}
