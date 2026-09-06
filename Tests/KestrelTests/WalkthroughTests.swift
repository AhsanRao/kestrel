import XCTest
@testable import Kestrel

final class WalkthroughParserTests: XCTestCase {
    private let valid = #"""
    {"goal":"Export as PDF","needs_more":false,"steps":[
      {"n":1,"instruction":"Open the File menu","target":{"x":12,"y":8,"w":52,"h":22},"shape":"rect"},
      {"n":2,"instruction":"Choose Export","target":{"x":30,"y":180,"w":160,"h":26},"shape":"rect"}]}
    """#

    func testParsesTheHappyCase() throws {
        let walkthrough = try XCTUnwrap(WalkthroughParser.parse(valid))
        XCTAssertEqual(walkthrough.goal, "Export as PDF")
        XCTAssertEqual(walkthrough.steps.map(\.instruction), ["Open the File menu", "Choose Export"])
    }

    func testParsesThroughCodeFences() throws {
        let fenced = "```json\n" + valid + "\n```"
        XCTAssertEqual(WalkthroughParser.parse(fenced)?.steps.count, 2)
    }

    func testParsesWhenTheModelAddsProse() throws {
        let chatty = "Sure, here are the steps.\n\(valid)\nLet me know if that helps."
        XCTAssertEqual(WalkthroughParser.parse(chatty)?.steps.count, 2)
    }

    func testRejectsMalformedJSONInsteadOfCrashing() {
        XCTAssertNil(WalkthroughParser.parse("{\"goal\": \"broken\", \"steps\": ["))
        XCTAssertNil(WalkthroughParser.parse("no json at all"))
        XCTAssertNil(WalkthroughParser.parse(""))
    }

    func testRejectsAnEnvelopeWithNoUsableSteps() {
        XCTAssertNil(WalkthroughParser.parse(#"{"goal":"x","steps":[]}"#))
        XCTAssertNil(WalkthroughParser.parse(
            #"{"goal":"x","steps":[{"n":1,"instruction":"","target":{"x":0,"y":0,"w":10,"h":10},"shape":"rect"}]}"#))
        XCTAssertNil(WalkthroughParser.parse(
            #"{"goal":"x","steps":[{"n":1,"instruction":"go","target":{"x":0,"y":0,"w":0,"h":0},"shape":"rect"}]}"#))
    }

    func testStringsInsideJSONDoNotConfuseTheBraceScanner() throws {
        let tricky = #"{"goal":"Say \"hi\" {maybe}","steps":[{"n":1,"instruction":"Click OK","target":{"x":1,"y":1,"w":9,"h":9},"shape":"circle"}]}"#
        let walkthrough = try XCTUnwrap(WalkthroughParser.parse(tricky))
        XCTAssertEqual(walkthrough.goal, #"Say "hi" {maybe}"#)
        XCTAssertEqual(walkthrough.steps[0].shape, "circle")
    }

    func testStepsAreRenumberedAndCapped() {
        let steps = (1...20).map {
            WalkthroughStep(n: 99 - $0, instruction: "step \($0)",
                            target: .init(x: 0, y: 0, w: 10, h: 10), shape: "RECT")
        }
        let sanitized = WalkthroughParser.sanitize(steps)
        XCTAssertEqual(sanitized.count, WalkthroughParser.maximumSteps)
        XCTAssertEqual(sanitized.map(\.n), Array(1...15))
        XCTAssertEqual(sanitized[0].shape, "rect")
    }

    func testUnknownShapeFallsBackToRect() {
        let steps = [WalkthroughStep(n: 1, instruction: "x", target: .init(x: 0, y: 0, w: 5, h: 5), shape: "blob")]
        XCTAssertEqual(WalkthroughParser.sanitize(steps)[0].shape, "rect")
    }

    func testSpokenSummaryNumbersTheSteps() throws {
        let walkthrough = try XCTUnwrap(WalkthroughParser.parse(valid))
        let summary = WalkthroughParser.spokenSummary(walkthrough)
        XCTAssertTrue(summary.hasPrefix("Export as PDF"))
        XCTAssertTrue(summary.contains("1. Open the File menu"))
        XCTAssertTrue(summary.contains("2. Choose Export"))
    }

    func testTheDeclaredImageGridIsCarriedThrough() throws {
        let json = #"{"goal":"x","image":{"w":320,"h":208},"steps":[{"n":1,"instruction":"Click Print","target":{"x":104,"y":22,"w":30,"h":14},"shape":"rect"}]}"#
        let walkthrough = try XCTUnwrap(WalkthroughParser.parse(json))
        XCTAssertEqual(walkthrough.space, Walkthrough.ImageSize(w: 320, h: 208))
    }

    func testSpokenSummaryFlagsAnIncompleteWalkthrough() {
        var walkthrough = Walkthrough(goal: "Sign in", steps: [
            WalkthroughStep(n: 1, instruction: "Click Account", target: .init(x: 0, y: 0, w: 4, h: 4)),
        ], needs_more: true)
        XCTAssertTrue(WalkthroughParser.spokenSummary(walkthrough).contains("more steps"))
        walkthrough.needs_more = false
        XCTAssertFalse(WalkthroughParser.spokenSummary(walkthrough).contains("more steps"))
    }
}

final class WalkthroughDetectorTests: XCTestCase {
    func testShowMeQuestionsWantAWalkthrough() {
        for question in ["How do I export as PDF in this app?",
                         "how can i change the theme",
                         "Show me how to add a new sheet",
                         "walk me through publishing this",
                         "Where do I find the settings?"] {
            XCTAssertTrue(WalkthroughDetector.wantsWalkthrough(question, config: .defaults), question)
        }
    }

    func testPlainQuestionsDoNot() {
        for question in ["What app is this?",
                         "Summarise this page",
                         "Is there an error in this code?",
                         "What does this button do?"] {
            XCTAssertFalse(WalkthroughDetector.wantsWalkthrough(question, config: .defaults), question)
        }
    }

    func testTheFeatureCanBeTurnedOff() {
        var config = Config.defaults
        config.walkthroughs = false
        XCTAssertFalse(WalkthroughDetector.wantsWalkthrough("How do I export as PDF?", config: config))
    }
}
