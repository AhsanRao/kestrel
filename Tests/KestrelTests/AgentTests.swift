import XCTest
@testable import Kestrel

/// Telling the two apart matters more than usual: one branch answers a question, the other touches
/// the user's Mac. When it is ambiguous, answering is the cheap mistake.
final class AgentDetectorTests: XCTestCase {
    func testInstructionsAreActedOn() {
        for instruction in ["open Slack", "click the Export button", "send the reply",
                            "set the title to Quarterly", "archive this thread",
                            "please open the settings", "turn on dark mode"] {
            XCTAssertTrue(AgentDetector.wantsAction(instruction, config: .defaults), instruction)
        }
    }

    func testQuestionsAreAnswered() {
        for question in ["how do I open Slack?", "how do i send this", "what is this button?",
                         "where is the export option", "what does send do",
                         "can you explain the archive button"] {
            XCTAssertFalse(AgentDetector.wantsAction(question, config: .defaults), question)
        }
    }

    func testAnythingEndingInAQuestionMarkIsAQuestion() {
        XCTAssertFalse(AgentDetector.wantsAction("open Slack?", config: .defaults))
    }

    func testDescriptionsAreNotInstructions() {
        for text in ["this window looks wrong", "the button is greyed out",
                     "there is an error at the top"] {
            XCTAssertFalse(AgentDetector.wantsAction(text, config: .defaults), text)
        }
    }

    func testActingCanBeTurnedOffEntirely() {
        var config = Config.defaults
        config.agentActions = false
        XCTAssertFalse(AgentDetector.wantsAction("open Slack", config: config))
    }

    func testEmptySpeechDoesNothing() {
        XCTAssertFalse(AgentDetector.wantsAction("   ", config: .defaults))
    }
}

final class ActionPlanParserTests: XCTestCase {
    private let valid = #"""
    {"goal":"Export as PDF","needs_more":false,"actions":[
      {"kind":"press","element":4,"describe":"Click the File menu"},
      {"kind":"setValue","element":9,"value":"Report","describe":"Type the file name"}]}
    """#

    func testAPlanParses() throws {
        let plan = try XCTUnwrap(ActionPlanParser.parse(valid))
        XCTAssertEqual(plan.goal, "Export as PDF")
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertEqual(plan.actions[1].value, "Report")
    }

    func testFencesAndProseAreTolerated() {
        XCTAssertEqual(ActionPlanParser.parse("Sure!\n```json\n\(valid)\n```\nDone.")?.actions.count, 2)
    }

    func testMalformedOutputIsRefusedRatherThanGuessed() {
        XCTAssertNil(ActionPlanParser.parse("{\"goal\":"))
        XCTAssertNil(ActionPlanParser.parse("I'll click the File menu for you"))
    }

    func testStepsPointingAtNothingAreDropped() {
        let json = #"""
        {"goal":"x","actions":[
          {"kind":"press","describe":"Click something"},
          {"kind":"setValue","element":2,"describe":"Type"},
          {"kind":"launchApp","describe":"Open it"},
          {"kind":"press","element":3,"describe":""}]}
        """#
        XCTAssertEqual(ActionPlanParser.parse(json)?.actions.count, 0)
    }

    func testLaunchNeedsABundleIdButNoElement() {
        let json = #"{"goal":"x","actions":[{"kind":"launchApp","value":"com.apple.Safari","describe":"Open Safari"}]}"#
        XCTAssertEqual(ActionPlanParser.parse(json)?.actions.count, 1)
    }

    func testAPlanIsCappedAtParseTime() {
        let actions = (1...30).map { #"{"kind":"press","element":\#($0),"describe":"Step \#($0)"}"# }
        let json = #"{"goal":"x","actions":[\#(actions.joined(separator: ","))]}"#
        XCTAssertEqual(ActionPlanParser.parse(json)?.actions.count, ActionPlan.maximumActions)
    }

    func testAnEmptyPlanCarriesItsReason() throws {
        let plan = try XCTUnwrap(ActionPlanParser.parse(#"{"goal":"That control isn't on this screen","actions":[]}"#))
        XCTAssertTrue(plan.actions.isEmpty)
        XCTAssertEqual(plan.goal, "That control isn't on this screen")
    }

    func testAnUnknownKindIsRejectedRatherThanRun() {
        XCTAssertNil(ActionPlanParser.parse(#"{"goal":"x","actions":[{"kind":"formatDisk","element":1,"describe":"Format"}]}"#))
    }
}

/// The acting state has to behave like the others: interruptible only in the ways that are safe.
final class ActingStateTests: XCTestCase {
    private func acting() -> SessionMachine {
        var machine = SessionMachine()
        machine.apply(.askPressed)
        machine.apply(.askReleased)
        machine.apply(.transcribed(.ask))
        machine.apply(.actionsReady)
        return machine
    }

    func testAPlanMovesFromThinkingToActing() {
        XCTAssertEqual(acting().state, .acting)
    }

    func testFinishingClearsTheOverlay() {
        var machine = acting()
        XCTAssertEqual(machine.apply(.actionsFinished), [.clearOverlay, .reset])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeStopsARunAndClearsUp() {
        var machine = acting()
        XCTAssertEqual(machine.apply(.cancelled), [.clearOverlay, .reset])
    }

    func testAHotkeyDoesNotInterruptARunMidWay() {
        var machine = acting()
        XCTAssertEqual(machine.apply(.askPressed), [.pulse])
        XCTAssertEqual(machine.state, .acting, "a run is stopped with Esc, not by talking over it")
    }

    func testAFailureDuringARunSurfacesAndClearsUp() {
        var machine = acting()
        XCTAssertEqual(machine.apply(.failed("could not press Send")), [.clearOverlay])
        XCTAssertEqual(machine.state, .error("could not press Send"))
    }
}
