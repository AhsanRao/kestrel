import XCTest
@testable import Kestrel

/// The flags are the whole contract with the CLI, and one of them is worth about eleven seconds a
/// question, so they are pinned down here rather than discovered in the field.
final class ClaudeArgumentsTests: XCTestCase {
    private func arguments(_ query: Query, config: Config = .defaults, streaming: Bool = false) -> [String] {
        ClaudeBackend.arguments(for: query, config: config, streaming: streaming)
    }

    func testAPlainQuestionSkipsConnectorDiscovery() {
        // Measured on the build machine: 16.9 s with the user's connectors, 5.2 s without.
        XCTAssertTrue(arguments(Query(text: "what is this?")).contains("--strict-mcp-config"))
    }

    func testConnectorsCanBeTurnedOnGlobally() {
        var config = Config.defaults
        config.allowMCPServers = true
        XCTAssertFalse(arguments(Query(text: "x"), config: config).contains("--strict-mcp-config"))
    }

    func testATaskCanOptIntoConnectorsWithoutSlowingQuestionsDown() {
        var config = Config.defaults
        config.mcpForTasks = true
        XCTAssertFalse(arguments(Query(text: "send it", mode: .agent), config: config)
            .contains("--strict-mcp-config"))
        // The same setting must not leak into an ordinary question.
        XCTAssertTrue(arguments(Query(text: "what is this?"), config: config)
            .contains("--strict-mcp-config"))
    }

    func testStreamingAsksForPartialMessages() {
        let streamed = arguments(Query(text: "x"), streaming: true)
        XCTAssertTrue(streamed.contains("stream-json"))
        XCTAssertTrue(streamed.contains("--include-partial-messages"))
        XCTAssertTrue(streamed.contains("--verbose"), "stream-json needs --verbose in print mode")
    }

    func testANonStreamingCallAsksForTheJSONEnvelope() {
        let plain = arguments(Query(text: "x"))
        XCTAssertTrue(plain.contains("json"))
        XCTAssertFalse(plain.contains("--include-partial-messages"))
    }

    func testAScreenshotQuestionIsAllowedToReadAndNothingElse() {
        let withImage = arguments(Query(text: "x", screenshot: URL(fileURLWithPath: "/tmp/a.png")))
        XCTAssertEqual(zip(withImage, withImage.dropFirst()).first { $0.0 == "--allowedTools" }?.1, "Read")
        XCTAssertEqual(zip(withImage, withImage.dropFirst()).first { $0.0 == "--tools" }?.1, "Read")
    }

    func testATextOnlyTurnGetsNoToolsAtAll() {
        let plain = arguments(Query(text: "clean this up", mode: .dictationCleanup))
        XCTAssertEqual(zip(plain, plain.dropFirst()).first { $0.0 == "--tools" }?.1, "")
        XCTAssertFalse(plain.contains("--allowedTools"))
    }

    func testSessionsAreNeverPersisted() {
        XCTAssertTrue(arguments(Query(text: "x")).contains("--no-session-persistence"))
    }

    func testAConfiguredModelIsPassedThroughAndABlankOneIsNot() {
        var config = Config.defaults
        config.claudeModel = "sonnet"
        XCTAssertEqual(zip(arguments(Query(text: "x"), config: config),
                           arguments(Query(text: "x"), config: config).dropFirst())
            .first { $0.0 == "--model" }?.1, "sonnet")

        config.claudeModel = ""
        XCTAssertFalse(arguments(Query(text: "x"), config: config).contains("--model"))
    }

    func testThePromptIsTheFirstThingAfterPrint() {
        let built = arguments(Query(text: "what is this?"))
        XCTAssertEqual(built.first, "-p")
        XCTAssertTrue(built[1].contains("Question: what is this?"))
    }
}
