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
