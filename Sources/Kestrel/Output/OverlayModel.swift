import AppKit
import SwiftUI

/// Drawing state for the overlay. Updated on the main thread by `WalkthroughSession`.
final class OverlayModel: ObservableObject {
    @Published var steps: [WalkthroughStep] = []
    @Published var index: Int = 0 { didSet { isCurrentFrameLive = false } }
    @Published var goal: String = ""
    @Published var breathing = false
    /// Set once the user has clicked past the ring twice: the drawing is probably slightly off.
    @Published var showsAnyClickHint = false

    /// The goal needs more than this screen; the overlay says so rather than just ending.
    @Published var needsMore = false
    /// Where each step points, in global AppKit points. Parallel to `steps`; nil for a step whose
    /// control is not on screen yet.
    @Published var frames: [CGRect?] = []
    /// True when the current frame came from a live scan taken at this step rather than from the
    /// plan, which means it is exact and the click target can be tight.
    @Published private(set) var isCurrentFrameLive = false

    /// The overlay window's own frame in global AppKit points; marks are placed relative to it.
    ///
    /// Published, and set before the window's view is built: a first layout against a zero frame
    /// puts every mark off screen, and the correction then arrives on the same render pass as the
    /// breathing animation, which pulls the mark endlessly back and forth between the two places.
    @Published var windowFrame: CGRect = .zero

    var currentStep: WalkthroughStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    /// The current target in global screen points, for hit-testing a click.
    var currentFrame: CGRect? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    /// The same target inside the overlay window.
    var currentRect: CGRect? {
        currentFrame.map(viewRect(forScreenRect:))
    }

    /// The step after this one, so the user can see where the route is going.
    var nextInstruction: String? {
        let next = index + 1
        return steps.indices.contains(next) ? steps[next].instruction : nil
    }

    /// A control found by the live scan for the step now showing.
    func setLiveFrame(_ frame: CGRect) {
        guard frames.indices.contains(index) else { return }
        frames[index] = frame
        isCurrentFrameLive = true
    }

    /// SwiftUI draws from the top-left of the window; AppKit measures from the bottom of the desktop.
    func viewRect(forScreenRect rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - windowFrame.minX,
               y: windowFrame.maxY - rect.maxY,
               width: rect.width, height: rect.height)
    }

    /// The union of every display, which is what the overlay window covers.
    static var desktopBounds: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }
}
