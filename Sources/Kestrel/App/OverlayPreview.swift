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
            // Built exactly as the real pipeline builds it, or the probe answers a different
            // question than the one being asked: controls first, numbered from one, then the
            // content regions numbered on after them.
            let elements = AXElementScanner.scanFrontmostApp(menuDepth: AXElementScanner.deepMenuDepth)
            var targets = Array(elements.prefix(SessionCoordinator.maximumPointableControls))
                .map(\.asTarget)
            let screen = AXContentReader.read(startingAt: targets.count + 1)
            targets += screen.regions

            var report = ["accessibility trusted: \(AXElementScanner.isAvailable)",
                          "frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")",
                          "screens: " + NSScreen.screens.map { "\($0.frame)" }.joined(separator: " "),
                          "desktop: \(AnnotationOverlayModel.desktopBounds)",
                          "page: \(screen.url ?? "—")  document: \(screen.document ?? "—")",
                          "controls: \(elements.count)  regions: \(screen.regions.count)"
                            + "  text: \(screen.text.count) chars",
                          "",
                          "--- the numbered list the model is given ---"]
            report += targets.map { target in
                let frame = target.frame
                return "\(target.kind == .control ? "C" : "R") \(target.listing)"
                    + "  frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)))"
            }
            report += ["", "--- what the screen says ---", screen.text, ""]
            if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                report += AXCensus.report(pid: pid)
            }
            let text = report.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(text.utf8))
            // Launched with `open`, so that Accessibility is granted to the bundle rather than to
            // whatever shell started it — which means stderr goes nowhere. The report is written
            // beside the screenshot instead.
            if let out = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"] {
                try? text.write(to: URL(fileURLWithPath: out).appendingPathExtension("txt"),
                                atomically: true, encoding: .utf8)
            }

            // Draw the regions, not the controls: controls were already proven, and whether a
            // region lands on a real block of the page is the open question.
            let drawn = Array(screen.regions.prefix(3))
            coordinator.annotations.show(drawn.map {
                Annotation(frame: $0.frame, caption: $0.label.isEmpty ? $0.role : $0.label,
                           shape: $0.preferredShape, isRegion: true)
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
        case "region":
            // The case the content reader exists for: an answer about a section of a page.
            let card = CGRect(x: screen.midX - 260, y: screen.midY - 60, width: 520, height: 300)
            coordinator.annotations.show([
                Annotation(frame: card, caption: "Pricing cards", shape: .rect, isRegion: true),
            ])
        case "annotation":
            coordinator.annotations.show([
                Annotation(frame: button, caption: "Export as PDF", shape: .rect),
                Annotation(frame: menu, caption: "File", shape: .circle),
            ])
        default:
            // Two marks, drawn one after the other, which is what an ordinary answer looks like:
            // the pencil rings the first, travels, and rings the second.
            coordinator.annotations.show([
                Annotation(frame: menu, caption: "File", shape: .circle),
                Annotation(frame: button, caption: "Export as PDF", shape: .rect),
            ])
        }

        // Lifted before the windows are composited, exactly as the panel preview must do it.
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
