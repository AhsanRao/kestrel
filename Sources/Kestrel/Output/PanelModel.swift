import SwiftUI

/// What the floating panel shows. Mutated only on the main thread by `SessionCoordinator`.
final class PanelModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var transcript: String = ""
    @Published var answer: String = ""
    @Published var backend: BackendKind = .claude
    @Published var askHint: String = "⌘⌥"
    @Published var permissionURL: URL?
    /// A piece of writing the user asked for — an email, a reply, a paragraph. Shown with a copy
    /// button instead of being read out, because the only thing anyone does with a draft is take it
    /// somewhere else.
    @Published var draft: Draft?
    @Published var pulse: Int = 0
    @Published var isHovering: Bool = false
    /// This question continues the previous one rather than starting fresh.
    @Published var isFollowUp: Bool = false
    /// "Let me have a look" — said and shown while the model is still thinking, replaced by the
    /// answer the moment the first sentence of it arrives.
    @Published var aside: String?
    /// Live input level, 0…1, while recording.
    @Published var level: Double = 0
    /// The steps taken so far while acting — "Opened Safari", "Clicked Send" — so what Kestrel
    /// is doing to the screen can be seen as it happens, not only in the log afterwards.
    @Published var steps: [String] = []
    /// The notch on the screen the panel is about to appear on. Set by `PanelWindow` before it
    /// positions itself, so the view can lay its content out around the camera housing.
    @Published var notch: NotchMetrics = .none

    /// Told when the island's own size changes, so the window can follow it. Set by `PanelWindow`.
    var onSizeChange: ((CGSize) -> Void)?

    /// Collapsed, the island is a bar around the notch; it opens only once there is something to
    /// read. A transcript alone counts: that is the question being heard back.
    var isExpanded: Bool {
        !answer.isEmpty || !transcript.isEmpty || isError || draft != nil || aside != nil || !steps.isEmpty
    }

    /// The island's width in each of its two sizes. Always wider than the housing, so the housing
    /// has no corner poking out from behind it, and no wider than the words in it need: this sits
    /// over the user's own screen, and every point of it covers something they were looking at.
    ///
    /// The floor is set by the longest state label. Each shoulder gets half of whatever is left
    /// once the housing is taken out, and of that, 30 points go to the inset (`PanelView.inset`)
    /// and 24 to the indicator and its gap — so against a 179-point housing a shoulder of 130
    /// leaves 76 for the word. Measured at the font the row uses, `.system(12, .semibold)`,
    /// "Transcribing" is 73.8 points wide and every other label is under 55, so the longest one
    /// clears by two points at full size. Taking 30 points off this is what cut it to "Transcribin…".
    var width: CGFloat {
        let clearance = notch.notchSize.width + 260
        return isExpanded ? max(clearance, 420) : max(clearance, 300)
    }

    /// What the notch row says. Short by construction: it shares a notch-tall strip with the camera
    /// housing, and an error message that runs across the housing is worse than no message.
    var headline: String {
        isError ? "Kestrel" : label
    }

    /// The error itself, which belongs in the opened half where it has room to wrap.
    var detail: String? {
        if case .error(let message) = state { return message }
        return nil
    }

    var label: String {
        switch state {
        // No trailing ellipses: the island is narrow, the indicator beside the word already says
        // that something is in progress, and "Transcribing…" is three characters of nothing.
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .dictating: return "Dictating"
        case .transcribing: return "Transcribing"
        case .thinking: return "Thinking"
        case .confirming: return "Your call"
        case .answering: return "Answer"
        case .injecting: return "Pasting"
        case .error(let message): return message
        }
    }

    var accent: Color {
        switch state {
        case .idle: return KestrelPalette.idle
        case .listening, .dictating: return KestrelPalette.accentOnDark
        case .transcribing, .thinking, .injecting: return KestrelPalette.sky
        // A question back to the user, in the colour that means "talk to me".
        case .confirming: return KestrelPalette.accentOnDark
        // The island is black, so the logo's navy-leaning blue disappears into it; the same hue
        // lifted to where it reads against black.
        case .answering: return KestrelPalette.sky
        case .error: return KestrelPalette.dangerOnDark
        }
    }

    var isError: Bool { if case .error = state { return true }; return false }
    var isRecording: Bool {
        switch state {
        case .listening, .dictating: return true
        default: return false
        }
    }
}
