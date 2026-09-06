import Foundation
import os

/// Claude Pro/Max via headless Claude Code. Never touches `~/.claude` credentials and never calls
/// api.anthropic.com directly — the CLI owns auth entirely (spec §3).
///
/// Flags verified against `claude --help`, Claude Code 2.1.69 (2026-09-06):
///   -p, --print                        print response and exit
///   --output-format <format>           "text" | "json" | "stream-json"   (we parse the json envelope)
///   --tools <tools...>                 restrict the built-in tool set    (we allow only Read)
///   --allowedTools <tools...>          auto-approve those tools, no prompt
///   --model <model>                    alias ("sonnet") or full id
///   --no-session-persistence           do not write a resumable session (only works with --print)
/// There is no --max-turns in this release; Read-only single answers finish in one turn anyway.
final class ClaudeBackend: Backend {
    let kind: BackendKind = .claude

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "claude")
    private let runner = CLIRunner()

    func cancel() { runner.cancel() }

    func ask(_ query: Query, config: Config) throws -> Answer {
        guard let executable = CLIRunner.locate("claude") else {
            throw KestrelError.backendMissing("claude")
        }

        var arguments = ["-p", PromptBuilder.build(query),
                         "--output-format", "json",
                         "--no-session-persistence"]
        if query.screenshot != nil || query.focusCrop != nil {
            arguments += ["--tools", "Read", "--allowedTools", "Read"]
        } else {
            arguments += ["--tools", ""]          // pure text turn: no tools at all, lowest latency
        }
        if let model = config.claudeModel, !model.isEmpty {
            arguments += ["--model", model]
        }

        // Optional pay-as-you-go override. Absent by default: subscription auth stays with the CLI.
        var env: [String: String] = [:]
        if let key = config.apiKeys.anthropic, !key.isEmpty { env["ANTHROPIC_API_KEY"] = key }

        let result: CLIRunner.Result
        do {
            result = try runner.run(executable: executable, arguments: arguments,
                                    cwd: Paths.root, environment: env, timeout: query.timeout)
        } catch is CancellationError {
            throw CancellationError()
        }

        if result.timedOut { throw KestrelError.backendTimedOut(name: "claude", seconds: Int(query.timeout)) }
        let combined = result.stdout + "\n" + result.stderr
        if BackendSupport.isQuotaError(combined) { throw KestrelError.quotaExhausted("Claude") }
        guard result.exitCode == 0 else {
            throw KestrelError.backendFailed(name: "claude", stderr: result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let text = ClaudeBackend.parse(result.stdout)
        guard !text.isEmpty else {
            throw KestrelError.backendFailed(name: "claude", stderr: "empty response")
        }
        log.debug("claude answered in \(result.durationMs)ms")
        return Answer(text: text, raw: result.stdout, durationMs: result.durationMs)
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
