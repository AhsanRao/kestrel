import SwiftUI

/// Draws the marks that go with a spoken answer: a loop around each control, an arrow into the
/// first one, and the control's name when there is more than one thing being pointed at.
struct AnnotationView: View {
    @ObservedObject var model: AnnotationOverlayModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(Array(model.annotations.enumerated()), id: \.offset) { index, annotation in
                    mark(annotation, index: index, bounds: geometry.size)
                }
            }
            .id(model.generation)
        }
        .ignoresSafeArea()
    }

    private func mark(_ annotation: Annotation, index: Int, bounds: CGSize) -> some View {
        let rect = model.viewRect(for: annotation.frame).insetBy(dx: -9, dy: -7)
        let span = (rect.width + rect.height) * 2
        let ringDuration = Sketch.duration(forSpan: span)
        // The cursor is one hand, so the marks are made one after another: it arrives at the first
        // control, rings it, travels to the next, and rings that.
        let arrival = start(index)
        let travel = arrow(into: rect, bounds: bounds, delay: arrival)
        let fromLeft = comesFromLeft(rect)
        let isLast = index == model.annotations.count - 1

        return ZStack(alignment: .topLeading) {
            if annotation.isRegion {
                // A section is shaded rather than ringed: the mark has to say "this area", and a
                // thin line around a quarter of the screen says "something is wrong with my maths".
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(KestrelPalette.cyan.opacity(0.12))
                    .frame(width: max(rect.width, 14), height: max(rect.height, 14))
                    .offset(x: rect.minX, y: rect.minY)
                    .modifier(FadesIn(delay: arrival + travel.duration))
            }
            travel.view
            Group {
                if annotation.shape == .circle {
                    DrawsOn(shape: SketchEllipse(start: fromLeft ? .leading : .trailing),
                            lineWidth: AnnotationView.stroke, duration: ringDuration,
                            delay: arrival + travel.duration, restsAfterDrawing: isLast)
                } else {
                    DrawsOn(shape: SketchRect(cornerRadius: 8, start: fromLeft ? .leading : .trailing),
                            lineWidth: AnnotationView.stroke, duration: ringDuration,
                            delay: arrival + travel.duration, restsAfterDrawing: isLast)
                }
            }
            .frame(width: max(rect.width, 14), height: max(rect.height, 14))
            .offset(x: rect.minX, y: rect.minY)

            // A region is always named. Its outline says where, but only the label says which of
            // the several things inside it the answer meant.
            if !annotation.caption.isEmpty, annotation.isRegion || model.annotations.count > 1 {
                badge(index: index, caption: annotation.caption, rect: rect,
                      delay: arrival + travel.duration + ringDuration)
            }
        }
    }

    /// When the cursor gets to this mark: after everything before it has been drawn.
    private func start(_ index: Int) -> Double {
        Sketch.leadIn + Double(index) * AnnotationView.perMark
    }

    /// Rough time for one arrow plus one loop, which is all the sequencing needs to be — a mark
    /// that finishes a little early simply leaves the cursor resting on it for a moment.
    ///
    /// Not private: how long the marks stay on screen is worked out from it, and a lifetime that
    /// does not know how long the drawing takes can take the first mark away before the last one
    /// has been made.
    static let perMark: Double = 0.95

    /// Pencil width. Thin enough that a ring around a pane does not read as a border the app
    /// itself drew, heavy enough to stay visible over a busy screen.
    static let stroke: CGFloat = 1.5

    private func comesFromLeft(_ rect: CGRect) -> Bool { rect.minX > 190 }

    /// The arrow comes in from whichever side has room, so it never crosses the control it points at.
    private func arrow(into rect: CGRect, bounds: CGSize, delay: Double)
        -> (view: AnyView, duration: Double) {
        let fromLeft = comesFromLeft(rect)
        let from = CGPoint(x: fromLeft ? max(rect.minX - 120, 20) : min(rect.maxX + 120, bounds.width - 20),
                           y: rect.midY + (rect.minY > 120 ? -70 : 70))
        // `rect` is already the ring, so the standoff is measured from the drawn edge.
        let tip = CGPoint(x: fromLeft ? rect.minX - Sketch.arrowStandoff : rect.maxX + Sketch.arrowStandoff,
                          y: rect.midY)
        let shape = SketchArrow(from: from, to: tip, bow: fromLeft ? 20 : -20)
        let duration = Sketch.duration(forSpan: shape.span)
        return (AnyView(DrawsOn(shape: shape, lineWidth: AnnotationView.stroke - 0.5, duration: duration, delay: delay,
                                restsAfterDrawing: false)),
                duration)
    }

    private func badge(index: Int, caption: String, rect: CGRect, delay: Double) -> some View {
        HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(KestrelPalette.navy)
                .frame(width: 18, height: 18)
                .background(KestrelPalette.cyan, in: Circle())
            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(KestrelPalette.navy.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(KestrelPalette.cyan.opacity(0.3), lineWidth: 1))
        .shadow(radius: 10, y: 3)
        .fixedSize()
        .offset(x: rect.minX, y: max(rect.minY - 32, 6))
        .modifier(FadesIn(delay: delay + 0.3))
    }
}

/// The captions arrive after the stroke that earned them.
private struct FadesIn: ViewModifier {
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.easeOut(duration: 0.25).delay(delay)) { shown = true }
            }
    }
}
