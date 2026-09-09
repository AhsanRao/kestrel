import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

/// State behind the first-run window: what is still missing, and how to ask for each thing.
///
/// Main-actor isolated: it drives SwiftUI directly, and it owns the voice downloader, which
/// publishes its progress from the main thread.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var report: DependencyCheck.Report
    @Published var relaunchNeeded = false

    /// Owned here rather than by the row so a download survives the row being redrawn.
    let voiceDownloader = KokoroDownloader()

    private var pollTimer: Timer?

    init() {
        report = DependencyCheck.run(config: ConfigStore.shared.current)
    }

    var readyToUse: Bool { report.readyToUse }

    /// Permissions are granted in System Settings, outside this app, so the window keeps looking.
    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() {
        let fresh = DependencyCheck.run(config: ConfigStore.shared.current)
        guard fresh.items.map(\.ok) != report.items.map(\.ok) else { return }
        report = fresh
    }

    // MARK: - Actions

    /// Asks macOS for the permission, which shows the system prompt the first time only. After
    /// that the switch has to be flipped by hand, so the pane is opened instead.
    func request(_ requirement: DependencyCheck.Requirement) {
        switch requirement {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(for: requirement) }
            relaunchNeeded = true
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

    /// Declining the download is a real answer, not a postponement: the config is switched to the
    /// macOS voices so the row can tick and the checklist can finish.
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
    static func shouldPresent(config: Config, report: DependencyCheck.Report) -> Bool {
        !config.onboardingCompleted || !report.readyToUse
    }
}
