import SwiftUI

/// Four pips that rise with the user's voice — the notch's own level meter, small enough to live
/// beside the housing without crowding it.
struct LevelPips: View {
    let level: Double
    let accent: Color

    private let weights: [Double] = [0.55, 0.9, 0.7, 0.4]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(weights.enumerated()), id: \.offset) { index, weight in
                Capsule()
                    .fill(accent)
                    .frame(width: 2.5, height: 3 + 11 * min(level * 1.4, 1) * weight)
                    .animation(.spring(response: 0.2 + Double(index) * 0.02, dampingFraction: 0.6),
                               value: level)
            }
        }
        .frame(height: 14)
    }
}

/// Reports the island's own size so the window can follow it, rather than the other way round.
struct MeasuresIsland: ViewModifier {
    var onChange: ((CGSize) -> Void)?

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { onChange?(geometry.size) }
                    .onChange(of: geometry.size) { _, size in onChange?(size) }
            }
        )
    }
}

/// A short nudge when a hotkey arrives while Kestrel is busy (spec §5.4).
struct PulseEffect: ViewModifier {
    let trigger: Int
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.06).repeatCount(4, autoreverses: true)) { offset = 5 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { offset = 0 }
            }
    }
}
