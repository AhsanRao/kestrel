import SwiftUI

/// Contents of the floating panel: state dot, backend badge, transcript, answer, hotkey hint.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    var onOpenPermission: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !model.transcript.isEmpty {
                Text(model.transcript)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if !model.answer.isEmpty {
                ScrollView {
                    Text(model.answer)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            if model.isError, let url = model.permissionURL {
                Button("Open Privacy settings") { onOpenPermission(url) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
            footer
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(model.accent.opacity(model.isRecording ? 0.55 : 0.18), lineWidth: 1)
        )
        .onHover { model.isHovering = $0 }
        .modifier(PulseEffect(trigger: model.pulse))
    }

    private var header: some View {
        HStack(spacing: 8) {
            StateDot(model: model)
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(model.backend.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(KestrelPalette.blue.opacity(0.18), in: Capsule())
                .foregroundStyle(.secondary)
        }
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

/// Solid when idle, breathing while recording, spinning while busy.
private struct StateDot: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        ZStack {
            if model.state.isBusy {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 10, height: 10)
            } else {
                Circle()
                    .fill(model.accent)
                    .frame(width: 9, height: 9)
                    .scaleEffect(model.isRecording ? 1.0 + 0.35 * model.levelPhase : 1)
                    .animation(.easeInOut(duration: 0.6), value: model.levelPhase)
            }
        }
        .frame(width: 12, height: 12)
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
