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
                    caption(step: step, rect: rect, bounds: geometry.size)
                }
                footer(bounds: geometry.size)
            }
            .animation(.easeOut(duration: 0.22), value: model.index)
        }
        .ignoresSafeArea()
    }

    // MARK: - Pieces

    private func highlight(step: WalkthroughStep, rect: CGRect) -> some View {
        let inflated = rect.insetBy(dx: -10, dy: -10)
        return Group {
            if step.shape == "circle" {
                Ellipse().strokeBorder(KestrelPalette.cyan, lineWidth: 4)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(KestrelPalette.cyan, lineWidth: 4)
            }
        }
        .frame(width: inflated.width, height: inflated.height)
        .background(KestrelPalette.cyan.opacity(0.10))
        .shadow(color: KestrelPalette.cyan.opacity(0.55), radius: 12)
        .scaleEffect(reduceMotion ? 1.0 : (model.breathing ? 1.03 : 1.0))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: model.breathing)
        .offset(x: inflated.minX, y: inflated.minY)
    }

    private func caption(step: WalkthroughStep, rect: CGRect, bounds: CGSize) -> some View {
        let width: CGFloat = 300
        // Prefer below the target; flip above when there is no room.
        let below = rect.maxY + 20
        let y = below + 80 < bounds.height ? below : max(rect.minY - 96, 12)
        let x = min(max(rect.midX - width / 2, 12), bounds.width - width - 12)

        return HStack(alignment: .top, spacing: 10) {
            Text("\(step.n)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(KestrelPalette.navy)
                .frame(width: 24, height: 24)
                .background(KestrelPalette.cyan, in: Circle())
            Text(step.instruction)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background(KestrelPalette.navy.opacity(0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(KestrelPalette.cyan.opacity(0.35), lineWidth: 1)
        )
        .shadow(radius: 18, y: 6)
        .offset(x: x, y: y)
    }

    private func footer(bounds: CGSize) -> some View {
        HStack(spacing: 8) {
            Text(model.goal.isEmpty ? "Walkthrough" : model.goal)
                .font(.system(size: 12, weight: .semibold))
            Text("Step \(model.index + 1) of \(model.steps.count)")
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
}

/// Drawing state for the overlay. Updated on the main thread by `WalkthroughSession`.
final class OverlayModel: ObservableObject {
    @Published var steps: [WalkthroughStep] = []
    @Published var index: Int = 0
    @Published var goal: String = ""
    @Published var breathing = false
    /// Set once the user has clicked past the ring twice: the drawing is probably slightly off.
    @Published var showsAnyClickHint = false

    var capture: ScreenCapture?
    /// Where each step points, in global AppKit points. Parallel to `steps`.
    var frames: [CGRect] = []

    var currentStep: WalkthroughStep? {
        steps.indices.contains(index) ? steps[index] : nil
    }

    /// The current target in global screen points, for hit-testing a click.
    var currentFrame: CGRect? {
        frames.indices.contains(index) ? frames[index] : nil
    }

    /// The same target inside the overlay window, which covers `capture.captureFrame`.
    var currentRect: CGRect? {
        guard let frame = currentFrame, let capture else { return nil }
        return capture.viewRect(forScreenRect: frame)
    }
}
