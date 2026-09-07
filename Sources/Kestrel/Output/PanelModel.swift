import SwiftUI

/// What the floating panel shows. Mutated only on the main thread by `SessionCoordinator`.
final class PanelModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var transcript: String = ""
    @Published var answer: String = ""
    @Published var backend: BackendKind = .claude
    @Published var askHint: String = "⌃⌘A"
    @Published var dictateHint: String = "⌃⌘K"
    @Published var permissionURL: URL?
    @Published var pulse: Int = 0
    @Published var isHovering: Bool = false
    /// This question continues the previous one rather than starting fresh.
    @Published var isFollowUp: Bool = false
    /// Live input level, 0…1, while recording.
    @Published var level: Double = 0
    @Published var levelPhase: Double = 0
    /// The notch on the screen the panel is about to appear on. Set by `PanelWindow` before it
    /// positions itself, so the view can lay its content out around the camera housing.
    @Published var notch: NotchMetrics = .none

    /// Told when the island's own size changes, so the window can follow it. Set by `PanelWindow`.
    var onSizeChange: ((CGSize) -> Void)?

    /// Collapsed, the island is a bar around the notch; it opens only once there is something to
    /// read. A transcript alone counts: that is the question being heard back.
    var isExpanded: Bool {
        !answer.isEmpty || !transcript.isEmpty || isError
    }

    /// The island's width in each of its two sizes. Always wider than the housing, so the housing
    /// has no corner poking out from behind it.
    var width: CGFloat {
        let clearance = notch.notchSize.width + 280
        return isExpanded ? max(clearance, 470) : max(clearance, 330)
    }

    /// What the notch row says. Short by construction: it shares a 32-point strip with the camera
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
        case .answering: return "Answer"
        case .injecting: return "Pasting"
        case .guiding: return "Follow along"
        case .acting: return "Working"
        case .error(let message): return message
        }
    }

    var accent: Color {
        switch state {
        case .idle: return KestrelPalette.idle
        case .listening, .dictating: return KestrelPalette.cyan
        case .transcribing, .thinking, .injecting, .acting: return KestrelPalette.sky
        // The island is black, so the logo's navy-leaning blue disappears into it; the same hue
        // lifted to where it reads against black.
        case .answering, .guiding: return KestrelPalette.sky
        case .error: return KestrelPalette.coral
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

/// Taken from the shipped logo (`assets/kestrel-logo.svg`): deep navy body, cyan waveform.
/// The spec's §15 table described a cream/amber concept that the final artwork replaced.
enum KestrelPalette {
    static let navy = Color(red: 0.059, green: 0.125, blue: 0.220)
    static let cyan = Color(red: 0.165, green: 0.941, blue: 0.855)
    static let blue = Color(red: 0.180, green: 0.361, blue: 0.541)
    /// The same blue, lifted for use on black.
    static let sky = Color(red: 0.404, green: 0.667, blue: 0.949)
    static let cream = Color(red: 0.961, green: 0.945, blue: 0.910)
    static let coral = Color(red: 0.847, green: 0.353, blue: 0.188)
    static let idle = Color.secondary
}
