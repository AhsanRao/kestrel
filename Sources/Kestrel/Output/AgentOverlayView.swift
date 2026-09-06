import SwiftUI

/// The visible half of an agent run: a marker on the control being touched, what is being done to
/// it in words, and how to stop.
struct AgentOverlayView: View {
    @ObservedObject var model: AgentOverlayModel

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                // The ring and pointer keep their identity between steps, so moving to the next
                // control is a glide across the screen rather than a cut. Watching it travel is
                // what makes the run legible.
                marker(model.targetInView)
                if let rect = model.targetInView {
                    caption(rect, bounds: geometry.size)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                banner(bounds: geometry.size)
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.targetInView)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: model.stepIndex)
            .animation(.easeOut(duration: 0.2), value: model.isFinishing)
        }
        .ignoresSafeArea()
    }

    /// A ring plus a small pointer of its own, so it is obvious that something other than the
    /// user's hand is doing this. Both are always present and merely move, which is what lets the
    /// glide between controls happen.
    private func marker(_ rect: CGRect?) -> some View {
        let ring = (rect ?? .zero).insetBy(dx: -8, dy: -8)
        let visible = rect != nil
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(KestrelPalette.cyan, lineWidth: 3)
                .background(KestrelPalette.cyan.opacity(0.12))
                .frame(width: max(ring.width, 1), height: max(ring.height, 1))
                .shadow(color: KestrelPalette.cyan.opacity(0.5), radius: 10)
                .offset(x: ring.minX, y: ring.minY)
            AgentPointer()
                .offset(x: (rect?.midX ?? 0) - 9, y: (rect?.midY ?? 0) - 9)
        }
        .opacity(visible ? 1 : 0)
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

/// Kestrel's own pointer: a filled dot inside a slow pulse, so it never looks like the user's
/// cursor has been taken over.
private struct AgentPointer: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(KestrelPalette.cyan.opacity(0.35))
                .frame(width: pulse ? 26 : 14, height: pulse ? 26 : 14)
                .opacity(pulse ? 0 : 0.9)
            Circle()
                .fill(KestrelPalette.cyan)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .frame(width: 14, height: 14)
                .shadow(radius: 4)
        }
        .frame(width: 18, height: 18)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
