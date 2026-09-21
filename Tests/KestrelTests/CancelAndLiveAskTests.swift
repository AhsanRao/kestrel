import XCTest
@testable import Kestrel

/// What Esc and a held chord do to the loop: a phrase heard mid-hold is a question, a cancel
/// belongs to the run it interrupted, and a stale result never lands on the next question.
final class CancelAndLiveAskTests: XCTestCase {
    func testAPhraseHeardMidHoldStartsTheQuestionWithoutARelease() {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        XCTAssertEqual(machine.apply(.phraseHeard), [])
        XCTAssertEqual(machine.state, .transcribing(.ask))
        machine.apply(.transcribed(.ask))
        XCTAssertEqual(machine.state, .thinking)
        // The chord coming up now is not a second question.
        XCTAssertEqual(machine.apply(.askReleased), [.pulse])
        XCTAssertEqual(machine.state, .thinking)
    }

    func testTheNextPhraseFollowsAnAnswerAnErrorOrNothing() {
        for start in [SessionEvent.answered, .failed("x")] {
            var machine = SessionMachine(state: .thinking)
            machine.apply(start)
            XCTAssertEqual(machine.apply(.phraseHeard), [.clearOverlay, .interruptSpeech])
            XCTAssertEqual(machine.state, .transcribing(.ask))
        }
        var idle = SessionMachine()
        XCTAssertEqual(idle.apply(.phraseHeard), [])
        XCTAssertEqual(idle.state, .transcribing(.ask))
    }

    func testACancelBelongsToTheRunItInterrupted() throws {
        let runner = CLIRunner()
        runner.cancel()
        // Before the fix this threw CancellationError forever after: one Esc, no model ever again.
        let result = try runner.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["ok"],
                                    cwd: URL(fileURLWithPath: "/tmp"), timeout: 5)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }

    func testAGenerationBumpMakesEarlierWorkStale() {
        let coordinator = SessionCoordinator()
        let first = coordinator.beginGeneration()
        XCTAssertTrue(coordinator.isCurrent(first))
        coordinator.cancelSession()          // idle: only the marks; no bump
        XCTAssertTrue(coordinator.isCurrent(first))
        let second = coordinator.beginGeneration()
        XCTAssertFalse(coordinator.isCurrent(first))
        XCTAssertTrue(coordinator.isCurrent(second))
    }

    func testAskSilenceIsClamped() throws {
        let config = try XCTUnwrap(ConfigStore.decode(Data(#"{"askSilenceSeconds":0.1,"liveAsk":false}"#.utf8)))
        XCTAssertEqual(config.askSilenceSeconds, 0.5)
        XCTAssertFalse(config.liveAsk)
        XCTAssertTrue(Config.defaults.liveAsk)
    }
}
