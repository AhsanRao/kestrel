import XCTest
@testable import Kestrel

final class BackendOutputParsingTests: XCTestCase {

    // MARK: - Claude

    func testClaudeJSONEnvelope() {
        let stdout = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":2140,
         "result":"You're in Xcode, on the build settings tab."}
        """
        XCTAssertEqual(ClaudeBackend.parse(stdout), "You're in Xcode, on the build settings tab.")
    }

    func testClaudeContentBlockFallback() {
        let stdout = #"{"content":[{"type":"text","text":"Two windows are open."}]}"#
        XCTAssertEqual(ClaudeBackend.parse(stdout), "Two windows are open.")
    }

    func testClaudeMalformedJSONFallsBackToRawText() {
        let stdout = "{\"result\": \"truncated"
        XCTAssertEqual(ClaudeBackend.parse(stdout), "{\"result\": \"truncated")
    }

    func testClaudeEmptyOutput() {
        XCTAssertEqual(ClaudeBackend.parse("   \n "), "")
    }

    func testClaudeStripsCodeFenceWrapper() {
        let stdout = #"{"result":"```\nplain answer\n```"}"#
        XCTAssertEqual(ClaudeBackend.parse(stdout), "plain answer")
    }

    // MARK: - Codex

    func testCodexPrefersLastMessageFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("last-\(UUID()).txt")
        try "The PDF export lives under File ▸ Export.".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(CodexBackend.parse(lastMessageFile: file, stdout: "noise"),
                       "The PDF export lives under File ▸ Export.")
    }

    func testCodexFallsBackToStdoutWhenFileMissing() {
        let missing = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID()).txt")
        let stdout = """
        OpenAI Codex v0.20.0
        --------
        workdir: /Users/x/.kestrel
        model: gpt-5
        --------
        [2026-09-06T10:00:00] codex
        You are looking at Safari.
        """
        XCTAssertEqual(CodexBackend.parse(lastMessageFile: missing, stdout: stdout),
                       "You are looking at Safari.")
    }

    func testCodexEmptyEverywhere() {
        let missing = URL(fileURLWithPath: "/tmp/none-\(UUID()).txt")
        XCTAssertEqual(CodexBackend.parse(lastMessageFile: missing, stdout: "  \n"), "")
    }

    // MARK: - Shared

    func testQuotaErrorsAreRecognised() {
        XCTAssertTrue(BackendSupport.isQuotaError("Error: usage limit reached, resets at 3pm"))
        XCTAssertTrue(BackendSupport.isQuotaError("429 Too Many Requests"))
        XCTAssertFalse(BackendSupport.isQuotaError("Read tool: file not found"))
    }

    func testCleanAnswerStripsQuotesAndFences() {
        XCTAssertEqual(BackendSupport.cleanAnswer("\"quoted\""), "quoted")
        XCTAssertEqual(BackendSupport.cleanAnswer("```text\nhello\n```"), "hello")
        XCTAssertEqual(BackendSupport.cleanAnswer("  spaced  "), "spaced")
    }

    // MARK: - Routing

    func testAutoRouteKeepsScreenshotsOnClaude() {
        let withShot = Query(text: "what is this", screenshot: URL(fileURLWithPath: "/tmp/a.png"))
        XCTAssertEqual(BackendRouter.route(withShot, configured: .codex), .claude)

        let shortText = Query(text: "what is the capital of France")
        XCTAssertEqual(BackendRouter.route(shortText, configured: .claude), .codex)

        let longText = Query(text: String(repeating: "word ", count: 30))
        XCTAssertEqual(BackendRouter.route(longText, configured: .claude), .claude)
    }
}
