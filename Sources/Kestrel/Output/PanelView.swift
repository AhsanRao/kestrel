import SwiftUI

/// Kestrel's island: a black shape hanging off the top edge of the display, sized to the notch
/// when there is nothing to read and opening downward when there is.
///
/// Two rules make it read as part of the machine rather than a window near it. It is pure black,
/// because the camera housing is pure black and any other value draws a seam right across the
/// middle of it. And its top row is exactly as tall as the housing, so the housing has nothing to
/// stick out of — the island is the notch, wider.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onOpenPermission: (URL) -> Void

    private var spring: Animation { .spring(response: 0.38, dampingFraction: 0.86) }

    var body: some View {
        // Room around the island for its shadow, which the window would otherwise clip; none at the
        // top, where the island has to stay flush with the edge of the display.
        island
            .padding(.horizontal, PanelView.margin)
            .padding(.bottom, PanelView.margin)
            .modifier(MeasuresIsland(onChange: model.onSizeChange))
    }

    /// How much space the window carries around the island for the shadow.
    static let margin: CGFloat = 26

    private var island: some View {
        VStack(alignment: .leading, spacing: 0) {
            notchRow
            if model.isExpanded { content }
        }
        .frame(width: model.width)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .overlay(rim)
        .compositingGroup()
        .shadow(color: .black.opacity(0.38), radius: 13, y: 6)
        .environment(\.colorScheme, .dark)
        .animation(spring, value: model.isExpanded)
        .animation(spring, value: model.state)
        .animation(.easeOut(duration: 0.2), value: model.answer)
        .animation(spring, value: model.transcript)
        .onHover { model.isHovering = $0 }
        .modifier(PulseEffect(trigger: model.pulse))
    }

    private var shape: NotchShape {
        NotchShape(bottomRadius: model.isExpanded ? 26 : 17, shoulder: 12)
    }

    /// A hairline that fades out before it reaches the top edge: a border across the very top would
    /// be the one line that gives away where the housing ends and Kestrel begins.
    private var rim: some View {
        shape.stroke(
            LinearGradient(colors: [.clear, .white.opacity(model.isRecording ? 0.18 : 0.10)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: 1)
    }

    // MARK: - The notch row

    /// State to the left of the housing, meta to the right, and a gap between them the exact width
    /// of the housing itself. Both sides are fixed and equal so the gap cannot drift off centre.
    private var notchRow: some View {
        let gap = model.notch.notchSize.width
        let side = max((model.width - gap) / 2, 70)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                PanelIndicator(model: model, showsWaveform: false)
                Text(model.headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .frame(width: side, alignment: .leading)

            Color.clear.frame(width: gap, height: 1)

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                if model.isFollowUp {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                trailing
            }
            .padding(.trailing, 16)
            .frame(width: side, alignment: .trailing)
        }
        .frame(height: model.notch.barHeight)
    }

    /// The right shoulder carries whatever is most useful: the level while listening, the hotkey
    /// while idle, the backend once there is an answer to attribute.
    @ViewBuilder private var trailing: some View {
        if model.isRecording {
            LevelPips(level: model.level, accent: model.accent)
        } else if model.isExpanded {
            Text(model.backend.displayName.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityLabel("Backend: \(model.backend.displayName)")
        } else {
            Text(model.askHint)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    // MARK: - The opened half

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let detail = model.detail {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KestrelPalette.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !model.transcript.isEmpty {
                Text(model.transcript)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if !model.answer.isEmpty {
                // Laid out at its full height rather than inside a scroller. A ScrollView takes
                // whatever space it is offered, and here the space it is offered is the window —
                // whose height is being decided by this very measurement. The island grows to fit
                // the answer instead, which is what an island is supposed to do.
                Text(model.answer)
                    .font(.system(size: 13))
                    .lineSpacing(2.5)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.opacity)
            }
            if model.isError, let url = model.permissionURL {
                Button("Open Privacy settings") { onOpenPermission(url) }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .transition(.opacity)
    }
}
