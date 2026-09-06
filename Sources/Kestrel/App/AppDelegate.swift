import AppKit
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "app")
    private let coordinator = SessionCoordinator()
    private var statusMenu: StatusMenu?
    private var settingsWindow: SettingsWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try Paths.bootstrap()
        } catch {
            log.error("could not create ~/.kestrel: \(error.localizedDescription, privacy: .public)")
        }
        ConfigStore.shared.start()
        MemoryStore.bootstrap()
        LaunchAtLogin.sync(with: ConfigStore.shared.current.launchAtLogin)

        let menu = StatusMenu()
        menu.onOpenSettings = { [weak self] in self?.showSettings() }
        menu.onCheckDependencies = { [weak self] in self?.showDependencyReport() }
        menu.install()
        statusMenu = menu

        coordinator.start()
        log.info("Kestrel ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow() }
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
