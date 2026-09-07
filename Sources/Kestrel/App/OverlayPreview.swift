import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Puts the drawing on screen with made-up targets, and optionally photographs it.
///
/// The marks are strokes that animate onto a live screen; nothing about whether they land in the
/// right place, or read as drawn rather than pasted, survives an offscreen render. Runs only when
/// `KESTREL_PREVIEW_OVERLAY` is set, like the panel preview beside it.
enum OverlayPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OVERLAY"] != nil
    }

    static func run(on coordinator: SessionCoordinator) {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        // Two plausible targets: a menu bar item, and a button in the middle of a window.
        let menu = CGRect(x: screen.minX + 120, y: screen.maxY - 34, width: 44, height: 22)
        let button = CGRect(x: screen.midX - 60, y: screen.midY, width: 132, height: 30)

        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OVERLAY"] {
        case "live":
            // The one that can actually catch a mark landing in the wrong place: real controls,
            // read out of whatever app is in front, drawn where Kestrel thinks they are. Every
            // other mode uses made-up frames and so agrees with itself by construction.
            // Optionally bring a known-good app forward first, so the probe is not at the mercy of
            // whatever happened to be in front.
            if let bundleID = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_APP"],
               let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: app, configuration: configuration,
                                                   completionHandler: nil)
                Thread.sleep(forTimeInterval: 2.0)
            }
            let elements = AXElementScanner.scanFrontmostApp(menuDepth: AXElementScanner.deepMenuDepth)
            let chosen = Array(elements.filter { $0.frame.width > 24 && $0.frame.height > 12 }.prefix(4))
            var report = ["accessibility trusted: \(AXElementScanner.isAvailable)",
                          "elements: \(elements.count)",
                          "screens: " + NSScreen.screens.map { "\($0.frame)" }.joined(separator: " "),
                          "desktop: \(OverlayModel.desktopBounds)",
                          "frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")"]
            report += chosen.map { "  \($0.label) role=\($0.role) frame=\($0.frame)" }
            FileHandle.standardError.write(Data((report.joined(separator: "\n") + "\n").utf8))
            coordinator.annotations.show(chosen.map {
                Annotation(frame: $0.frame, caption: $0.label,
                           shape: $0.frame.width / max($0.frame.height, 1) > 2.2 ? .rect : .circle)
            })
        case "calibrate":
            // Landmarks at known global AppKit points. If the mapping is right, "bottom left" is
            // drawn at the bottom left. Nothing here depends on Accessibility, so it isolates the
            // screen-to-overlay conversion from everything that feeds it.
            let inset: CGFloat = 40
            let box = CGSize(width: 180, height: 70)
            coordinator.annotations.show([
                Annotation(frame: CGRect(x: screen.minX + inset, y: screen.minY + inset,
                                         width: box.width, height: box.height),
                           caption: "bottom left", shape: .rect),
                Annotation(frame: CGRect(x: screen.maxX - inset - box.width,
                                         y: screen.maxY - inset - box.height,
                                         width: box.width, height: box.height),
                           caption: "top right", shape: .rect),
                Annotation(frame: CGRect(x: screen.midX - box.width / 2, y: screen.midY - box.height / 2,
                                         width: box.width, height: box.height),
                           caption: "centre", shape: .rect),
            ])
        case "annotation":
            coordinator.annotations.show([
                Annotation(frame: button, caption: "Export as PDF", shape: .rect),
                Annotation(frame: menu, caption: "File", shape: .circle),
            ])
        default:
            let walkthrough = Walkthrough(goal: "Export as PDF", steps: [
                WalkthroughStep(n: 1, instruction: "Click the File menu", label: "File"),
                WalkthroughStep(n: 2, instruction: "Choose Export as PDF", label: "Export as PDF…"),
            ], needs_more: false)
            coordinator.overlay.model.frames = [menu, button]
            coordinator.overlay.model.steps = walkthrough.steps
            coordinator.overlay.model.goal = walkthrough.goal
            coordinator.overlay.model.index = 0
            coordinator.overlay.show()
        }

        // Lifted before the windows are composited, exactly as the panel preview must do it.
        coordinator.overlay.setExcludedFromCapture(false)
        coordinator.annotations.setExcludedFromCapture(false)

        guard let path = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"] else { return }
        // Long enough for the strokes to finish by default; `KESTREL_PREVIEW_DELAY` catches the
        // cursor mid-draw, which is the only way to see whether it is riding the stroke at all.
        let delay = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_DELAY"].flatMap(Double.init) ?? 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            capture(to: URL(fileURLWithPath: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    /// Same trade as `PanelPreview`: the deprecated call is the one that works from a terminal,
    /// where this is run from.
    private static func capture(to url: URL) {
        guard let image = CGWindowListCreateImage(
            .infinite, .optionAll, kCGNullWindowID, [.bestResolution]),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
