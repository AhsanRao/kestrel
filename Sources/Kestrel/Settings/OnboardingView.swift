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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch model.step {
            case .checklist:
                checklist.transition(slide(from: .leading))
            case .interview:
                OnboardingInterview(model: interview,
                                    onBack: { model.step = .checklist },
                                    onDone: onFinish)
                    .transition(slide(from: .trailing))
            }
        }
        // One size for both halves, so the step change is the window's contents moving across it
        // rather than the window itself resizing under them.
        .frame(width: 520, height: 600)
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.settle), value: model.step)
    }

    /// Each half enters and leaves by its own side, so going back retraces the way forward instead
    /// of pushing on in the same direction. Reduce Motion gets the cross-fade without the travel.
    private func slide(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    private var checklist: some View {
        let permissions = rows(.microphone, .screenRecording, .accessibility)
        let tools = rows(.speech, .whisperBinary, .whisperModel, .voice, .claude, .codex)
        return VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    section("Permissions", permissions, startingAt: 0)
                    section("Tools", tools, startingAt: permissions.count)
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.settle),
                   value: model.readyToUse)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }

    /// The rows this Mac actually has — the two whisper lines are absent on Apple's speech engine.
    /// Resolved before the list is laid out so the arrival cascade counts real rows and has no gaps
    /// where a missing one used to be.
    private func rows(_ requirements: DependencyCheck.Requirement...) -> [DependencyCheck.Item] {
        requirements.compactMap { model.report.item($0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            OnboardingHeading(step: 1, title: "Set up Kestrel")
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.progress), value: done)
    }

    /// `startingAt` continues the cascade from where the section above it left off, so the whole
    /// checklist reads top to bottom as one list rather than two arriving side by side.
    private func section(_ title: String, _ items: [DependencyCheck.Item],
                         startingAt offset: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.element.requirement) { index, item in
                OnboardingRow(item: item, model: model)
                    .modifier(StaggeredEntrance(
                        delay: Double(offset + index) * OnboardingMotion.stagger))
                // Nothing after the last row: the next section's heading is the break.
                if index < items.count - 1 {
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
                    .foregroundStyle(model.readyToUse ? Color.green : .secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            // One label, because it is one action: the footer text beside it is what says whether
            // anything is being left behind.
            Button("Continue") {
                model.stopPolling()
                model.step = .interview
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }
}

/// A step's number and name, shared by both halves so they read as one window moving on.
struct OnboardingHeading: View {
    let step: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STEP \(step) OF 2")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 19, weight: .semibold))
        }
    }
}
