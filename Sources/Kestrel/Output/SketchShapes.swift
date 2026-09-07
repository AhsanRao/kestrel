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
    /// A beat before the first stroke, so the pencil is seen arriving rather than already there.
    static let leadIn: Double = 0.12

    /// How far an arrow stops short of the mark it points at. Longer than the arrowhead, or the
    /// head is drawn over the box.
    static let arrowStandoff: CGFloat = 22

    static func duration(forSpan span: CGFloat) -> Double {
        min(0.75, max(0.32, Double(span) / 1400))
    }
}

/// Which side of the mark the stroke begins on.
///
/// It matters because the cursor draws the arrow first and the loop second: if the loop began
/// somewhere other than where the arrow's tip landed, the cursor would teleport across the control
/// between the two, and the whole point is that one hand is making one gesture.
enum SketchStart {
    case top, trailing, bottom, leading

    /// Where on a circle this side is, in the degrees `SketchEllipse` measures in.
    var degrees: Double {
        switch self {
        case .top: return -95
        case .trailing: return -5
        case .bottom: return 85
        case .leading: return 175
        }
    }

    /// How far around a rounded rectangle's clockwise path this side sits.
    var rectRotation: Int {
        switch self {
        case .top: return 0
        case .trailing: return 3
        case .bottom: return 6
        case .leading: return 9
        }
    }
}

/// A circle drawn the way a hand draws one: slightly out of round, and carried a little past where
/// it began.
struct SketchEllipse: Shape {
    var start: SketchStart = .top
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
            let degrees = start.degrees + total * Double(step) / Double(steps)
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

/// A rounded rectangle drawn as one continuous stroke, from whichever side the cursor arrives on,
/// closing a little past where it began.
struct SketchRect: Shape {
    var cornerRadius: CGFloat = 10
    var start: SketchStart = .top
    /// How far past the start point the stroke carries, as a fraction of the top edge.
    var overshoot: CGFloat = 0.12

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        // One clockwise lap as twelve moves, so it can be started from any of the four side
        // midpoints by rotating the list rather than by writing the path out four times.
        enum Move {
            case line(CGPoint)
            case corner(to: CGPoint, control: CGPoint)

            var end: CGPoint {
                switch self {
                case .line(let point): return point
                case .corner(let point, _): return point
                }
            }
        }
        let moves: [Move] = [
            .line(CGPoint(x: rect.maxX - radius, y: rect.minY)),
            .corner(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                    control: CGPoint(x: rect.maxX, y: rect.minY)),
            .line(CGPoint(x: rect.maxX, y: rect.midY)),
            .line(CGPoint(x: rect.maxX, y: rect.maxY - radius)),
            .corner(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                    control: CGPoint(x: rect.maxX, y: rect.maxY)),
            .line(CGPoint(x: rect.midX, y: rect.maxY)),
            .line(CGPoint(x: rect.minX + radius, y: rect.maxY)),
            .corner(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                    control: CGPoint(x: rect.minX, y: rect.maxY)),
            .line(CGPoint(x: rect.minX, y: rect.midY)),
            .line(CGPoint(x: rect.minX, y: rect.minY + radius)),
            .corner(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                    control: CGPoint(x: rect.minX, y: rect.minY)),
            .line(CGPoint(x: rect.midX, y: rect.minY)),
        ]

        let rotation = start.rectRotation
        let ordered = Array(moves[rotation...] + moves[..<rotation])
        var path = Path()
        path.move(to: moves[(rotation + moves.count - 1) % moves.count].end)
        for move in ordered {
            switch move {
            case .line(let point): path.addLine(to: point)
            case .corner(let point, let control): path.addQuadCurve(to: point, control: control)
            }
        }
        // A little past the start, along the edge it began on.
        if let last = path.currentPoint {
            let overrun = rect.width * overshoot
            switch start {
            case .top: path.addLine(to: CGPoint(x: min(last.x + overrun, rect.maxX - 1), y: last.y))
            case .bottom: path.addLine(to: CGPoint(x: max(last.x - overrun, rect.minX + 1), y: last.y))
            case .trailing: path.addLine(to: CGPoint(x: last.x, y: min(last.y + overrun, rect.maxY - 1)))
            case .leading: path.addLine(to: CGPoint(x: last.x, y: max(last.y - overrun, rect.minY + 1)))
            }
        }
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
