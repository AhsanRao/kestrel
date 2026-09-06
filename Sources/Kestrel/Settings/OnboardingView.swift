import SwiftUI

/// First-run checklist: every permission and tool Kestrel needs, what each is for, and a button
/// that asks for it. Re-checks itself while open, so granting something in System Settings ticks
/// the row without the user coming back to press anything.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    section("Permissions", [.microphone, .screenRecording, .accessibility])
                    section("Tools", [.whisperBinary, .whisperModel, .claude, .codex])
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 560)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Set up Kestrel")
                .font(.system(size: 19, weight: .semibold))
            Text("Hold ⌃⌘A and ask about your screen. Kestrel needs a few things first — nothing "
                 + "leaves this Mac except the question you ask and one screenshot.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private func section(_ title: String, _ requirements: [DependencyCheck.Requirement]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(requirements, id: \.self) { requirement in
                if let item = model.report.item(requirement) {
                    OnboardingRow(item: item, model: model)
                    Divider().padding(.leading, 46)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.relaunchNeeded {
                Label("Screen Recording applies after a restart", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("Relaunch") { model.relaunch() }
            } else {
                Text(model.readyToUse ? "Everything Kestrel needs is in place."
                                      : "You can start now and finish the rest later.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.readyToUse ? "Start using Kestrel" : "Skip for now") { onFinish() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// One checklist line: status, name, what it is for, and the button that fixes it.
private struct OnboardingRow: View {
    let item: DependencyCheck.Item
    @ObservedObject var model: OnboardingModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 16))
                .foregroundStyle(item.ok ? Color.green : (item.requirement.isRequired ? KestrelPalette.coral : .secondary))
                .frame(width: 22)

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
