import SwiftUI

/// What the floating panel shows. Mutated only on the main thread by `SessionCoordinator`.
final class PanelModel: ObservableObject {
    @Published var state: SessionState = .idle
    @Published var transcript: String = ""
    @Published var answer: String = ""
    @Published var backend: BackendKind = .claude
    @Published var askHint: String = "⌃⌥Space"
    @Published var dictateHint: String = "⌃⌥D"
    @Published var permissionURL: URL?
    @Published var pulse: Int = 0
    @Published var isHovering: Bool = false
    @Published var levelPhase: Double = 0

    var label: String {
        switch state {
        case .idle: return "Ready"
        case .listening: return "Listening…"
        case .dictating: return "Dictating…"
        case .transcribing: return "Transcribing…"
        case .thinking: return "Thinking…"
        case .answering: return "Answer"
        case .injecting: return "Pasting…"
        case .error(let message): return message
        }
    }

    var accent: Color {
        switch state {
        case .idle: return KestrelPalette.idle
        case .listening, .dictating: return KestrelPalette.cyan
        case .transcribing, .thinking, .injecting: return KestrelPalette.blue
        case .answering: return KestrelPalette.cream
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
    static let cream = Color(red: 0.961, green: 0.945, blue: 0.910)
    static let coral = Color(red: 0.847, green: 0.353, blue: 0.188)
    static let idle = Color.secondary
}
