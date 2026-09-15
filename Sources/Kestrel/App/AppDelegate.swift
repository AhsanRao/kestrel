import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "app")
    private let coordinator = SessionCoordinator()
    private var statusMenu: StatusMenu?
    private var settingsWindow: SettingsWindow?
    private var onboardingWindow: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try Paths.bootstrap()
        } catch {
            log.error("could not create ~/.kestrel: \(error.localizedDescription, privacy: .public)")
        }
        ConfigStore.shared.start()
        MemoryStore.bootstrap()
        SkillLibrary.bootstrap()
        LaunchAtLogin.sync(with: ConfigStore.shared.current.launchAtLogin)
        SystemSpeaker.requestPersonalVoice()

        let menu = StatusMenu()
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onCheckDependencies = { [weak self] in self?.showDependencyReport() }
        menu.onOpenOnboarding = { [weak self] in self?.showOnboarding() }
        menu.install()
        statusMenu = menu
        coordinator.onStateChange = { [weak menu] state in menu?.show(state: state) }

        coordinator.start()
        log.info("Kestrel ready")


        // `KESTREL_PREVIEW_APPEARANCE=light|dark` pins the appearance, so a preview can be
        // photographed in the theme it is being judged for rather than the one this Mac is set to.
        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }

        if MenuPreview.isRequested {
            MenuPreview.run(on: menu)
            return
        }

        if ActionProbe.isRequested {
            ActionProbe.run(on: coordinator)
            return
        }

        if OverlayPreview.isRequested {
            OverlayPreview.run(on: coordinator)
            return
        }

        if OnboardingPreview.isRequested {
            OnboardingPreview.run()
            return
        }

        if SettingsPreview.isRequested {
            SettingsPreview.run()
            return
        }

        if let tarballs = SpeechPreview.installTarballs {
            SpeechPreview.runInstall(tarballs)
            return
        }

        if SpeechPreview.isDownloadRequested {
            SpeechPreview.runDownload()
            return
        }

        if SpeechPreview.isRequested {
            SpeechPreview.run(on: coordinator)
            return
        }

        if PanelPreview.isRequested {
            PanelPreview.run(on: coordinator.panel)
            return
        }

        // First launch, or something it needs has gone missing since.
        if OnboardingModel.shouldPresentOnLaunch(config: ConfigStore.shared.current) {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    @MainActor
    func showOnboarding() {
        if onboardingWindow == nil { onboardingWindow = OnboardingWindow() }
        onboardingWindow?.show()
    }

    @MainActor
    func showSettings() {
        if settingsWindow == nil {
            let settings = SettingsWindow()
            settings.onOpenSetup = { [weak self] in self?.showOnboarding() }
            settings.onCheckInstalled = { [weak self] in self?.showDependencyReport() }
            settingsWindow = settings
        }
        settingsWindow?.show()
    }

    /// Runs the same checks as `scripts/check-deps.sh` and shows them in an alert.
    func showDependencyReport() {
        NSApp.activate(ignoringOtherApps: true)
        let report = DependencyCheck.run(config: ConfigStore.shared.current)
        let alert = NSAlert()
        alert.messageText = report.allGood ? "All dependencies found" : "Some dependencies are missing"
        alert.informativeText = report.summary
        alert.alertStyle = report.allGood ? .informational : .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
