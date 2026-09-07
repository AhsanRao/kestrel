import SwiftUI

/// The one moving part in the panel's header. It changes shape with the session rather than only
/// colour, so the state is readable from the corner of the eye — bars that follow the user's own
/// voice while Kestrel listens, an orbiting sweep while it thinks, a settled dot when it answers.
struct PanelIndicator: View {
    @ObservedObject var model: PanelModel
    /// False in the island's notch row, where the live level is metered on the other side of the
    /// housing: two waveforms on one bar is a lot of movement saying one thing.
    var showsWaveform = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.state {
            case .listening, .dictating:
                if showsWaveform {
                    WaveformBars(accent: model.accent, level: model.level)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    SettledDot(accent: model.accent)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            case .transcribing, .thinking, .injecting, .acting:
                ThinkingSweep(accent: model.accent, reduceMotion: reduceMotion)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            default:
                SettledDot(accent: model.accent)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: showsWaveform ? 20 : 16, height: 16)
        .animation(.spring(response: 0.34, dampingFraction: 0.7), value: model.state)
        // The shape alone carries state for sighted users; VoiceOver needs it named instead.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch model.state {
        case .listening, .dictating: return "Listening"
        case .transcribing: return "Transcribing"
        case .thinking: return "Thinking"
        case .injecting: return "Pasting"
        case .acting: return "Working"
        case .answering, .guiding: return "Answer ready"
        case .error: return "Error"
        case .idle: return "Idle"
        }
    }
}

/// Five bars driven by the live microphone level, each lagging the one before it so the shape
/// travels outward from the centre the way a voice does.
private struct WaveformBars: View {
    let accent: Color
    let level: Double

    private let weights: [Double] = [0.42, 0.72, 1.0, 0.78, 0.5]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                Capsule()
                    .fill(accent)
                    .frame(width: 2.5, height: height(weight))
                    .animation(.spring(response: 0.18 + Double(index) * 0.03, dampingFraction: 0.6),
                               value: level)
            }
        }
    }

    /// Always a visible stub, so the bars read as "listening" even in a silent room.
    private func height(_ weight: Double) -> CGFloat {
        let floor = 3.0
        return CGFloat(floor + (15 - floor) * min(level * 1.35, 1) * weight)
    }
}

/// A ring with a moving gap: the standard "working" idiom, without a spinner's busy feel.
private struct ThinkingSweep: View {
    let accent: Color
    let reduceMotion: Bool
    @State private var angle: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 2)
            Circle()
                .trim(from: 0.06, to: 0.5)
                .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 13, height: 13)
        .onAppear {
            // A still, gapped ring still reads as "not idle" without the spin Reduce Motion asks to skip.
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 0.95).repeatForever(autoreverses: false)) { angle = 360 }
        }
    }
}

/// Idle and answering: a dot, with one slow ring pushed out when an answer lands.
private struct SettledDot: View {
    let accent: Color
    @State private var halo: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.5 * (1 - halo)), lineWidth: 1.5)
                .frame(width: 8 + 14 * halo, height: 8 + 14 * halo)
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { halo = 1 }
        }
    }
}
