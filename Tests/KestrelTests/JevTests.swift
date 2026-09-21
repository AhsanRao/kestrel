import XCTest
@testable import Kestrel

final class JevTests: XCTestCase {
    func testRequestIsShapedTheWayTypeSafeReadsIt() throws {
        let data = Jev.body(model: "typesafe-ai/jev", state: "open spotify", questions: [
            "kind": .oneOf(["a": "A", "b": "B"], "Which?"),
            "sure": .yesNo("Sure?"),
            "how": JevQuestion(instructions: "How much?", kind: .score(["low", "high"])),
        ])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "typesafe-ai/jev")
        XCTAssertEqual(json["state"] as? String, "open spotify")
        let questions = try XCTUnwrap(json["questions"] as? [String: [String: Any]])
        XCTAssertEqual(questions["kind"]?["type"] as? String, "choice")
        XCTAssertEqual(questions["kind"]?["criteria"] as? [String: String], ["a": "A", "b": "B"])
        XCTAssertEqual(questions["sure"]?["type"] as? String, "noul")
        XCTAssertNil(questions["sure"]?["criteria"])
        XCTAssertEqual(questions["how"]?["criteria"] as? [String], ["low", "high"])
    }

    func testAnswersDecodeWithConfidenceAndProbability() throws {
        let answers = try JSONDecoder().decode(JevAnswers.self, from: Data(sample.utf8))
        XCTAssertEqual(answers.yes("draft"), 0.9)
        let kind = try XCTUnwrap(answers.choice("kind"))
        XCTAssertEqual(kind.option, "act")
        XCTAssertEqual(kind.confidence, 0.95)
        XCTAssertNil(answers.yes("missing"))
    }

    func testJevIsOffWithoutAKey() {
        XCTAssertFalse(Config.Jev(apiKey: nil).isEnabled)
        XCTAssertFalse(Config.Jev(apiKey: "").isEnabled)
        XCTAssertTrue(Config.Jev(apiKey: "vck_x").isEnabled)
        XCTAssertNil(Jev.ask("x", [:], config: Config.Jev(apiKey: nil)))
    }

    func testJevConfigDecodesWithDefaults() throws {
        let config = try XCTUnwrap(ConfigStore.decode(Data(#"{"jev":{"apiKey":"vck_x"}}"#.utf8)))
        XCTAssertEqual(config.jev.apiKey, "vck_x")
        XCTAssertEqual(config.jev.model, "typesafe-ai/jev")
        XCTAssertTrue(config.jev.endpoint.hasPrefix("https://ai-gateway.vercel.sh/"))
    }

    // MARK: - Triage

    func testWithoutJevTriageIsWhatTheListsSaid() {
        var config = Config.defaults
        let triage = QuestionTriage.decide("what does this button do", frontmostApp: nil,
                                           previous: nil, config: config)
        XCTAssertEqual(triage.kind, .act)   // tools on: the model decides, as before
        XCTAssertFalse(triage.wantsDraft)
        XCTAssertEqual(triage.source, "lists")
        config.agentTools = false
        XCTAssertEqual(QuestionTriage.decide("open Finder", frontmostApp: nil, previous: nil,
                                             config: config).kind, .openApp)
        XCTAssertTrue(QuestionTriage.heuristic("reply to this", config: config).wantsDraft)
    }

    func testAnUnsurePickFallsBackToTheLists() throws {
        let fallback = QuestionTriage.heuristic("what is this", config: .defaults)
        let unsure = try JSONDecoder().decode(JevAnswers.self, from: Data(
            #"{"answers":{"kind":{"type":"choice","choice":"answer","confidence":0.4}}}"#.utf8))
        XCTAssertEqual(QuestionTriage.parse(unsure, fallback: fallback, hasHistory: false)?.kind, fallback.kind)
        let sure = try JSONDecoder().decode(JevAnswers.self, from: Data(
            #"{"answers":{"kind":{"type":"choice","choice":"answer","confidence":0.9},"draft":{"type":"noul","noul":0.1}}}"#.utf8))
        XCTAssertEqual(QuestionTriage.parse(sure, fallback: fallback, hasHistory: false)?.kind, .answer)
    }

    func testALaunchWithNoKnownAppGoesToTheModel() throws {
        let fallback = QuestionTriage.heuristic("pull up my music thing", config: .defaults)
        let answers = try JSONDecoder().decode(JevAnswers.self, from: Data(
            #"{"answers":{"kind":{"type":"choice","choice":"open_app","confidence":0.9},"app":{"type":"choice","choice":"none","confidence":0.8}}}"#.utf8))
        let triage = try XCTUnwrap(QuestionTriage.parse(answers, fallback: fallback, hasHistory: false))
        XCTAssertEqual(triage.kind, .act)
        XCTAssertNil(triage.app)
    }

    func testAMacroNeedsShapeControlAndWords() throws {
        let bar = ScreenTarget(id: 7, label: "Address and search bar", role: "AXTextField",
                               frame: CGRect(x: 0, y: 0, width: 400, height: 20), kind: .control)
        let fallback = QuestionTriage.heuristic("search for owls", config: .defaults)
        func parse(shape: String, sure: Double, control: Double, text: Double, more: Double = 0.05) throws -> QuestionTriage.Macro? {
            let json = """
            {"answers":{"kind":{"type":"choice","choice":"act","confidence":0.9},
              "shape":{"type":"choice","choice":"\(shape)","confidence":\(sure)},
              "control":{"type":"choice","choice":"7","confidence":\(control)},
              "text":{"type":"choice","choice":"0","confidence":0.4,"probabilities":{"0":\(text),"none":\(1 - text)}},
              "more":{"type":"noul","noul":\(more)}}}
            """
            let answers = try JSONDecoder().decode(JevAnswers.self, from: Data(json.utf8))
            return QuestionTriage.parse(answers, fallback: fallback, hasHistory: false, controls: [bar], words: ["owls"])?.macro
        }
        XCTAssertEqual(try parse(shape: "type_submit", sure: 0.9, control: 0.95, text: 0.7), .type(bar, "owls", submit: true))
        XCTAssertEqual(try parse(shape: "click", sure: 0.9, control: 0.95, text: 0.7), .click(bar))
        XCTAssertNil(try parse(shape: "type_submit", sure: 0.5, control: 0.95, text: 0.7), "not sure of the shape")
        XCTAssertNil(try parse(shape: "type_submit", sure: 0.9, control: 0.6, text: 0.7), "not sure which control")
        XCTAssertNil(try parse(shape: "type_submit", sure: 0.9, control: 0.95, text: 0.3), "not sure of the words")
        XCTAssertNil(try parse(shape: "type_submit", sure: 0.9, control: 0.95, text: 0.7, more: 0.9), "more than one thing asked")
        XCTAssertNil(try parse(shape: "none", sure: 0.9, control: 0.95, text: 0.7))
    }

    func testTheWordsToTypeAreCutFromThePhrase() {
        XCTAssertEqual(PhraseText.candidates(in: "search for barn owls in chrome"),
                       ["barn owls in chrome", "barn owls", "for barn owls in chrome", "for barn owls"])
        XCTAssertEqual(PhraseText.candidates(in: "google peregrine falcon"), ["peregrine falcon"])
        XCTAssertEqual(PhraseText.candidates(in: "what is this"), [])
    }

    func testABrowserSearchGoesInANewTab() {
        let bar = ScreenTarget(id: 7, label: "Address and search bar", role: "AXTextField",
                               frame: .zero, kind: .control)
        let chrome = SessionCoordinator.steps(for: .type(bar, "owls", submit: true), in: "com.google.Chrome")
        XCTAssertEqual(chrome.map(\.tool), [.pressKey, .typeText, .pressKey])
        XCTAssertEqual(chrome.first?.string("key"), "t")
        let notes = SessionCoordinator.steps(for: .type(bar, "owls", submit: true), in: "com.apple.Notes")
        XCTAssertEqual(notes.map(\.tool), [.click, .pressKey, .typeText, .pressKey])
        XCTAssertEqual(SessionCoordinator.describe(.type(bar, "owls", submit: true), in: "com.google.Chrome"),
                       "Searched for “owls” in a new tab.")
        XCTAssertEqual(SessionCoordinator.spoken("Explorer (⇧⌘E)"), "Explorer")
    }

    func testAFollowUpIsDroppedOnlyWhenJevIsSureItIsNot() throws {
        let fallback = QuestionTriage.heuristic("and the other one", config: .defaults)
        let no = try JSONDecoder().decode(JevAnswers.self, from: Data(
            #"{"answers":{"kind":{"type":"choice","choice":"answer","confidence":0.9},"follow_up":{"type":"noul","noul":0.1}}}"#.utf8))
        XCTAssertEqual(QuestionTriage.parse(no, fallback: fallback, hasHistory: true)?.isFollowUp, false)
        let maybe = try JSONDecoder().decode(JevAnswers.self, from: Data(
            #"{"answers":{"kind":{"type":"choice","choice":"answer","confidence":0.9},"follow_up":{"type":"noul","noul":0.4}}}"#.utf8))
        XCTAssertEqual(QuestionTriage.parse(maybe, fallback: fallback, hasHistory: true)?.isFollowUp, true)
    }

    /// The real thing, only when a key is in the environment: `JEV_API_KEY=… swift test`.
    func testLiveTriageOnRealPhrasings() throws {
        guard let key = ProcessInfo.processInfo.environment["JEV_API_KEY"], !key.isEmpty else {
            throw XCTSkip("set JEV_API_KEY to run against the gateway")
        }
        var config = Config.defaults
        config.jev = Config.Jev(apiKey: key)
        let cases: [(String, QuestionTriage.Kind, Bool)] = [
            ("open Finder", .openApp, false),
            ("can you pull up Finder for me", .openApp, false),
            ("what does this button do", .answer, false),
            ("summarise this page", .answer, false),
            ("reply to this saying I'll be there at six", .act, true),
            ("what should I say back to him", .answer, true),
            ("close all these tabs", .act, false),
            ("open Finder and go to my downloads", .act, false),
        ]
        for (text, kind, draft) in cases {
            let triage = QuestionTriage.decide(text, frontmostApp: "Safari", previous: nil, config: config)
            XCTAssertEqual(triage.source, "jev", text)
            XCTAssertEqual(triage.kind, kind, text)
            XCTAssertEqual(triage.wantsDraft, draft, text)
            if kind == .openApp { XCTAssertEqual(triage.app?.name, "Finder", text) }
        }
    }

    private let sample = """
    {"model":"typesafe-ai/jev","answers":{
      "kind":{"type":"choice","choice":"act","confidence":0.95,"probabilities":{"answer":0,"act":0.96,"open_app":0.04}},
      "draft":{"type":"noul","noul":0.9}},
     "usage":{"input_tokens":379,"output_tokens":65}}
    """
}

final class ActionJudgeTests: XCTestCase {
    private let policy = ActionPolicy.default

    func testOnlyAClearAnswerOverridesTheList() {
        XCTAssertEqual(ActionJudge.sensitivity(0.9), true)
        XCTAssertEqual(ActionJudge.sensitivity(0.1), false)
        XCTAssertNil(ActionJudge.sensitivity(0.4))
        XCTAssertEqual(ActionJudge.consent(0.9), true)
        XCTAssertEqual(ActionJudge.consent(0.2), false)
        XCTAssertNil(ActionJudge.consent(0.5))
    }

    func testTheJudgeCanAllowWhatTheListWouldConfirm() {
        let call = ToolCall(tool: .click, arguments: ["x": 1, "y": 1])
        // "order" is on the list; "Sort by order" is not an order.
        XCTAssertEqual(policy.verdict(for: call, target: "Sort by order"), .confirm("click “Sort by order”"))
        XCTAssertEqual(policy.verdict(for: call, target: "Sort by order", judge: { _ in false }), .allow)
        XCTAssertEqual(policy.verdict(for: call, target: "Sort by order", judge: { _ in nil }),
                       .confirm("click “Sort by order”"))
    }

    func testTheJudgeCanConfirmWhatTheListWouldAllow() {
        let call = ToolCall(tool: .click, arguments: ["x": 1, "y": 1])
        XCTAssertEqual(policy.verdict(for: call, target: "Yes, go", judge: { _ in true }), .confirm("click “Yes, go”"))
        var told: String?
        _ = policy.verdict(for: call, target: "Send", judge: { told = $0; return nil })
        XCTAssertEqual(told, "click the control labelled “Send”")
    }

    func testRulesAreNeverPutToTheJudge() {
        var asked = false
        let judge: ActionPolicy.Judge = { _ in asked = true; return false }
        guard case .deny = policy.verdict(for: ToolCall(tool: .runShell, arguments: ["command": "sudo ls"]), judge: judge)
        else { return XCTFail("sudo is a rule") }
        guard case .confirm = policy.verdict(for: ToolCall(tool: .typeText, arguments: ["text": "hi"]),
                                             frontmostBundleID: "com.apple.Terminal", judge: judge)
        else { return XCTFail("a terminal is a rule") }
        XCTAssertFalse(asked)
    }

    func testJudgeIsSilentWithoutJev() {
        XCTAssertNil(ActionJudge.isSensitive("click the control labelled “Send”", in: "Mail", config: .defaults))
        XCTAssertNil(ActionJudge.isYes("yes", to: "send it", config: .defaults))
    }
}

final class DoneCheckTests: XCTestCase {
    private func session(request: String, review: @escaping (String) -> ActionJudge.Progress?) -> ActionSession {
        let hooks = ActionSession.Hooks(
            confirm: { _ in true },
            perform: { _, _, _ in "Safari is open and in front." },
            observe: { _ in .init(capture: nil, controls: "1. Back  (button) at 10, 10", frontmost: "Safari") },
            frontmostBundleID: { nil },
            elementLabel: { _ in nil },
            progress: { _ in },
            capHit: {},
            review: review)
        return ActionSession(policy: .default, maximumSteps: 5, initialCapture: nil, hooks: hooks, request: request)
    }

    func testTheModelIsToldWhenTheJobLooksDone() {
        var seen: String?
        let done = session(request: "open Safari") { seen = $0; return .init(done: true, picture: false) }
        let result = done.handle(ToolCall(tool: .openApp, arguments: ["name": "Safari"]))
        XCTAssertTrue(result.text.contains("looks complete"))
        XCTAssertNil(result.image, "the words sufficed")
        let progress = seen ?? ""
        XCTAssertTrue(progress.contains("The user asked: \"open Safari\""))
        XCTAssertTrue(progress.contains("1. open Safari — Safari is open and in front."))
        XCTAssertTrue(progress.contains("In front now: Safari"))
        XCTAssertTrue(progress.contains("Back  (button)"))
    }

    func testNothingIsSaidWhenTheJudgeIsUnsureOrAbsent() {
        let unsure = session(request: "open Safari") { _ in nil }
        XCTAssertFalse(unsure.handle(ToolCall(tool: .openApp, arguments: ["name": "Safari"])).text.contains("looks complete"))
        XCTAssertNil(ActionJudge.review("anything", config: .defaults))
    }
}
