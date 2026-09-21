import AppKit

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
            ? NSColor(hex: KestrelPalette.Brand.teal).withAlphaComponent(0.85).cgColor
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
        case "thinking":
            // The gap the acknowledgement fills: the question is heard, the answer is not here yet.
            panel.model.state = .thinking
            panel.model.transcript = "What's going on with this build error?"
            panel.model.aside = Acknowledgement.line(for: "what's wrong with this build")
        case "error":
            panel.model.state = .error("I can't find whisper-cli. Run: brew install whisper-cpp")
        case "draft":
            panel.model.state = .answering
            panel.model.transcript = "Write a reply saying I can't make Thursday."
            panel.model.answer = "Here's a reply you can send."
            panel.model.draft = Draft(
                subject: "Re: Thursday's review",
                body: "Hi Sam,\n\nThursday won't work on my end — I'm out with the team until "
                    + "late afternoon. Friday morning is clear if that suits, otherwise any time "
                    + "Monday.\n\nSorry for the shuffle.\n\nAsh")
        case "stream":
            // Sentence by sentence, the way an answer really arrives — the case the frame spring
            // exists for, and the only way to see it retarget mid-movement.
            panel.model.state = .answering
            panel.model.transcript = "What is this window for?"
            let sentences = [
                "That's Xcode's build settings.",
                "The tabs across the top switch between targets.",
                "The search box filters every setting by name.",
                "Levels shows where a value was actually set.",
            ]
            for (index, sentence) in sentences.enumerated() {
                // Closer together than the spring's own response, so every sentence after the
                // first lands while the window is still moving.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + Double(index) * 0.12) {
                    panel.model.answer += panel.model.answer.isEmpty ? sentence : " " + sentence
                }
            }
        case "clipped":
            // Far past the line limits, so the note about what did not fit is the thing on show.
            panel.model.state = .answering
            panel.model.transcript = "Summarise this build settings pane."
            panel.model.answer = String(repeating:
                "Build settings resolve from the target, then the project, then any xcconfig. ", count: 14)
            panel.model.draft = Draft(
                subject: "Re: the settings audit",
                body: (1...24).map { "Line \($0) of a draft that runs past what the island shows." }
                    .joined(separator: "\n"))
        default:
            panel.model.state = .answering
            panel.model.transcript = "What is this window for?"
            panel.model.answer = "That's Xcode's build settings. The tabs across the top switch "
                + "between targets, and the search box filters every setting by name."
        }
        panel.model.askHint = "⌘⌥"
        // Lifted before the window is composited: flipping it moments before the shot is too late,
        // the exclusion is baked into how the window server has already drawn it.
        panel.show()
        panel.setExcludedFromCapture(false)

        FileHandle.standardError.write(Data("preview: panel \(panel.screenFrame.map(String.init(describing:)) ?? "nil") visible=\(panel.isVisible) screens=\(NSScreen.screens.map(\.frame))\n".utf8))
        // After the entrance animation has settled. The whole screen rather than the panel's own
        // frame: the island's background is a vibrancy material, which samples what is behind it
        // and comes back blank in isolation, and the surrounding desktop is the context the
        // picture is being taken for.
        PreviewCapture.shoot(after: PreviewCapture.delay(default: 1.0)) {
            panel.screenFrame == nil ? .null : PreviewCapture.wholeScreen()
        }
    }

}
