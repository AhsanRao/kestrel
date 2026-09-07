import CoreGraphics
import Foundation

/// Where one mark's pieces go, and when each of them is drawn.
///
/// Worked out in one place because the pieces are not independent: the loop has to begin on the
/// side of the control the arrow arrived at, and it has to begin at the moment the arrow finishes.
/// Get either wrong and the cursor jumps, which is the difference between a hand drawing and two
/// animations that happen to overlap.
struct MarkPlan {
    var target: CGRect
    var bounds: CGSize
    var captionWidth: CGFloat

    /// The caption sits below the control when there is room, and above it when there is not.
    var isBelow: Bool {
        target.maxY + 54 + 80 >= bounds.height
    }

    var captionOrigin: CGPoint {
        let y = isBelow ? max(target.minY - 130, 12) : target.maxY + 54
        let x = min(max(target.midX - captionWidth / 2, 12), max(bounds.width - captionWidth - 12, 12))
        return CGPoint(x: x, y: y)
    }

    /// The loop drawn around the control.
    var ring: CGRect { target.insetBy(dx: -10, dy: -10) }

    var arrow: SketchArrow {
        let origin = captionOrigin
        let from = CGPoint(x: origin.x + 26, y: isBelow ? origin.y - 8 : origin.y + 44)
        let to = CGPoint(x: target.midX, y: isBelow ? target.maxY + 13 : target.minY - 13)
        return SketchArrow(from: from, to: to, bow: isBelow ? -20 : 20)
    }

    var arrowDuration: Double { Sketch.duration(forSpan: arrow.span) }

    /// The loop starts on the side the arrow's tip landed on, so the cursor carries straight on.
    var ringStart: SketchStart { isBelow ? .bottom : .top }
    var ringDuration: Double { Sketch.duration(forSpan: (ring.width + ring.height) * 2) }
    var ringDelay: Double { Sketch.leadIn + arrowDuration }
}
