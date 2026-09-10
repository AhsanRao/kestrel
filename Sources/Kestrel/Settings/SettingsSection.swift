import SwiftUI

/// The settings window's left-hand list: nine short pages rather than three long ones, so finding
/// a setting is reading a list of names instead of scrolling three.
enum SettingsSection: String, CaseIterable, Identifiable {
    case brain, shortcuts, seeing, typing, voice, hearing, memory, advanced, about

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
        case .about: return "About"
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
        case .about: return "info.circle"
        }
    }

    /// One line under the heading, in place of a paragraph taking a row inside the list.
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
        case .about: return "Which build you're on, and who made it."
        }
    }
}
