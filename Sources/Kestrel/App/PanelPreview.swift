import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Shows the panel with sample content, and optionally photographs it.
///
/// Only runs when `KESTREL_PREVIEW_PANEL` is set, so it can never surprise a user. It exists
/// because the panel is a real window with real materials and a real shadow: an offscreen SwiftUI
/// render cannot show whether its edges are right, and that is exactly the class of bug this
/// catches.
enum PanelPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_PANEL"] != nil
    }

    /// Where to write a PNG of the window, if asked.
    private static var outputPath: String? {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"]
    }

    /// A plain backdrop behind the panel, because a black island on a black desktop tells you
    /// nothing about its edges — and its edges are the entire design. `KESTREL_PREVIEW_BACKDROP`
    /// takes `light` or `grid`.
    private static var backdrop: NSWindow?

    private static func showBackdrop() {
        guard let kind = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_BACKDROP"],
              let screen = NSScreen.main else { return }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: true)
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = NSView(frame: screen.frame)
        view.wantsLayer = true
        view.layer?.backgroundColor = kind == "grid"
            ? NSColor.systemTeal.withAlphaComponent(0.85).cgColor
            : NSColor.white.cgColor
        window.contentView = view
        window.orderFrontRegardless()
        backdrop = window
    }

    static func run(on panel: PanelWindow) {
        showBackdrop()
        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_STATE"] ?? "answer" {
        case "listening":
            panel.model.state = .listening
            panel.model.level = 0.78
        case "error":
            panel.model.state = .error("whisper-cli not found — run: brew install whisper-cpp")
        case "draft":
            panel.model.state = .answering
            panel.model.transcript = "Write a reply saying I can't make Thursday."
            panel.model.answer = "Here's a reply you can send."
            panel.model.draft = Draft(
                subject: "Re: Thursday's review",
                body: "Hi Sam,\n\nThursday won't work on my end — I'm out with the team until "
                    + "late afternoon. Friday morning is clear if that suits, otherwise any time "
                    + "Monday.\n\nSorry for the shuffle.\n\nAsh")
        case "thinking":
            panel.model.state = .thinking
            panel.model.transcript = "How do I export this as a PDF?"
        default:
            panel.model.state = .answering
            panel.model.transcript = "What is this window for?"
            panel.model.answer = "That's Xcode's build settings. The tabs across the top switch "
                + "between targets, and the search box filters every setting by name."
        }
        panel.model.askHint = "⌃⌥"
        panel.model.dictateHint = "⌃⌘K"
        // Lifted before the window is composited: flipping it moments before the shot is too late,
        // the exclusion is baked into how the window server has already drawn it.
        panel.show()
        panel.setExcludedFromCapture(false)

        FileHandle.standardError.write(Data("preview: panel \(panel.screenFrame.map(String.init(describing:)) ?? "nil") visible=\(panel.isVisible) screens=\(NSScreen.screens.map(\.frame))\n".utf8))
        guard let path = outputPath else { return }
        // After the entrance animation has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            capture(panel, to: URL(fileURLWithPath: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
        }
    }

    /// Photographs the screen where the panel sits, rather than the window on its own.
    ///
    /// A window captured in isolation comes back blank: the panel's background is a vibrancy
    /// material, which samples whatever is behind it, and in isolation there is nothing to sample.
    /// The composited screen is also the only thing that shows the shadow and the edges — which is
    /// the whole reason for taking the picture.
    private static func capture(_ panel: PanelWindow, to url: URL) {
        guard panel.screenFrame != nil else { return }
        // The whole screen: cropping to the panel's frame proved fiddly to get right in flipped
        // coordinates, and the surrounding desktop is useful context for judging the edges anyway.
        //
        // Deprecated in macOS 14, and kept anyway. The replacement, ScreenCaptureKit, is async and
        // wants the main run loop — which this blocks. `/usr/sbin/screencapture`, which ScreenGrabber
        // uses for real captures, is worse here: as a subprocess its Screen Recording grant is
        // judged against whatever launched Kestrel, so it fails from a terminal, which is precisely
        // where this tool is run from. One warning in debug-only code is the cheaper trade.
        guard let image = CGWindowListCreateImage(
            .infinite, .optionAll, kCGNullWindowID, [.bestResolution]) else { return }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
