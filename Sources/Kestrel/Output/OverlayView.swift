import SwiftUI

/// Draws one walkthrough step over the live screen: a ring around the control to click, its number,
/// and the instruction. Everything is click-through; the window below still receives the click.
struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                if let step = model.currentStep, let rect = model.currentRect {
                    highlight(step: step, rect: rect)
                    let anchor = captionOrigin(rect: rect, bounds: geometry.size)
                    arrow(from: anchor, to: rect)
                    caption(step: step, at: anchor)
                } else if let step = model.currentStep {
                    // The control is not on screen yet — a menu that has not been opened, most
                    // often. Naming it and waiting beats ending the route with nothing said.
                    searching(step: step, bounds: geometry.size)
                }
                footer(bounds: geometry.size)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Pieces

    /// The mark is drawn on, once, per step: the stroke travels around the control instead of the
    /// shape appearing whole. `.id` is the step, so each step gets a fresh draw rather than a
    /// silent jump from the last one.
    private func highlight(step: WalkthroughStep, rect: CGRect) -> some View {
        let inflated = rect.insetBy(dx: -10, dy: -10)
        let span = (inflated.width + inflated.height) * 2
        return ZStack(alignment: .topLeading) {
            Group {
                if step.shape == "circle" {
                    DrawsOn(shape: SketchEllipse(), lineWidth: 4,
                            duration: Sketch.duration(forSpan: span), delay: 0.24)
                } else {
                    DrawsOn(shape: SketchRect(cornerRadius: 10), lineWidth: 4,
                            duration: Sketch.duration(forSpan: span), delay: 0.24)
                }
            }
            .frame(width: max(inflated.width, 12), height: max(inflated.height, 12))
            .background(
                KestrelPalette.cyan.opacity(0.10)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            // The pulse is its own view so the repeating animation owns nothing but the scale. Put
            // it on this subtree and it also owns the mark's position, which it will then animate
            // back and forth between wherever the mark first laid out and where it belongs.
            .modifier(Breathing(active: model.breathing))
            .offset(x: inflated.minX, y: inflated.minY)
        }
        .id(model.index)
    }

    /// An arrow drawn from the instruction to the control, so the words and the thing they name are
    /// visibly one gesture rather than two separate overlays.
    private func arrow(from origin: CGPoint, to rect: CGRect) -> some View {
        let start = CGPoint(x: origin.x + 26, y: origin.y < rect.midY ? origin.y + 44 : origin.y - 8)
        let edge = CGPoint(x: rect.midX, y: start.y < rect.midY ? rect.minY - 14 : rect.maxY + 14)
        let shape = SketchArrow(from: start, to: edge, bow: 22)
        return DrawsOn(shape: shape, lineWidth: 3,
                       duration: Sketch.duration(forSpan: shape.span), delay: 0.06)
            .id(model.index)
    }

    private func captionOrigin(rect: CGRect, bounds: CGSize) -> CGPoint {
        let width = OverlayView.captionWidth
        // Prefer below the target; flip above when there is no room.
        let below = rect.maxY + 54
        let y = below + 80 < bounds.height ? below : max(rect.minY - 130, 12)
        let x = min(max(rect.midX - width / 2, 12), max(bounds.width - width - 12, 12))
        return CGPoint(x: x, y: y)
    }

    private func caption(step: WalkthroughStep, at origin: CGPoint) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Text("\(step.n)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(KestrelPalette.navy)
                    .frame(width: 24, height: 24)
                    .background(KestrelPalette.cyan, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.instruction)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if let next = model.nextInstruction {
                        Text("then \(next.prefix(1).lowercased() + next.dropFirst())")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .offset(x: origin.x, y: origin.y)
        .transition(.opacity)
    }

    /// Shown while the step's control has not been found on screen yet.
    private func searching(step: WalkthroughStep, bounds: CGSize) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Text("\(step.n)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(KestrelPalette.navy)
                    .frame(width: 24, height: 24)
                    .background(KestrelPalette.cyan, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.instruction)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Looking for it — click when you have done this")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
        }
        .offset(x: max((bounds.width - OverlayView.captionWidth) / 2, 12), y: bounds.height / 2 - 40)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(width: OverlayView.captionWidth, alignment: .leading)
            .background(KestrelPalette.navy.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(KestrelPalette.cyan.opacity(0.35), lineWidth: 1)
            )
            .shadow(radius: 18, y: 6)
    }

    private func footer(bounds: CGSize) -> some View {
        HStack(spacing: 8) {
            Text(model.goal.isEmpty ? "Walkthrough" : model.goal)
                .font(.system(size: 12, weight: .semibold))
            Text("Step \(model.index + 1) of \(model.steps.count)\(model.needsMore ? "+" : "")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(model.showsAnyClickHint ? "Ring off? Click anywhere to continue" : "Esc to stop")
                .font(.system(size: 11))
                .foregroundStyle(model.showsAnyClickHint ? KestrelPalette.cyan : Color.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 10, y: 3)
        .offset(x: max((bounds.width - 380) / 2, 12), y: bounds.height - 68)
    }

    private static let captionWidth: CGFloat = 300
}

/// The slow swell that keeps the current mark alive while the user looks for it.
private struct Breathing: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swelled = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(swelled ? 1.03 : 1.0)
            .onAppear {
                guard active, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    swelled = true
                }
            }
    }
}
