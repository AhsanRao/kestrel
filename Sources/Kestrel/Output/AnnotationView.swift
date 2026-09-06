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
        // Marks land one after another, so several of them read as a sequence of gestures rather
        // than as a diagram appearing at once.
        let delay = 0.1 + Double(index) * 0.28

        return ZStack(alignment: .topLeading) {
            Group {
                if annotation.shape == .circle {
                    DrawsOn(shape: SketchEllipse(), lineWidth: 3.5,
                            duration: Sketch.duration(forSpan: span), delay: delay)
                } else {
                    DrawsOn(shape: SketchRect(cornerRadius: 8), lineWidth: 3.5,
                            duration: Sketch.duration(forSpan: span), delay: delay)
                }
            }
            .frame(width: max(rect.width, 14), height: max(rect.height, 14))
            .offset(x: rect.minX, y: rect.minY)

            arrow(into: rect, bounds: bounds, delay: delay)

            if model.annotations.count > 1, !annotation.caption.isEmpty {
                badge(index: index, caption: annotation.caption, rect: rect, delay: delay)
            }
        }
    }

    /// The arrow comes in from whichever side has room, so it never crosses the control it points at.
    private func arrow(into rect: CGRect, bounds: CGSize, delay: Double) -> some View {
        let fromLeft = rect.minX > 190
        let start = CGPoint(x: fromLeft ? max(rect.minX - 120, 20) : min(rect.maxX + 120, bounds.width - 20),
                            y: rect.midY + (rect.minY > 120 ? -70 : 70))
        let tip = CGPoint(x: fromLeft ? rect.minX - 10 : rect.maxX + 10, y: rect.midY)
        let shape = SketchArrow(from: start, to: tip, bow: fromLeft ? 20 : -20)
        return DrawsOn(shape: shape, lineWidth: 3,
                       duration: Sketch.duration(forSpan: shape.span), delay: delay + 0.16)
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
