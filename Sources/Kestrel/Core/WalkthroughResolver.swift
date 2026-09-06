import CoreGraphics
import Foundation

/// Works out where each step of a walkthrough actually points, in global AppKit points.
///
/// Three sources, in order of trust: a control the model picked from the Accessibility list, whose
/// frame macOS reported exactly; a control matched by name in a fresh scan taken once the user has
/// arrived at that step; and — only when there was no list at all — the coordinates the model
/// estimated from the screenshot, which are approximate.
///
/// A step that none of those can place is **kept, not dropped**. Half a route is worse than a route
/// with one unmarked stop on it: the instruction still names the control, and the step is usually
/// somewhere that does not exist yet, like an item in a menu that has not been opened.
enum WalkthroughResolver {
    struct Resolved {
        var step: WalkthroughStep
        /// Nil when the control is not on screen yet; the step is shown by name instead.
        var frame: CGRect?
        /// True when the frame came from Accessibility rather than from the model's estimate.
        var isExact: Bool
    }

    static func resolve(_ walkthrough: Walkthrough, elements: [AXElementScanner.Element],
                        capture: ScreenCapture?) -> [Resolved] {
        let byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let space = walkthrough.space

        return walkthrough.steps.map { step in
            if let id = step.element, let element = byID[id] {
                return Resolved(step: step, frame: element.frame, isExact: true)
            }
            if let frame = relocate(step, in: elements) {
                return Resolved(step: step, frame: frame, isExact: true)
            }
            if let capture, let target = step.target, ScreenCapture.isPlausible(target, in: space) {
                return Resolved(step: step, frame: capture.screenRect(for: target, in: space), isExact: false)
            }
            return Resolved(step: step, frame: nil, isExact: false)
        }
    }

    /// Finds the step's control by name in a scan taken *now*.
    ///
    /// This is what makes a multi-step route work at all. The frames handed back by the first scan
    /// describe the screen as it was before the user clicked anything; one click into a menu and
    /// they describe nothing. Matching the step's own label against a fresh scan re-points the ring
    /// at wherever the control has since appeared.
    static func relocate(_ step: WalkthroughStep, in elements: [AXElementScanner.Element]) -> CGRect? {
        let wanted = normalize(step.label ?? "")
        guard wanted.count >= 2 else { return nil }
        var fallback: CGRect?
        for element in elements {
            let candidate = normalize(element.label)
            guard !candidate.isEmpty else { continue }
            if candidate == wanted { return element.frame }
            // "Export…" against "Export as PDF…", or the other way round: good enough to point at,
            // but only if nothing matches exactly.
            if fallback == nil, candidate.contains(wanted) || wanted.contains(candidate) {
                fallback = element.frame
            }
        }
        return fallback
    }

    /// Case, padding and the trailing ellipsis menu items wear are not part of a control's identity.
    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
