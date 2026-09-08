import SwiftUI

/// First-run checklist: every permission and tool Kestrel needs, what each is for, and a button
/// that asks for it. Re-checks itself while open, so granting something in System Settings ticks
/// the row without the user coming back to press anything.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onFinish: () -> Void

    /// The checklist first, then the four questions that seed the memory file. In that order
    /// because the permissions are what stop Kestrel working at all, and a profile is worth
    /// nothing if the microphone is still off.
    @StateObject private var interview = InterviewModel()
    @State private var showsInterview = false

    var body: some View {
        if showsInterview {
            OnboardingInterview(model: interview, onDone: onFinish)
        } else {
            checklist
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    section("Permissions", [.microphone, .screenRecording, .accessibility])
                    section("Tools", [.speech, .whisperBinary, .whisperModel, .claude, .codex])
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 600)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.readyToUse)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Set up Kestrel")
                .font(.system(size: 19, weight: .semibold))
            Text("Hold ⌃⌥ and ask about your screen. Kestrel needs a few things first — nothing "
                 + "leaves this Mac except the question you ask and one screenshot.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            progress
        }
        .padding(18)
    }

    /// Fills as rows tick over, so the window shows how much is left at a glance.
    private var progress: some View {
        let done = model.report.items.filter(\.ok).count
        let total = model.report.items.count
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(model.readyToUse ? Color.green : KestrelPalette.cyan)
                        .frame(width: geometry.size.width * CGFloat(done) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 4)
            Text("\(done) of \(total) ready")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: done)
    }

    private func section(_ title: String, _ requirements: [DependencyCheck.Requirement]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(Array(requirements.enumerated()), id: \.element) { index, requirement in
                if let item = model.report.item(requirement) {
                    OnboardingRow(item: item, model: model)
                        .modifier(StaggeredEntrance(delay: Double(index) * 0.045))
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
            Button(model.readyToUse ? "Next" : "Skip for now") {
                model.stopPolling()
                showsInterview = true
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}
