import SwiftUI

/// The settings window's left-hand list.
///
/// Eight small pages rather than three long ones. Three tabs meant every page was a scroll, and a
/// scroll is where a setting goes to be lost — the user has to remember which of three lists a
/// thing was in and then hunt down it. A named page each means the sidebar itself is the index.
enum SettingsSection: String, CaseIterable, Identifiable {
    case brain, shortcuts, seeing, typing, voice, hearing, memory, advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brain: return "Brain"
        case .shortcuts: return "Shortcuts"
        case .seeing: return "Seeing"
        case .typing: return "Typing"
        case .voice: return "My voice"
        case .hearing: return "Hearing you"
        case .memory: return "Memory"
        case .advanced: return "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .brain: return "brain"
        case .shortcuts: return "command"
        case .seeing: return "viewfinder"
        case .typing: return "text.cursor"
        case .voice: return "speaker.wave.2"
        case .hearing: return "waveform"
        case .memory: return "book.closed"
        case .advanced: return "gearshape.2"
        }
    }

    /// One line under the heading, saying what the page is for. It replaces the paragraph that used
    /// to sit inside the list and take a row of its own.
    var caption: String {
        switch self {
        case .brain: return "Which assistant answers you, and on which model."
        case .shortcuts: return "The two keys, and whether I start with your Mac."
        case .seeing: return "What I capture when you ask, and how I point things out."
        case .typing: return "How dictated text gets into the app you're in."
        case .voice: return "Whether I speak, and what I sound like."
        case .hearing: return "How your voice becomes text. All of it on this Mac."
        case .memory: return "What I read before every answer."
        case .advanced: return "The island's timings, keys, and where it all lives."
        }
    }
}
