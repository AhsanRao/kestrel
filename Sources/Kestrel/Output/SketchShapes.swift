import SwiftUI

/// The marks Kestrel draws on the user's screen, and the stroke that draws them.
///
/// A rectangle that simply appears reads as a screenshot annotation done to the user. A stroke that
/// travels — circling the control, an arrow arriving at it — reads as someone pointing while they
/// talk, which is the whole difference between a chatbot with a screenshot and a person at your
/// shoulder. Every shape here is one continuous path so `trim(to:)` can draw it a bit at a time.
enum Sketch {
    /// How long a mark of a given path length should take, so a small circle is not sluggish and a
    /// long arrow is not a flicker.
    static func duration(forSpan span: CGFloat) -> Double {
        min(0.75, max(0.32, Double(span) / 1400))
    }
}

/// A circle drawn the way a hand draws one: slightly out of round, started at the top, and carried
/// a little past where it began.
struct SketchEllipse: Shape {
    /// Extra sweep past 360°, so the stroke visibly closes over its own start.
    var overshoot: Double = 26
    var wobble: CGFloat = 0.018

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width / 2, radiusY = rect.height / 2
        let total = 360 + overshoot
        let steps = 96
        for step in 0...steps {
            let degrees = -95 + total * Double(step) / Double(steps)
            let radians = degrees * .pi / 180
            // A slow three-lobed swell is enough to look drawn rather than plotted.
            let swell = 1 + wobble * sin(3 * radians + 0.7)
            let point = CGPoint(x: center.x + cos(radians) * radiusX * swell,
                                y: center.y + sin(radians) * radiusY * swell)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A rounded rectangle drawn as one stroke from the top edge, closing past its own start.
struct SketchRect: Shape {
    var cornerRadius: CGFloat = 10
    /// How far past the start point the stroke carries, as a fraction of the top edge.
    var overshoot: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        let start = CGPoint(x: rect.midX, y: rect.minY)
        path.move(to: start)
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: start.x + rect.width * overshoot, y: rect.minY))
        return path
    }
}

/// A curved arrow from `from` to `to`, head included in the same path so the head lands last.
struct SketchArrow: Shape {
    var from: CGPoint
    var to: CGPoint
    /// Sideways bow of the shaft, in points. Zero draws a straight arrow.
    var bow: CGFloat = 26
    var headLength: CGFloat = 15

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        // Control point pushed perpendicular to the shaft, which is what gives the drawn-by-hand arc.
        let control = CGPoint(x: (from.x + to.x) / 2 - dy / length * bow,
                              y: (from.y + to.y) / 2 + dx / length * bow)
        path.move(to: from)
        path.addQuadCurve(to: to, control: control)

        // The head follows the tangent at the tip, which for a quad curve points away from `control`.
        let tangent = CGPoint(x: to.x - control.x, y: to.y - control.y)
        let tangentLength = max(sqrt(tangent.x * tangent.x + tangent.y * tangent.y), 1)
        let angle = atan2(tangent.y / tangentLength, tangent.x / tangentLength)
        for spread in [Double.pi * 0.82, -Double.pi * 0.82] {
            let barb = CGPoint(x: to.x + cos(angle + spread) * headLength,
                               y: to.y + sin(angle + spread) * headLength)
            path.move(to: to)
            path.addLine(to: barb)
        }
        return path
    }

    var span: CGFloat { hypot(to.x - from.x, to.y - from.y) }
}

/// Strokes a shape on as though it were being drawn, once, when it appears.
///
/// Give it an `.id()` that changes per step: the draw-on is an `onAppear` animation, so a new
/// identity is what makes the next mark draw itself rather than snap into place.
struct DrawsOn<S: Shape>: View {
    let shape: S
    var color: Color = KestrelPalette.cyan
    var lineWidth: CGFloat = 3.5
    var duration: Double = 0.5
    var delay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        shape
            .trim(from: 0, to: progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: color.opacity(0.55), radius: 9)
            .onAppear {
                // Reduce Motion still gets the mark, it just does not watch it being made.
                guard !reduceMotion else { progress = 1; return }
                withAnimation(.easeOut(duration: duration).delay(delay)) { progress = 1 }
            }
    }
}
