import XCTest
@testable import Kestrel

final class SessionStateTests: XCTestCase {
    func testAskHappyPath() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.apply(.askPressed), [.startListening])
        XCTAssertEqual(machine.state, .listening)
        XCTAssertEqual(machine.apply(.askReleased), [.finishListening])
        XCTAssertEqual(machine.state, .transcribing(.ask))
        XCTAssertEqual(machine.apply(.transcribed(.ask)), [])
        XCTAssertEqual(machine.state, .thinking)
        XCTAssertEqual(machine.apply(.answered), [])
        XCTAssertEqual(machine.state, .answering)
        XCTAssertEqual(machine.apply(.autoHideElapsed), [.reset])
        XCTAssertEqual(machine.state, .idle)
    }

    func testDictationHappyPath() {
        var machine = SessionMachine()
        XCTAssertEqual(machine.apply(.dictateToggled), [.startDictating])
        XCTAssertEqual(machine.state, .dictating)
        XCTAssertEqual(machine.apply(.dictateToggled), [.finishDictating])
        XCTAssertEqual(machine.state, .transcribing(.dictation))
        XCTAssertEqual(machine.apply(.transcribed(.dictation)), [])
        XCTAssertEqual(machine.state, .injecting)
        XCTAssertEqual(machine.apply(.injected), [.reset])
        XCTAssertEqual(machine.state, .idle)
    }

    func testAskWhileAnsweringStopsSpeechAndListensAgain() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)
        machine.apply(.transcribed(.ask))
        machine.apply(.answered)
        XCTAssertEqual(machine.apply(.askPressed), [.clearOverlay, .interruptSpeech, .startListening])
        XCTAssertEqual(machine.state, .listening)
    }

    func testAConfirmationIsAskedAndAnsweredWithinTheModelsTurn() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)
        machine.apply(.transcribed(.ask))            // thinking: the model has the question
        XCTAssertEqual(machine.apply(.confirmationNeeded("delete a file")), [])
        XCTAssertEqual(machine.state, .confirming("delete a file"))
        // The ask hotkey now means "yes": a press starts recording it, release decides.
        XCTAssertEqual(machine.apply(.askPressed), [.startConfirming])
        XCTAssertEqual(machine.apply(.askReleased), [.finishConfirming])
        XCTAssertEqual(machine.apply(.confirmed), [])
        XCTAssertEqual(machine.state, .thinking, "back to the model's turn, whatever the answer")
    }

    func testADeclineReturnsToThinkingToo() {
        var machine = SessionMachine(state: .confirming("send an email"))
        XCTAssertEqual(machine.apply(.declined), [])
        XCTAssertEqual(machine.state, .thinking)
    }

    func testDictationCannotInterruptAConfirmation() {
        var machine = SessionMachine(state: .confirming("delete a file"))
        XCTAssertEqual(machine.apply(.dictateToggled), [.pulse])
        XCTAssertEqual(machine.state, .confirming("delete a file"))
    }

    func testHotkeyWhileBusyIsRefusedWithAPulse() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)          // now transcribing
        XCTAssertEqual(machine.apply(.askPressed), [.pulse])
        XCTAssertEqual(machine.state, .transcribing(.ask))
        machine.apply(.transcribed(.ask))    // now thinking
        XCTAssertEqual(machine.apply(.dictateToggled), [.pulse])
        XCTAssertEqual(machine.state, .thinking)
    }

    func testListeningAndDictatingAreMutuallyExclusive() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        XCTAssertEqual(machine.apply(.dictateToggled), [.pulse])
        XCTAssertEqual(machine.state, .listening)

        var other = SessionMachine()
        other.apply(.dictateToggled)
        XCTAssertEqual(other.apply(.askPressed), [.pulse])
        XCTAssertEqual(other.state, .dictating)
    }

    func testEmptyTranscriptBecomesAReadableError() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)
        machine.apply(.transcriptionEmpty)
        XCTAssertEqual(machine.state, .error("Didn't catch that"))
        XCTAssertEqual(machine.apply(.askPressed), [.startListening])
    }

    func testFailureFromAnyStateEndsInError() {
        for event in [SessionEvent.askPressed, .dictateToggled] {
            var machine = SessionMachine()
            machine.apply(event)
            machine.apply(.failed("boom"))
            XCTAssertEqual(machine.state, .error("boom"))
            XCTAssertEqual(machine.apply(.autoHideElapsed), [.reset])
            XCTAssertEqual(machine.state, .idle)
        }
    }

    // MARK: - Taking the marks off the screen

    private func machineShowingAnAnswer() -> SessionMachine {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)
        machine.apply(.transcribed(.ask))
        machine.apply(.answered)
        return machine
    }

    func testAnAnswerLandsInAnswering() {
        XCTAssertEqual(machineShowingAnAnswer().state, .answering)
    }

    /// The marks are the only thing Kestrel leaves drawn on the screen, so Esc has to reach them.
    func testEscapeTakesTheMarksOffTheScreen() {
        var machine = machineShowingAnAnswer()
        XCTAssertEqual(machine.apply(.cancelled), [.clearOverlay, .interruptSpeech, .reset])
        XCTAssertEqual(machine.state, .idle)
    }

    /// Asking again while the last answer is still marked: the old marks must go first, or they
    /// sit over the screen the new question is about.
    func testAskingAgainClearsTheOldMarks() {
        var machine = machineShowingAnAnswer()
        XCTAssertEqual(machine.apply(.askPressed), [.clearOverlay, .interruptSpeech, .startListening])
        XCTAssertEqual(machine.state, .listening)
    }

    func testDictatingClearsTheOldMarks() {
        var machine = machineShowingAnAnswer()
        XCTAssertEqual(machine.apply(.dictateToggled), [.clearOverlay, .interruptSpeech, .startDictating])
        XCTAssertEqual(machine.state, .dictating)
    }

    /// Cancelling always takes the marks off too. Nothing is drawn this early, so clearing is a
    /// no-op here — but it is the one path every abandoned session goes through, and marks left on
    /// the screen after the user has walked away is the failure worth being blunt about.
    func testTooShortPressCancelsBackToIdle() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        XCTAssertEqual(machine.apply(.cancelled), [.clearOverlay, .interruptSpeech, .reset])
        XCTAssertEqual(machine.state, .idle)
    }
}
