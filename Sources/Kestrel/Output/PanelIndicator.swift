import SwiftUI

/// The one moving part in the panel's header. It changes shape with the session rather than just
/// changing colour, so the state is readable from the corner of the eye: bars that move while
/// Kestrel listens, a drifting sweep while it thinks, a settled dot when it answers.
struct PanelIndicator: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        ZStack {
            switch model.state {
            case .listening, .dictating:
                WaveformBars(accent: model.accent, level: model.levelPhase)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .transcribing, .thinking, .injecting:
                ThinkingSweep(accent: model.accent)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            default:
                Circle()
                    .fill(model.accent)
                    .frame(width: 8, height: 8)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 14)
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: model.state)
    }
}

/// Five bars breathing at slightly different rates — enough motion to read as "listening" without
/// tapping the microphone for real levels.
private struct WaveformBars: View {
    let accent: Color
    let level: Double

    private let heights: [CGFloat] = [0.45, 0.8, 1.0, 0.7, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                Capsule()
                    .fill(accent)
                    .frame(width: 2.5, height: 14 * height * scale(index))
                    .animation(.easeInOut(duration: 0.42 + Double(index) * 0.06)
                        .repeatForever(autoreverses: true), value: level)
            }
        }
    }

    private func scale(_ index: Int) -> CGFloat {
        let phase = level > 0.5 ? 1.0 : 0.45
        return index.isMultiple(of: 2) ? CGFloat(phase) : CGFloat(1.45 - phase)
    }
}

/// A ring with a moving gap: the standard "working" idiom, without a spinner's busy feel.
private struct ThinkingSweep: View {
    let accent: Color
    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0.08, to: 0.62)
            .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
