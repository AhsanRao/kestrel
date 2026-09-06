import CoreGraphics
import Foundation

/// A screenshot plus everything needed to map a model's coordinates back onto the real screen.
///
/// Targets arrive in whatever grid the model measured in, which it declares alongside them: the
/// vendors resize images before the model sees them, so a model looking at a 1440x900 screenshot
/// reports coordinates from its own ~320x200 view of it and cannot be talked out of that. Asking
/// it to name its frame and rescaling from there is what actually works. AppKit then wants
/// bottom-left points, so every target makes that round trip here, testable without a display.
struct ScreenCapture: Equatable {
    var url: URL
    /// Frame of the captured display in global AppKit points (origin bottom-left).
    var displayFrame: CGRect
    /// Pixel size of the PNG actually handed to the model. Not used for mapping — kept for logs.
    var pixelSize: CGSize

    func pointsPerUnitX(in space: Walkthrough.ImageSize) -> CGFloat {
        displayFrame.width / CGFloat(space.w)
    }

    func pointsPerUnitY(in space: Walkthrough.ImageSize) -> CGFloat {
        displayFrame.height / CGFloat(space.h)
    }

    /// Target in the model's own grid (origin top-left) → global screen rect (origin bottom-left).
    func screenRect(for target: WalkthroughStep.Target, in space: Walkthrough.ImageSize) -> CGRect {
        let scaleX = pointsPerUnitX(in: space), scaleY = pointsPerUnitY(in: space)
        let x = displayFrame.minX + CGFloat(target.x) * scaleX
        // y counts down from the top of the display, AppKit counts up from the bottom.
        let y = displayFrame.maxY - (CGFloat(target.y) + CGFloat(target.h)) * scaleY
        return CGRect(x: x, y: y, width: CGFloat(target.w) * scaleX, height: CGFloat(target.h) * scaleY)
    }

    /// The same rect in the top-left drawing space SwiftUI uses inside the overlay window.
    func viewRect(for target: WalkthroughStep.Target, in space: Walkthrough.ImageSize) -> CGRect {
        let scaleX = pointsPerUnitX(in: space), scaleY = pointsPerUnitY(in: space)
        return CGRect(x: CGFloat(target.x) * scaleX, y: CGFloat(target.y) * scaleY,
                      width: CGFloat(target.w) * scaleX, height: CGFloat(target.h) * scaleY)
    }

    /// True when the target could plausibly be a control on this screen. Models sometimes invent
    /// coordinates or contradict the frame they declared; those steps are described, not drawn.
    static func isPlausible(_ target: WalkthroughStep.Target, in space: Walkthrough.ImageSize) -> Bool {
        guard target.w > 0, target.h > 0 else { return false }
        let canvas = CGRect(x: 0, y: 0, width: space.w, height: space.h)
        let rect = CGRect(x: target.x, y: target.y, width: target.w, height: target.h)
        guard canvas.contains(CGPoint(x: rect.midX, y: rect.midY)) else { return false }
        // A "target" covering nearly the whole screen is not a target.
        return rect.width <= space.w * 0.9 || rect.height <= space.h * 0.9
    }
}
