import XCTest
@testable import Kestrel

/// A question asked straight after another, in the same app, should continue it — and a question
/// asked ten minutes later, or in a different app, should not.
final class ConversationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let window: TimeInterval = 90

    private func warmed(app: String? = "com.apple.Safari") -> Conversation {
        var conversation = Conversation()
        conversation.record(question: "What is this page?", answer: "It's the pricing page.",
                            at: start, appBundleID: app)
        return conversation
    }

    func testAFreshConversationIsCold() {
        XCTAssertFalse(Conversation().isWarm(now: start, window: window, frontmostBundleID: "x"))
        XCTAssertTrue(Conversation().context(now: start, window: window, frontmostBundleID: "x").isEmpty)
    }

    func testAQuestionRightAfterTheLastOneContinuesIt() {
        let conversation = warmed()
        XCTAssertTrue(conversation.isWarm(now: start.addingTimeInterval(10), window: window,
                                          frontmostBundleID: "com.apple.Safari"))
        XCTAssertEqual(conversation.context(now: start.addingTimeInterval(10), window: window,
                                            frontmostBundleID: "com.apple.Safari").count, 1)
    }

    func testTheThreadGoesColdAfterTheWindow() {
        let conversation = warmed()
        XCTAssertFalse(conversation.isWarm(now: start.addingTimeInterval(91), window: window,
                                           frontmostBundleID: "com.apple.Safari"))
    }

    func testSwitchingAppEndsTheThread() {
        let conversation = warmed()
        XCTAssertFalse(conversation.isWarm(now: start.addingTimeInterval(5), window: window,
                                           frontmostBundleID: "com.tinyspeck.slackmacgap"))
    }

    func testAnUnknownFrontmostAppDoesNotAccidentallyMatch() {
        let conversation = warmed()
        XCTAssertFalse(conversation.isWarm(now: start.addingTimeInterval(5), window: window,
                                           frontmostBundleID: nil))
        // …but a thread started with no known app still matches nil.
        XCTAssertTrue(warmed(app: nil).isWarm(now: start.addingTimeInterval(5), window: window,
                                              frontmostBundleID: nil))
    }

    func testAZeroWindowDisablesFollowUps() {
        XCTAssertFalse(warmed().isWarm(now: start.addingTimeInterval(1), window: 0,
                                       frontmostBundleID: "com.apple.Safari"))
    }

    // MARK: - Retention

    func testOnlyTheLastFewTurnsAreCarried() {
        var conversation = Conversation()
        for index in 1...6 {
            conversation.record(question: "q\(index)", answer: "a\(index)",
                                at: start.addingTimeInterval(Double(index)), appBundleID: "app")
        }
        let context = conversation.context(now: start.addingTimeInterval(7), window: window,
                                           frontmostBundleID: "app")
        XCTAssertEqual(context.count, Conversation.maximumTurns)
        XCTAssertEqual(context.last?.question, "q6")
        XCTAssertEqual(context.first?.question, "q4")
    }

    func testEmptyTurnsAreNotRecorded() {
        var conversation = Conversation()
        conversation.record(question: "", answer: "a", at: start, appBundleID: "app")
        conversation.record(question: "q", answer: "", at: start, appBundleID: "app")
        XCTAssertTrue(conversation.turns.isEmpty)
    }

    func testClearingEndsTheThread() {
        var conversation = warmed()
        conversation.clear()
        XCTAssertFalse(conversation.isWarm(now: start, window: window, frontmostBundleID: "com.apple.Safari"))
    }

    // MARK: - Prompt

    func testTheBriefCarriesBothSides() {
        let brief = try? XCTUnwrap(Conversation.brief(warmed().turns))
        XCTAssertTrue(brief?.contains("What is this page?") ?? false)
        XCTAssertTrue(brief?.contains("It's the pricing page.") ?? false)
        XCTAssertTrue(brief?.contains("the other") ?? false)
    }

    func testNoTurnsMeansNoBrief() {
        XCTAssertNil(Conversation.brief([]))
    }

    func testAFollowUpPromptIncludesTheThread() {
        let query = Query(text: "and the one below it?", history: warmed().turns)
        let prompt = PromptBuilder.build(query)
        XCTAssertTrue(prompt.contains("It's the pricing page."))
        XCTAssertTrue(prompt.contains("Question: and the one below it?"))
    }

    func testAFirstQuestionCarriesNoThread() {
        let prompt = PromptBuilder.build(Query(text: "what is this?"))
        XCTAssertFalse(prompt.contains("Earlier in this conversation"))
    }

    func testTheWindowIsClampedToSomethingSane() {
        var config = Config.defaults
        XCTAssertEqual(config.followUpSeconds, 90)
        config = try! JSONDecoder().decode(Config.self, from: Data(#"{"followUpSeconds":99999}"#.utf8))
        XCTAssertEqual(config.followUpSeconds, 900)
    }
}
