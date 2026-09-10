import SwiftUI

/// Strokes a shape on as though it were being drawn, once, when it appears — with Kestrel's cursor
/// riding the tip of the stroke, so the mark is visibly *being made* by something.
///
/// Give it an `.id()` that changes per step: the draw-on is an `onAppear` animation, so a new
/// identity is what makes the next mark draw itself rather than snap into place.
struct DrawsOn<S: Shape>: View {
    let shape: S
    var color: Color = KestrelPalette.accentOnDark
    var lineWidth: CGFloat = 1.5
    var duration: Double = 0.5
    var delay: Double = 0
    /// False for a stroke drawn while another one is already carrying the cursor.
    var showsCursor: Bool = true
    /// Whether the cursor stays on the mark once it is finished. Only the last stroke of a gesture
    /// does: the rest hand the cursor on, so there is never more than one on screen.
    var restsAfterDrawing: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        AnimatedStroke(shape: shape, progress: progress, color: color, lineWidth: lineWidth,
                       showsCursor: showsCursor, restsAfterDrawing: restsAfterDrawing)
            .onAppear {
                // Reduce Motion still gets the mark, it just does not watch it being made.
                guard !reduceMotion else { progress = 1; return }
                withAnimation(.easeInOut(duration: duration).delay(delay)) { progress = 1 }
            }
    }
}

/// The frame-by-frame half of `DrawsOn`.
///
/// `Animatable` on a *view* rather than a shape is what makes the cursor possible: SwiftUI
/// re-evaluates this body on every frame of the animation, so the path can be trimmed here and its
/// live end point — `trimmedPath(...).currentPoint`, the place the pen has got to — read back and
/// used to position the cursor. A plain `.trim()` modifier animates inside the render tree and
/// never tells anyone where it is.
private struct AnimatedStroke<S: Shape>: View, Animatable {
    var shape: S
    var progress: CGFloat
    var color: Color
    var lineWidth: CGFloat
    var showsCursor: Bool
    var restsAfterDrawing: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// 1 while drawing; ramps to 0 over the last of the stroke unless this cursor is the one that
    /// stays.
    private var handoff: Double {
        guard !restsAfterDrawing else { return 1 }
        return Double(max(0, min(1, (1 - progress) / 0.06)))
    }

    var body: some View {
        GeometryReader { geometry in
            let full = shape.path(in: CGRect(origin: .zero, size: geometry.size))
            let drawn = full.trimmedPath(from: 0, to: max(min(progress, 1), 0))
            ZStack(alignment: .topLeading) {
                drawn
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                                      lineJoin: .round))
                    .shadow(color: color.opacity(0.45), radius: 6)
                if showsCursor, progress > 0.001, let tip = drawn.currentPoint {
                    let drawing = progress < 0.995
                    CursorHalo()
                        .position(tip)
                        .opacity(drawing ? 1 : 0)
                    KestrelCursor(isDrawing: drawing)
                        .offset(x: tip.x, y: tip.y)
                        // A stroke that is handing the cursor on lets go of it as it finishes,
                        // rather than leaving a second pointer sitting on the screen.
                        .opacity(handoff)
                }
            }
        }
    }
}
