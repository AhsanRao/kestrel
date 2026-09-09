import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

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

        guard let path = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"] else { return }
        let delay = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_DELAY"].flatMap(Double.init) ?? 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: URL(fileURLWithPath: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    /// Same trade as the other probes: the deprecated call is the one that works from a terminal.
    private static func capture(to url: URL) {
        guard let image = CGWindowListCreateImage(
            .infinite, .optionAll, kCGNullWindowID, [.bestResolution]),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
