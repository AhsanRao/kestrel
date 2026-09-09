import SwiftUI

/// Kestrel's island: a black shape hanging off the top edge of the display, sized to the notch
/// when there is nothing to read and opening downward when there is.
///
/// Two rules make it read as part of the machine rather than a window near it. It is pure black,
/// because the camera housing is pure black and any other value draws a seam right across the
/// middle of it. And its top row is a shade taller than the housing, so the housing has nothing to
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

    /// Where an answer stops. Long enough for anything worth reading off a notch, short enough that
    /// the island cannot grow down the whole display.
    static let answerLines = 14

    private var island: some View {
        VStack(alignment: .leading, spacing: 0) {
            notchRow
            if model.isExpanded { content }
        }
        .frame(width: model.width)
        .background(shape.fill(KestrelPalette.housing))
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
        NotchShape(bottomRadius: model.isExpanded ? 26 : 17, shoulder: PanelView.shoulder)
    }

    /// The concave flare where the island meets the top of the screen.
    static let shoulder: CGFloat = 12
    /// Where text starts, measured from the island's frame.
    ///
    /// The shape's body is inset by the shoulder on both sides, so padding measured from the frame
    /// is not the gap anyone actually sees: at 16 the text sat four points off the visible edge.
    static var inset: CGFloat { shoulder + 18 }

    /// A hairline that fades out before it reaches the top edge: a border across the very top would
    /// be the one line that gives away where the housing ends and Kestrel begins.
    ///
    /// Gone entirely while the island is collapsed. Closed, the whole island *is* the notch strip,
    /// so a rim that brightens towards the bottom draws a lit outline a few points below the
    /// housing — the exact seam it exists to avoid. Black on black is what makes the housing
    /// disappear; nothing else may be drawn over it.
    @ViewBuilder private var rim: some View {
        if model.isExpanded {
            shape.stroke(
                LinearGradient(colors: [.clear, .white.opacity(model.isRecording ? 0.18 : 0.10)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
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
            .padding(.leading, PanelView.inset)
            .frame(width: side, alignment: .leading)

            Color.clear.frame(width: gap, height: 1)

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                if model.isFollowUp {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
                trailing
            }
            .padding(.trailing, PanelView.inset)
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
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if !model.answer.isEmpty {
                // Laid out at its full height rather than inside a scroller. A ScrollView takes
                // whatever space it is offered, and here the space it is offered is the window —
                // whose height is being decided by this very measurement. The island grows to fit
                // the answer instead, which is what an island is supposed to do.
                ClippedText(text: model.answer, font: .systemFont(ofSize: 13), lineSpacing: 2.5,
                            limit: PanelView.answerLines) { hidden in
                    "+\(hidden) more line\(hidden == 1 ? "" : "s")"
                }
                .contentTransition(.opacity)
            }
            if let draft = model.draft {
                DraftCard(draft: draft)
            }
            if model.isError, let url = model.permissionURL {
                Button("Open Privacy settings") { onOpenPermission(url) }
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PanelView.inset)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .transition(.opacity)
    }
}
