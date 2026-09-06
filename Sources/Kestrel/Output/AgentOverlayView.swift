import SwiftUI

/// The visible half of an agent run: a marker on the control being touched, what is being done to
/// it in words, and how to stop.
struct AgentOverlayView: View {
    @ObservedObject var model: AgentOverlayModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                if let rect = model.targetInView {
                    marker(rect)
                    caption(rect, bounds: geometry.size)
                }
                banner(bounds: geometry.size)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: model.stepIndex)
            .animation(.easeOut(duration: 0.2), value: model.isFinishing)
        }
        .ignoresSafeArea()
    }

    /// A ring plus a small dot: the dot is the agent's own pointer, so it is obvious that something
    /// other than the user's hand is doing this.
    private func marker(_ rect: CGRect) -> some View {
        let ring = rect.insetBy(dx: -8, dy: -8)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(KestrelPalette.cyan, lineWidth: 3)
                .background(KestrelPalette.cyan.opacity(0.12))
                .frame(width: ring.width, height: ring.height)
                .shadow(color: KestrelPalette.cyan.opacity(0.5), radius: 10)
                .offset(x: ring.minX, y: ring.minY)
            Circle()
                .fill(KestrelPalette.cyan)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 12, height: 12)
                .shadow(radius: 4)
                .offset(x: rect.midX - 6, y: rect.midY - 6)
        }
    }

    private func caption(_ rect: CGRect, bounds: CGSize) -> some View {
        let width: CGFloat = 320
        let below = rect.maxY + 18
        let y = below + 60 < bounds.height ? below : max(rect.minY - 74, 12)
        let x = min(max(rect.midX - width / 2, 12), bounds.width - width - 12)

        return Text(model.describe)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: width, alignment: .leading)
            .background(KestrelPalette.navy.opacity(0.93),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(KestrelPalette.cyan.opacity(0.35), lineWidth: 1))
            .shadow(radius: 16, y: 5)
            .offset(x: x, y: y)
    }

    private func banner(bounds: CGSize) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(model.isFinishing ? Color.green : KestrelPalette.cyan)
                .frame(width: 7, height: 7)
            Text(model.goal.isEmpty ? "Working" : model.goal)
                .font(.system(size: 12, weight: .semibold))
            if !model.progress.isEmpty {
                Text(model.progress)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("Esc to stop")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(radius: 10, y: 3)
        .offset(x: max((bounds.width - 420) / 2, 12), y: 28)
    }
}
