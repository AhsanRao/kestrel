import SwiftUI

/// Setup, five steps, one thing at a time.
///
/// The shell owns everything that does not change between steps — the glass, the rail across the
/// top, the footer and its one primary action — so a step only has to say what it is for. That is
/// also what makes the movement between them read as one window rather than five.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    var onFinish: () -> Void

    @StateObject private var interview = InterviewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepRail(current: model.step)
                .padding(.horizontal, 26)
                .padding(.top, 40)
                .padding(.bottom, 22)

            // Scrolls only when a step runs long — the ready step with four things outstanding is
            // the tall one — so nothing is ever cut off at a fixed window height.
            ScrollView {
                content.padding(.bottom, 8)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        // One size for every step: a window that resizes as the content changes turns a step
        // change into two movements, and only one of them is the one being asked for.
        .frame(width: 540, height: 580)
        .ignoresSafeArea(edges: .top)
        .background(GlassBackground().ignoresSafeArea())
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.settle), value: model.step)
    }

    @ViewBuilder private var content: some View {
        ZStack(alignment: .top) {
            switch model.step {
            case .welcome:
                WelcomeStep().transition(step)
            case .voice:
                VoiceStep(model: model).transition(step)
            case .permissions:
                PermissionsStep(model: model).transition(step)
            case .profile:
                ProfileStep(model: interview).transition(step)
            case .ready:
                ReadyStep(model: model).transition(step)
            }
        }
    }

    /// Forward moves left, back moves right, so a step returns along the path it left by. Reduce
    /// Motion gets the cross-fade with none of the travel.
    private var step: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let forward = !model.isGoingBack
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if model.step.previous != nil {
                Button("Back") { model.goBack() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Spacer()
            Text(aside)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome: return "Let's go"
        case .ready: return "Start using Kestrel"
        default: return "Continue"
        }
    }

    /// The quiet line next to the button, for what the button is not saying.
    private var aside: String {
        switch model.step {
        case .voice: return KokoroInstall.isReady ? "" : "You can decide this later"
        case .permissions: return model.readyToUse ? "" : "You can sort the rest out later"
        case .profile: return interview.isEmpty ? "Nothing here is required" : ""
        default: return ""
        }
    }

    private func primaryAction() {
        if model.step == .profile { interview.save() }
        guard model.step != .ready else { return onFinish() }
        model.advance()
    }
}

/// Where the user is, and how much is left. Five stops, the ones behind filled in.
private struct StepRail: View {
    let current: OnboardingModel.Step

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.self) { step in
                let done = step.rawValue < current.rawValue
                VStack(spacing: 6) {
                    Capsule()
                        .fill(done || step == current ? KestrelPalette.cyan : Color.secondary.opacity(0.22))
                        .frame(height: 3)
                    Text(step.title)
                        .font(.system(size: 10, weight: step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                .opacity(step == current || done ? 1 : 0.6)
            }
        }
        .animation(OnboardingMotion.honoring(reduceMotion, OnboardingMotion.progress), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of 5: \(current.title)")
    }
}
