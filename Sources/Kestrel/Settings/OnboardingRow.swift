import SwiftUI

/// One checklist line: status, name, what it is for, and the button that fixes it.
struct OnboardingRow: View {
    let item: DependencyCheck.Item
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 16))
                .foregroundStyle(item.ok ? Color.green : (item.requirement.isRequired ? KestrelPalette.coral : .secondary))
                .frame(width: 22)
                // A tick that lands with a small bounce is the whole reward for granting a
                // permission in another app and coming back.
                .scaleEffect(item.ok ? 1 : 0.9)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: item.ok)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    if !item.requirement.isRequired {
                        Text("optional")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.requirement.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.ok {
                    Text(item.detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)
            if !item.ok { action }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var symbol: String {
        item.requirement.isRequired ? "exclamationmark.circle.fill" : "circle"
    }

    @ViewBuilder
    private var action: some View {
        VStack(spacing: 5) {
            Button(actionTitle) { model.request(item.requirement) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            if isPermission {
                Button("Open Settings") { model.openSettings(for: item.requirement) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var isPermission: Bool {
        [.microphone, .screenRecording, .accessibility].contains(item.requirement)
    }

    private var actionTitle: String { isPermission ? "Allow" : "Copy command" }
}

/// Rows arrive one after another instead of all at once, which turns a wall of requirements into
/// a list the eye reads top to bottom.
struct StaggeredEntrance: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}
