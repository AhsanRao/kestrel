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
    /// The model wants to do something irreversible and Kestrel has asked. The hotkey now means
    /// "yes" — a tap, or a hold with the word in it — and stays live until the answer comes.
    case confirming(String)
    case answering
    case injecting
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
    case confirmationNeeded(String)
    case confirmed
    case declined
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
    case startConfirming      // record the yes or no
    case finishConfirming     // stop recording and decide
    case interruptSpeech
    case pulse                // busy: refuse the input, nudge the panel
    case clearOverlay
    case reset
}

struct SessionMachine {
    private(set) var state: SessionState = .idle

    /// Starts wherever it is told. For the probe that asks a typed question without a microphone.
    init(state: SessionState = .idle) { self.state = state }

    @discardableResult
    mutating func apply(_ event: SessionEvent) -> [SessionEffect] {
        switch (state, event) {
        case (_, .failed(let message)):
            state = .error(message)
            return [.interruptSpeech]

        // Esc takes off everything Kestrel has put on the screen or said out loud. The marks
        // especially: they are the only thing it leaves behind, so cancelling has to reach them.
        case (_, .cancelled):
            state = .idle
            return [.clearOverlay, .interruptSpeech, .reset]

        case (.idle, .askPressed), (.error, .askPressed):
            state = .listening
            return [.startListening]

        // A new question while the last answer's marks are still drawn: clear them first, or the
        // old marks sit over the screen the new question is about.
        case (.answering, .askPressed):
            state = .listening
            return [.clearOverlay, .interruptSpeech, .startListening]

        case (.listening, .askReleased):
            state = .transcribing(.ask)
            return [.finishListening]

        case (.idle, .dictateToggled), (.error, .dictateToggled):
            state = .dictating
            return [.startDictating]

        case (.answering, .dictateToggled):
            state = .dictating
            return [.clearOverlay, .interruptSpeech, .startDictating]

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

        // A confirmation is asked from inside the model's turn, and answered with the ask hotkey.
        case (.thinking, .confirmationNeeded(let what)):
            state = .confirming(what)
            return []

        case (.confirming, .askPressed):
            return [.startConfirming]

        case (.confirming, .askReleased):
            return [.finishConfirming]

        case (.confirming, .confirmed), (.confirming, .declined):
            state = .thinking
            return []

        case (.injecting, .injected):
            state = .idle
            return [.reset]

        case (.answering, .autoHideElapsed), (.error, .autoHideElapsed):
            state = .idle
            return [.reset]

        // A press that arrives mid-flight, or the wrong hotkey for the running session.
        case (.listening, .dictateToggled), (.dictating, .askPressed), (.confirming, .dictateToggled),
             (.transcribing, _), (.thinking, _), (.injecting, _):
            return [.pulse]

        default:
            return []
        }
    }
}
