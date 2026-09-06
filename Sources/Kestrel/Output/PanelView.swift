import SwiftUI

/// The floating panel: state, transcript, answer, hotkey hints. Everything moves on the same
/// spring so the panel feels like one object changing rather than several views swapping.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onOpenPermission: (URL) -> Void

    private var spring: Animation { .spring(response: 0.34, dampingFraction: 0.82) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
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
            footer
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(background)
        .overlay(border)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .animation(spring, value: model.state)
        .animation(spring, value: model.answer.isEmpty)
        .animation(spring, value: model.transcript.isEmpty)
        .onHover { model.isHovering = $0 }
        .modifier(PulseEffect(trigger: model.pulse))
    }

    // MARK: - Pieces

    private var background: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.regularMaterial)
    }

    /// The border carries the state colour, brightening while Kestrel is actually listening.
    private var border: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(model.accent.opacity(model.isRecording ? 0.6 : 0.16),
                          lineWidth: model.isRecording ? 1.5 : 1)
    }

    private var header: some View {
        HStack(spacing: 9) {
            PanelIndicator(model: model)
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .contentTransition(.opacity)
                .id(model.label)
            Spacer(minLength: 8)
            Text(model.backend.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.4)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KestrelPalette.blue.opacity(0.16), in: Capsule())
                .foregroundStyle(.secondary)
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
                .transition(.opacity)
                .id(model.answer)
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
