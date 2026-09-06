import SwiftUI

/// The floating panel: state, transcript, answer, hotkey hints. Everything moves on the same
/// spring so the panel feels like one object changing rather than several views swapping.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onOpenPermission: (URL) -> Void

    private var spring: Animation { .spring(response: 0.34, dampingFraction: 0.82) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // The top strip is the notch itself: nothing may be drawn under the camera housing, so
            // the state lives to either side of it, the way the menu bar does.
            notchBar
            if !model.transcript.isEmpty {
                Text(model.transcript)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !model.answer.isEmpty {
                answer
            }
            if model.isError, let url = model.permissionURL {
                Button("Open Privacy settings") { onOpenPermission(url) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .transition(.opacity)
            }
            if model.isExpanded { footer }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, model.isExpanded ? 13 : 9)
        .frame(width: model.width, alignment: .leading)
        .background(background)
        .overlay(border)
        // The panel hangs off the top of the display in the notch's own colours, so its contents
        // are always read against black rather than against the user's wallpaper.
        .environment(\.colorScheme, .dark)
        // No SwiftUI shadow: the window is sized to this view, so a shadow drawn here is clipped
        // at the edges. The panel's own window shadow does the job properly.
        .compositingGroup()
        .animation(spring, value: model.state)
        .animation(spring, value: model.answer.isEmpty)
        .animation(spring, value: model.transcript.isEmpty)
        .animation(spring, value: model.isFollowUp)
        .animation(.easeOut(duration: 0.22), value: model.answer)
        .animation(spring, value: model.isExpanded)
        .onHover { model.isHovering = $0 }
        .modifier(PulseEffect(trigger: model.pulse))
    }

    // MARK: - Pieces

    private var background: some View {
        NotchShape(bottomRadius: model.isExpanded ? 24 : 18)
            // Near-black rather than a material: on a notched Mac this edge has to be the same
            // colour as the housing beside it, or the seam gives the whole thing away.
            .fill(Color(white: 0.045))
            // A wash of the state colour, so the panel reads correctly before a word of it does.
            .overlay(
                NotchShape(bottomRadius: model.isExpanded ? 24 : 18)
                    .fill(model.accent.opacity(model.isError ? 0.16 : model.isRecording ? 0.12 : 0.04))
            )
    }

    /// The border carries the state colour, brightening while Kestrel is actually listening.
    private var border: some View {
        NotchShape(bottomRadius: model.isExpanded ? 24 : 18)
            .stroke(model.accent.opacity(model.isRecording ? 0.55 : 0.14),
                    lineWidth: model.isRecording ? 1.5 : 1)
    }

    /// State on the left of the housing, backend on the right — with a gap the exact width of the
    /// notch between them.
    ///
    /// The two sides are given equal fixed widths rather than being pushed apart by spacers: the
    /// panel is centred on the screen and the housing is centred on the panel, so the gap only
    /// lands on the real notch if neither side can steal space from the other.
    private var notchBar: some View {
        let gap = model.notch.notchSize.width
        let side = max((model.width - gap) / 2, 60)
        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                PanelIndicator(model: model)
                Text(model.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(model.isExpanded ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .frame(width: side, alignment: .leading)

            Color.clear.frame(width: gap, height: 1)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if model.isFollowUp {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
                Text(model.backend.displayName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(KestrelPalette.blue.opacity(0.22), in: Capsule())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Backend: \(model.backend.displayName)")
            }
            .padding(.trailing, 14)
            .frame(width: side, alignment: .trailing)
        }
        .frame(height: max(model.notch.barHeight - 4, 22))
        // The bar spans the full width of the panel; the padding belongs to what sits under it.
        .padding(.horizontal, -14)
    }

    private var header: some View {
        HStack(spacing: 9) {
            PanelIndicator(model: model)
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(3)
                // Errors name the command that fixes them, so they must wrap rather than truncate.
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            if model.isFollowUp {
                Label("follow-up", systemImage: "arrow.turn.down.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .labelStyle(.titleAndIcon)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
            Text(model.backend.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KestrelPalette.blue.opacity(0.16), in: Capsule())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Backend: \(model.backend.displayName)")
        }
    }

    private var answer: some View {
        ScrollView {
            Text(model.answer)
                .font(.system(size: 13))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                // New sentences arrive while the model is still writing; fading them in reads as
                // speech appearing rather than the panel jumping.
                // Sentences arrive while the model is still writing; a crossfade reads as speech
                // appearing rather than as the panel being rebuilt.
                .contentTransition(.opacity)
        }
        .frame(maxHeight: 260)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(model.askHint, systemImage: "mic")
            Label(model.dictateHint, systemImage: "text.cursor")
            Spacer()
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .labelStyle(.titleAndIcon)
    }
}

/// A short nudge when a hotkey arrives while Kestrel is busy (spec §5.4).
private struct PulseEffect: ViewModifier {
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
