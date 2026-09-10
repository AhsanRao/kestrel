import AppKit

/// Opens the settings window, and optionally photographs it — the same trade as the other probes.
/// `KESTREL_PREVIEW_SETTINGS` takes a tab name: `basics`, `voice` or `advanced`.
enum SettingsPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_SETTINGS"] != nil
    }

    @MainActor private static var window: SettingsWindow?

    @MainActor
    static func run() {
        let settings = SettingsWindow()
        settings.show()
        window = settings

        PreviewCapture.shoot(after: PreviewCapture.delay(default: 2.0),
                             PreviewCapture.around(settings.window))
    }
}
