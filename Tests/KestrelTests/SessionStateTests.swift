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
        XCTAssertEqual(machine.apply(.askPressed), [.interruptSpeech, .startListening])
        XCTAssertEqual(machine.state, .listening)
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

    func testTooShortPressCancelsBackToIdle() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        XCTAssertEqual(machine.apply(.cancelled), [.reset])
        XCTAssertEqual(machine.state, .idle)
    }
}
