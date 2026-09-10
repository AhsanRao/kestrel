import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

/// State behind the first-run window: what is missing, and how to ask for each thing.
@MainActor
final class OnboardingModel: ObservableObject {
    /// Setup, one purpose at a time. Order matters: the voice download is long and runs in the
    /// background, so it is started before the permissions rather than after them — by the time
    /// the last switch is flipped it has usually finished on its own.
    enum Step: Int, CaseIterable {
        case welcome, voice, permissions, profile, ready

        /// What the rail calls it. One word where one word will do.
        var title: String {
            switch self {
            case .welcome: return "Hello"
            case .voice: return "Voice"
            case .permissions: return "Access"
            case .profile: return "You"
            case .ready: return "Ready"
            }
        }

        var next: Step? { Step(rawValue: rawValue + 1) }
        var previous: Step? { Step(rawValue: rawValue - 1) }
    }

    @Published private(set) var report: DependencyCheck.Report
    @Published var relaunchNeeded = false
    /// Which step is on screen. Here rather than in the view so reopening the window starts at the
    /// beginning instead of resuming wherever the user happened to leave it.
    @Published var step: Step = .welcome
    /// Which way the last move went, so a step leaves by the side it would have come back from.
    @Published private(set) var isGoingBack = false

    /// Owned here so a download survives the row being redrawn.
    let voiceDownloader = KokoroDownloader()

    /// Requirements the user has already pressed the button on. Drives the second, quieter way in:
    /// macOS shows its permission prompt once ever, so "Open Settings" is only worth the space once
    /// asking has visibly failed to do anything.
    @Published private(set) var asked: Set<DependencyCheck.Requirement> = []

    private var pollTimer: Timer?
    private let sounds = SoundBoard()
    /// The checks stat files and walk PATH. Off the main thread, because they run every 1.5s under
    /// a window that is animating.
    private let checks = DispatchQueue(label: "dev.0xash.kestrel.dependency-check", qos: .utility)

    init() {
        report = DependencyCheck.run(config: ConfigStore.shared.current)
    }

    var readyToUse: Bool { report.readyToUse }

    /// Only the three macOS grants. The rest of the report is tools, which are somebody else's
    /// installer and belong on the last step with everything else still outstanding.
    var permissions: [DependencyCheck.Item] {
        [.microphone, .screenRecording, .accessibility].compactMap { report.item($0) }
    }

    /// Everything that is not a macOS permission: the CLIs, the speech engine, the voice.
    var tools: [DependencyCheck.Item] {
        report.items.filter { ![.microphone, .screenRecording, .accessibility].contains($0.requirement) }
    }

    var unfinishedTools: [DependencyCheck.Item] { tools.filter { !$0.ok } }

    func go(to step: Step) {
        isGoingBack = step.rawValue < self.step.rawValue
        self.step = step
    }

    func advance() {
        guard let next = step.next else { return }
        go(to: next)
    }

    func goBack() {
        guard let previous = step.previous else { return }
        go(to: previous)
    }

    /// Permissions are granted in System Settings, outside this app, so the window keeps looking.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        let config = ConfigStore.shared.current
        checks.async { [weak self] in
            let fresh = DependencyCheck.run(config: config)
            Task { @MainActor in self?.apply(fresh, config: config) }
        }
    }

    private func apply(_ fresh: DependencyCheck.Report, config: Config) {
        guard fresh.items.map(\.ok) != report.items.map(\.ok) else { return }
        let wasReady = report.readyToUse
        let hadScreenRecording = granted(.screenRecording, in: report)
        report = fresh
        // Screen Recording reads as granted the moment it is given, but this process cannot capture
        // anything until it is restarted — so the notice belongs to the grant landing, not to the
        // button being pressed. Pressed and then ignored, nothing needs restarting.
        if !hadScreenRecording, granted(.screenRecording, in: fresh) { relaunchNeeded = true }
        // The last permission landing is the one moment in setup worth a sound. The row that ticked
        // is usually in another window's Settings pane, where the user cannot see it happen.
        if !wasReady, fresh.readyToUse { sounds.play(.ready, config: config) }
    }

    private func granted(_ requirement: DependencyCheck.Requirement,
                         in report: DependencyCheck.Report) -> Bool {
        report.item(requirement)?.ok ?? false
    }

    // MARK: - Actions

    /// Asks macOS for the permission, which shows the system prompt the first time only. After
    /// that the switch has to be flipped by hand, so the pane is opened instead.
    func request(_ requirement: DependencyCheck.Requirement) {
        asked.insert(requirement)
        switch requirement {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(for: requirement) }
        case .accessibility:
            TextInjector.requestAccessibilityPermission()
        default:
            if let command = DependencyCheck.fixCommand(for: requirement) { copy(command) }
        }
        refresh()
    }

    func openSettings(for requirement: DependencyCheck.Requirement) {
        let pane: String?
        switch requirement {
        case .microphone: pane = "Privacy_Microphone"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        case .accessibility: pane = "Privacy_Accessibility"
        default: pane = nil
        }
        guard let pane, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// A real answer, not a postponement — switching engines lets the row tick and setup finish.
    func skipKokoro() {
        ConfigStore.shared.update { $0.voiceEngine = .system }
        refresh()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Screen Recording only takes effect in a fresh process.
    func relaunch() {
        let bundle = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundle, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func markCompleted() {
        ConfigStore.shared.update { $0.onboardingCompleted = true }
    }

    /// Shown on launch until the required pieces are in place, and never again after that.
    static func shouldPresentOnLaunch(config: Config) -> Bool {
        shouldPresent(config: config, report: DependencyCheck.run(config: config))
    }

    /// Split out so the rule can be tested without depending on this Mac's real permissions.
    nonisolated static func shouldPresent(config: Config, report: DependencyCheck.Report) -> Bool {
        !config.onboardingCompleted || !report.readyToUse
    }
}
