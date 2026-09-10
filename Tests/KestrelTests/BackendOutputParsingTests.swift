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
        XCTAssertTrue(BackendSupport.isQuotaError("API error (status 429)"))
        XCTAssertFalse(BackendSupport.isQuotaError("Read tool: file not found"))
    }

    /// The envelope around every successful answer carries durations, token counts, a cost and two
    /// hex ids. A bare "429" needle matched all of them, so roughly one answer in fifteen ended in
    /// a quota error that had not happened.
    func testUsageNumbersContaining429AreNotQuotaErrors() {
        let envelope = """
        {"type":"result","subtype":"success","is_error":false,"duration_ms":4291,\
        "duration_api_ms":4290,"num_turns":1,"result":"You are looking at Safari.",\
        "session_id":"429e67aa-6531-46ba-813a-54e5513c074a","total_cost_usd":0.0142912,\
        "usage":{"input_tokens":3,"cache_read_input_tokens":3429,"output_tokens":429}}
        """
        // Two layers now reject it: the needle no longer matches a bare 429, and a successful run
        // produces no diagnostics for the needle to be run against in the first place.
        XCTAssertFalse(BackendSupport.isQuotaError(envelope))
        XCTAssertNil(ClaudeBackend.errorEnvelope(envelope))
        XCTAssertNil(ClaudeBackend.diagnostics(exitCode: 0, stdout: envelope, stderr: "",
                                               envelopeError: ClaudeBackend.errorEnvelope(envelope)))
    }

    /// An answer that discusses quotas is still just an answer.
    func testAnswerAboutUsageLimitsIsNotAQuotaError() {
        let stdout = #"{"type":"result","is_error":false,"result":"Your usage limit resets at 3pm."}"#
        XCTAssertNil(ClaudeBackend.diagnostics(exitCode: 0, stdout: stdout, stderr: "",
                                               envelopeError: ClaudeBackend.errorEnvelope(stdout)))
    }

    func testRealQuotaFailureIsStillCaught() {
        let detail = ClaudeBackend.diagnostics(exitCode: 1, stderr: "Claude usage limit reached",
                                               envelopeError: nil)
        XCTAssertNotNil(detail)
        XCTAssertTrue(BackendSupport.isQuotaError(detail ?? ""))
    }

    func testErrorEnvelopeIsUsedAsDiagnostics() {
        let stdout = #"{"type":"result","is_error":true,"result":"rate limit exceeded"}"#
        XCTAssertEqual(ClaudeBackend.errorEnvelope(stdout), "rate limit exceeded")
        let detail = ClaudeBackend.diagnostics(exitCode: 0, stderr: "",
                                               envelopeError: ClaudeBackend.errorEnvelope(stdout))
        XCTAssertTrue(BackendSupport.isQuotaError(detail ?? ""))
    }

    /// The run that started this: `claude` hit the plan's usage limit, exited 1 with an empty
    /// stderr, and said so somewhere inside a stdout full of hook events. Reading only stderr, the
    /// panel showed 400 characters of `{"type":"system","subtype":"hook_started"…`.
    func testUsageLimitOnStdoutIsCaughtAndReadable() {
        let stdout = """
        {"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}
        {"type":"result","is_error":true,"result":"Claude AI usage limit reached|1757520000"}
        """
        let detail = ClaudeBackend.diagnostics(exitCode: 1, stdout: stdout, stderr: "", envelopeError: nil)
        XCTAssertNotNil(detail)
        XCTAssertTrue(BackendSupport.isQuotaError(detail ?? ""))
        XCTAssertEqual(BackendSupport.quotaReset(in: detail ?? ""), Date(timeIntervalSince1970: 1_757_520_000))
    }

    func testAFailureReadsAsProseRatherThanJSON() {
        let stdout = """
        {"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}
        {"type":"result","is_error":true,"result":"Credit balance is too low"}
        """
        XCTAssertEqual(BackendSupport.readableFailure(stdout), "Credit balance is too low")
        XCTAssertNil(BackendSupport.readableFailure("""
        {"type":"system","subtype":"hook_started","hook_name":"SessionStart:startup"}
        """))
        // Plain stderr is already prose and survives untouched.
        XCTAssertEqual(BackendSupport.readableFailure("boom: bad flag"), "boom: bad flag")
    }

    func testStreamParserExposesOnlyRealErrors() {
        var ok = StreamParser()
        _ = ok.consume(#"{"type":"result","is_error":false,"result":"Your quota is fine."}"#)
        XCTAssertNil(ok.errorMessage)

        var bad = StreamParser()
        _ = bad.consume(#"{"type":"result","is_error":true,"result":"usage limit reached"}"#)
        XCTAssertEqual(bad.errorMessage, "usage limit reached")
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
