import SwiftUI

/// One checklist line: status, name, what it is for, and the button that fixes it.
struct OnboardingRow: View {
    let item: DependencyCheck.Item
    @ObservedObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 16))
                .foregroundStyle(item.ok ? KestrelPalette.success
                                         : (item.isRequired ? KestrelPalette.danger : .secondary))
                .frame(width: 22)
                // A tick that lands with a small bounce is the whole reward for granting a
                // permission in another app and coming back.
                .scaleEffect(item.ok ? 1 : 0.9)
                .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.tick), value: item.ok)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    if !item.isRequired {
                        Text("optional")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(KestrelPalette.track, in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(item.requirement.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.ok {
                    Text(item.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }

            Spacer(minLength: 8)
            if !item.ok {
                action.transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        // The row closes up around the tick as its hint and buttons go, rather than snapping to
        // the shorter height under them.
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.settle), value: item.ok)
    }

    private var symbol: String {
        item.isRequired ? "exclamationmark.circle.fill" : "circle"
    }

    @ViewBuilder
    private var action: some View {
        if item.requirement == .voice {
            KokoroRowAction(downloader: model.voiceDownloader, model: model)
        } else {
            permissionOrCommand
        }
    }

    @ViewBuilder
    private var permissionOrCommand: some View {
        VStack(spacing: 5) {
            Button(actionTitle) { press() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            // macOS puts up its own prompt the first time and never again, so the pane is the way
            // in from then on — but offering both at once asks the user to choose between two
            // buttons for one thing before either has been tried.
            if isPermission, model.asked.contains(item.requirement) {
                Button("Open Settings") { model.openSettings(for: item.requirement) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.settle),
                   value: model.asked.contains(item.requirement))
    }

    /// The command lands on the clipboard with nothing to show for it, so the button that was just
    /// pressed says so itself — the same confirmation a copied draft gets.
    private func press() {
        model.request(item.requirement)
        guard !isPermission else { return }
        withAnimation(OnboardingMotion.honoring(reduceMotion, .easeOut(duration: 0.15))) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(OnboardingMotion.honoring(reduceMotion, .easeOut(duration: 0.2))) {
                copied = false
            }
        }
    }

    private var isPermission: Bool {
        [.microphone, .screenRecording, .accessibility].contains(item.requirement)
    }

    private var actionTitle: String {
        if isPermission { return "Allow" }
        return copied ? "Copied" : "Copy command"
    }
}
