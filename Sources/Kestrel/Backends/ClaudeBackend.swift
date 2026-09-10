import Foundation
import os

/// Claude Pro/Max via headless Claude Code. Never touches `~/.claude` credentials and never calls
/// api.anthropic.com directly — the CLI owns auth entirely (spec §3).
///
/// Flags verified against `claude --help`, Claude Code 2.1.69 (2026-09-06):
///   -p, --print                        print response and exit
///   --output-format <format>           "text" | "json" | "stream-json"
///   --include-partial-messages         emit text deltas (needs --print and stream-json)
///   --verbose                          required alongside stream-json in print mode
///   --tools <tools...>                 restrict the built-in tool set    (we allow only Read)
///   --allowedTools <tools...>          auto-approve those tools, no prompt
///   --model <model>                    alias ("sonnet") or full id
///   --no-session-persistence           do not write a resumable session (only works with --print)
///   --strict-mcp-config                use only MCP servers passed on the command line — none.
///     Measured here: 16.9 s per question while the user's claude.ai connectors are discovered,
///     5.2 s without. `allowMCPServers` in config.json turns them back on.
/// There is no --max-turns in this release; Read-only single answers finish in one turn anyway.
final class ClaudeBackend: Backend {
    let kind: BackendKind = .claude

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "claude")
    private let runner = CLIRunner()

    func cancel() { runner.cancel() }

    /// Built as a pure function so the flag combinations can be tested without spawning anything.
    ///
    /// MCP discovery is the expensive one: with the user's connectors configured it added about
    /// eleven seconds to every question, and Kestrel only asks questions now, so it stays off
    /// unless the user has deliberately turned connectors on.
    static func arguments(for query: Query, config: Config, streaming: Bool) -> [String] {
        var arguments = ["-p", PromptBuilder.build(query), "--no-session-persistence"]

        let wantsConnectors = config.allowMCPServers
        if !wantsConnectors { arguments.append("--strict-mcp-config") }

        arguments += streaming
            ? ["--output-format", "stream-json", "--include-partial-messages", "--verbose"]
            : ["--output-format", "json"]

        if query.screenshot != nil || query.focusCrop != nil {
            arguments += ["--tools", "Read", "--allowedTools", "Read"]
        } else {
            arguments += ["--tools", ""]          // pure text turn: no tools at all, lowest latency
        }
        if let model = config.claudeModel, !model.isEmpty {
            arguments += ["--model", model]
        }
        return arguments
    }

    func ask(_ query: Query, config: Config, onDelta: ((String) -> Void)? = nil) throws -> Answer {
        guard let executable = CLIRunner.locate("claude") else {
            throw KestrelError.backendMissing("claude")
        }

        let streaming = onDelta != nil
        let arguments = ClaudeBackend.arguments(for: query, config: config, streaming: streaming)

        // Optional pay-as-you-go override. Absent by default: subscription auth stays with the CLI.
        var env: [String: String] = [:]
        if let key = config.apiKeys.anthropic, !key.isEmpty { env["ANTHROPIC_API_KEY"] = key }

        var parser = StreamParser()
        var sentences = SentenceAccumulator()
        let result: CLIRunner.Result
        do {
            result = try runner.run(
                executable: executable, arguments: arguments,
                cwd: query.workingDirectory ?? Paths.root,
                environment: env, timeout: query.timeout,
                onLine: streaming ? { line in
                    guard let chunk = parser.consume(line) else { return }
                    for sentence in sentences.push(chunk) { onDelta?(sentence) }
                } : nil)
        } catch is CancellationError {
            throw CancellationError()
        }

        if result.timedOut { throw KestrelError.backendTimedOut(name: "claude", seconds: Int(query.timeout)) }

        // Only what the CLI reported as a failure is eligible to be read as a quota error. The
        // answer, and the usage/cost/duration JSON around it, are not diagnostics.
        let diagnostics = ClaudeBackend.diagnostics(
            exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr,
            envelopeError: streaming ? parser.errorMessage : ClaudeBackend.errorEnvelope(result.stdout))
        if let diagnostics, BackendSupport.isQuotaError(diagnostics) {
            throw KestrelError.quotaExhausted("Claude", resets: BackendSupport.quotaReset(in: diagnostics))
        }
        guard result.exitCode == 0 else {
            throw KestrelError.backendFailed(
                name: "claude", stderr: BackendSupport.readableFailure(diagnostics ?? "") ?? "")
        }

        var text = streaming ? parser.answer : ClaudeBackend.parse(result.stdout)
        if text.isEmpty { text = ClaudeBackend.parse(result.stdout) }
        guard !text.isEmpty else {
            throw KestrelError.backendFailed(name: "claude", stderr: "empty response")
        }
        if streaming, let tail = sentences.flush() { onDelta?(tail) }
        log.debug("claude answered in \(result.durationMs)ms")
        return Answer(text: text, raw: result.stdout, durationMs: result.durationMs)
    }

    /// The text a failure is judged on: what the process printed when it actually failed, plus the
    /// message from an error envelope. Nil when the run reported no failure at all, which is the
    /// common case and the one that must never reach `isQuotaError`.
    ///
    /// A run that dies on the plan's usage limit exits non-zero with an empty stderr and says so
    /// somewhere in a stdout full of stream-json, so stdout counts as a diagnostic too — but only
    /// on a failed run, never on the successful ones whose token counts and answers used to be
    /// read as quota errors.
    static func diagnostics(exitCode: Int32, stdout: String = "", stderr: String,
                            envelopeError: String?) -> String? {
        var parts: [String] = []
        if exitCode != 0 {
            for stream in [stderr, stdout] where !stream.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(stream)
            }
        }
        if let envelopeError, !envelopeError.isEmpty { parts.append(envelopeError) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// The `result` string of a non-streaming envelope, but only when it is flagged `is_error`.
    static func errorEnvelope(_ stdout: String) -> String? {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["is_error"] as? Bool == true else { return nil }
        let message = (object["result"] as? String) ?? (object["error"] as? String)
        return (message?.isEmpty == false) ? message : "claude reported an error"
    }

    /// `--output-format json` prints one envelope object whose `result` holds the answer.
    /// Malformed or partial output falls back to the raw text so the user still sees something.
    static func parse(_ stdout: String) -> String {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let result = object["result"] as? String {
                return BackendSupport.cleanAnswer(result)
            }
            // Some versions nest the text under content blocks.
            if let content = object["content"] as? [[String: Any]] {
                let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.isEmpty { return BackendSupport.cleanAnswer(text) }
            }
        }
        return BackendSupport.cleanAnswer(trimmed)
    }
}
