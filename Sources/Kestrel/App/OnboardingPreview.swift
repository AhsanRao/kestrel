import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Opens the setup window, and optionally photographs it. `KESTREL_PREVIEW_ONBOARDING=download`
/// also starts the voice download — the only way to see the progress meter without pressing it —
/// and `=interview` opens on the second step.
enum OnboardingPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_ONBOARDING"] != nil
    }

    @MainActor private static var window: OnboardingWindow?

    @MainActor
    static func run() {
        let onboarding = OnboardingWindow()
        onboarding.show()
        window = onboarding

        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_ONBOARDING"] {
        case "download": onboarding.model.voiceDownloader.start()
        case "interview": onboarding.model.step = .interview
        default: break
        }

        guard let path = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"] else { return }
        let delay = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_DELAY"].flatMap(Double.init) ?? 3.0
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
