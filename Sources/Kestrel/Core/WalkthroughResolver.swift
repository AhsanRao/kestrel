import CoreGraphics
import Foundation

/// Works out where each step of a walkthrough actually points, in global AppKit points.
///
/// Two sources, in order of trust: a control the model picked from the Accessibility list, whose
/// frame macOS reported exactly, and — only when there was no such list — the coordinates the model
/// estimated from the screenshot, which are approximate.
enum WalkthroughResolver {
    struct Resolved {
        var step: WalkthroughStep
        var frame: CGRect
        /// True when the frame came from Accessibility rather than from the model's estimate.
        var isExact: Bool
    }

    static func resolve(_ walkthrough: Walkthrough, elements: [AXElementScanner.Element],
                        capture: ScreenCapture) -> [Resolved] {
        let byID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        let space = walkthrough.space

        return walkthrough.steps.compactMap { step in
            if let id = step.element, let element = byID[id] {
                return Resolved(step: step, frame: element.frame, isExact: true)
            }
            guard let target = step.target,
                  ScreenCapture.isPlausible(target, in: space) else { return nil }
            return Resolved(step: step, frame: capture.screenRect(for: target, in: space), isExact: false)
        }
    }
}
