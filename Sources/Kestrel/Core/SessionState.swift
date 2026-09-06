import Foundation

enum SessionIntent: String, Equatable { case ask, dictation }

/// Spec §5.4. Only one session runs at a time; hotkeys pressed while busy are refused with a
/// panel pulse rather than queued.
enum SessionState: Equatable {
    case idle
    case listening
    case dictating
    case transcribing(SessionIntent)
    case thinking
    case answering
    case injecting
    /// A walkthrough is drawn on screen and waiting for the user to click the current target.
    case guiding
    /// Kestrel is performing actions on the user's behalf.
    case acting
    case error(String)

    var isBusy: Bool {
        switch self {
        case .transcribing, .thinking, .injecting: return true
        default: return false
        }
    }
}

enum SessionEvent: Equatable {
    case askPressed
    case askReleased
    case dictateToggled
    case transcribed(SessionIntent)
    case transcriptionEmpty
    case answered
    case injected
    case walkthroughReady
    case walkthroughAdvanced
    case walkthroughFinished
    case actionsReady
    case actionsFinished
    case failed(String)
    case autoHideElapsed
    case cancelled
}

/// Side effects the coordinator must perform after a transition. The machine itself is pure so it
/// can be unit-tested without audio, subprocesses or windows.
enum SessionEffect: Equatable {
    case startListening
    case finishListening      // screenshot first, then stop audio and transcribe
    case startDictating
    case finishDictating
    case interruptSpeech
    case pulse                // busy: refuse the input, nudge the panel
    case clearOverlay
    case reset
}

struct SessionMachine {
    private(set) var state: SessionState = .idle

    @discardableResult
    mutating func apply(_ event: SessionEvent) -> [SessionEffect] {
        switch (state, event) {
        // Guiding is handled first: leaving it must always take the drawing off the screen.
        case (.guiding, .walkthroughAdvanced):
            return []

        case (.guiding, .walkthroughFinished), (.guiding, .cancelled):
            state = .idle
            return [.clearOverlay, .reset]

        case (.guiding, .failed(let message)):
            state = .error(message)
            return [.clearOverlay]

        case (.guiding, .askPressed):
            state = .listening
            return [.clearOverlay, .interruptSpeech, .startListening]

        case (.guiding, .dictateToggled):
            state = .dictating
            return [.clearOverlay, .interruptSpeech, .startDictating]

        case (.thinking, .walkthroughReady):
            state = .guiding
            return []

        case (.thinking, .actionsReady):
            state = .acting
            return []

        case (.acting, .actionsFinished), (.acting, .cancelled):
            state = .idle
            return [.clearOverlay, .reset]

        case (.acting, .failed(let message)):
            state = .error(message)
            return [.clearOverlay]

        // A run is stopped with Esc, not by asking something else half way through it.
        case (.acting, .askPressed), (.acting, .dictateToggled):
            return [.pulse]

        case (_, .failed(let message)):
            state = .error(message)
            return [.interruptSpeech]

        case (_, .cancelled):
            state = .idle
            return [.reset]

        case (.idle, .askPressed), (.error, .askPressed):
            state = .listening
            return [.startListening]

        case (.answering, .askPressed):
            state = .listening
            return [.interruptSpeech, .startListening]

        case (.listening, .askReleased):
            state = .transcribing(.ask)
            return [.finishListening]

        case (.idle, .dictateToggled), (.error, .dictateToggled):
            state = .dictating
            return [.startDictating]

        case (.answering, .dictateToggled):
            state = .dictating
            return [.interruptSpeech, .startDictating]

        case (.dictating, .dictateToggled):
            state = .transcribing(.dictation)
            return [.finishDictating]

        case (.transcribing(.ask), .transcribed(.ask)):
            state = .thinking
            return []

        case (.transcribing(.dictation), .transcribed(.dictation)):
            state = .injecting
            return []

        case (.transcribing, .transcriptionEmpty):
            state = .error("Didn't catch that")
            return []

        case (.thinking, .answered):
            state = .answering
            return []

        case (.injecting, .injected):
            state = .idle
            return [.reset]

        case (.answering, .autoHideElapsed), (.error, .autoHideElapsed):
            state = .idle
            return [.reset]

        // A press that arrives mid-flight, or the wrong hotkey for the running session.
        case (.listening, .dictateToggled), (.dictating, .askPressed),
             (.transcribing, _), (.thinking, _), (.injecting, _):
            return [.pulse]

        default:
            return []
        }
    }
}
