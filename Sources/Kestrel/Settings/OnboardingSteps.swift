import SwiftUI

/// A step's title and its one line of explanation. Every step opens the same way, so moving
/// between them changes the words and nothing else.
struct StepHeading: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                // Large text reads too loose at its default tracking; headings tighten as they grow.
                .tracking(-0.5)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Step one. What Kestrel is, in the time it takes to read one screen.
struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeading(title: "Hey — I'm Kestrel.",
                        detail: "Hold ⌃⌥, ask about whatever's on your screen, and I'll answer out "
                              + "loud. Let go and I'm gone again.")
            VStack(alignment: .leading, spacing: 12) {
                point("waveform", "Ask out loud", "Your voice becomes text right here on this Mac.")
                point("sparkle.magnifyingglass", "I can see your screen",
                      "One screenshot per question, only while you're holding the key.")
                point("hand.point.up.left", "And point at things",
                      "When the answer is \"that button there\", I'll circle it for you.")
                point("lock", "Nothing leaves this Mac",
                      "Except your question and that one screenshot, to your own Claude account.")
            }
            .padding(16)
            .glassPanel()
        }
        .padding(.horizontal, 26)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(KestrelPalette.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Step two. The voice download, started here so it runs while the permissions are being granted.
struct VoiceStep: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject private var downloader: KokoroDownloader

    init(model: OnboardingModel) {
        self.model = model
        self.downloader = model.voiceDownloader
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeading(title: "Pick my voice",
                        detail: "I sound far better through a neural voice that runs on this Mac "
                              + "than through anything macOS ships. It's a 370 MB download, once.")
            VStack(alignment: .leading, spacing: 14) {
                if let item = model.report.item(.voice), item.ok {
                    Label(KokoroInstall.isReady ? "Downloaded — I'm using it."
                                                : "Using a macOS voice. That works too.",
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                } else {
                    KokoroRowAction(downloader: downloader, model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("It keeps downloading while you carry on — no need to wait here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .glassPanel()
        }
        .padding(.horizontal, 26)
    }
}

/// Step three. The three macOS grants, and nothing else.
struct PermissionsStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeading(title: "Three things I need",
                        detail: "macOS keeps these behind a switch until you say otherwise. "
                              + "Here's what each one is actually for.")
            VStack(spacing: 0) {
                ForEach(Array(model.permissions.enumerated()), id: \.element.requirement) { index, item in
                    OnboardingRow(item: item, model: model)
                        .modifier(StaggeredEntrance(delay: Double(index) * OnboardingMotion.stagger))
                    if index < model.permissions.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .glassPanel()
        }
        .padding(.horizontal, 26)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

/// Step four. Four questions that become the memory file.
struct ProfileStep: View {
    @ObservedObject var model: InterviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeading(title: "Tell me a little about you",
                        detail: "This goes in a file on your Mac that I read before every answer. "
                              + "Leave out anything you'd rather not say.")
            OnboardingInterview(model: model)
                .padding(16)
                .glassPanel()
        }
        .padding(.horizontal, 26)
    }
}

/// Step five. Either everything is in place, or here is what is not.
struct ReadyStep: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeading(title: model.readyToUse ? "That's us — ready." : "Good enough to start.",
                        detail: model.readyToUse
                            ? "Hold ⌃⌥ anywhere and ask me something. I'm in the menu bar when you need me."
                            : "You can use me now. The rest is waiting whenever you want it.")
            if model.unfinishedTools.isEmpty {
                HotkeyCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("STILL TO SORT OUT")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                    ForEach(Array(model.unfinishedTools.enumerated()), id: \.element.requirement) { index, item in
                        OnboardingRow(item: item, model: model)
                        if index < model.unfinishedTools.count - 1 {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .glassPanel()
            }
            if model.relaunchNeeded {
                HStack(spacing: 8) {
                    Label("Screen Recording needs me restarted before it takes effect",
                          systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Restart") { model.relaunch() }
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 26)
        .onAppear { model.startPolling() }
        .onDisappear { model.stopPolling() }
    }
}

/// The two keys worth remembering, on the screen the user leaves setup from.
private struct HotkeyCard: View {
    var body: some View {
        let config = ConfigStore.shared.current
        return VStack(alignment: .leading, spacing: 12) {
            row(config.hotkeys.ask.display, "Hold it, ask, let go.")
            Divider()
            row(config.hotkeys.dictate.display, "Tap it and talk — I'll type it wherever you are.")
        }
        .padding(16)
        .glassPanel()
    }

    private func row(_ keys: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Text(keys)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7,
                                                                              style: .continuous))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}
