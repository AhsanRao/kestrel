import Foundation
import os

/// ChatGPT Plus/Pro via `codex exec` with ChatGPT sign-in (`codex login`). Same policy rules as
/// Claude: the CLI owns auth, Kestrel never reads `~/.codex` or calls api.openai.com.
///
/// Flag contract from spec §8.7. `codex` was not installed on the build machine, so these could not
/// be checked against `codex exec --help` at write time — `scripts/check-deps.sh` greps the help
/// output for each of them and reports a mismatch:
///   codex exec --sandbox read-only --skip-git-repo-check
///              --output-last-message <file> [--image <png>] [--model <m>] "<prompt>"
final class CodexBackend: Backend {
    let kind: BackendKind = .codex

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "codex")
    private let runner = CLIRunner()

    func cancel() { runner.cancel() }

    func ask(_ query: Query, config: Config, onDelta: ((String) -> Void)? = nil) throws -> Answer {
        guard let executable = CLIRunner.locate("codex") else {
            throw KestrelError.backendMissing("codex")
        }

        let lastMessage = Paths.temporaryFile(ext: "txt")
        defer { try? FileManager.default.removeItem(at: lastMessage) }

        var arguments = ["exec",
                         "--sandbox", "read-only",
                         "--skip-git-repo-check",
                         "--output-last-message", lastMessage.path]
        // Codex takes images as attachments rather than as a path the model reads itself.
        for image in [query.focusCrop, query.screenshot].compactMap({ $0 }) {
            arguments += ["--image", image.path]
        }
        if let model = config.codexModel, !model.isEmpty {
            arguments += ["--model", model]
        }
        arguments.append(PromptBuilder.build(query, mentionScreenshotPath: false))

        var env: [String: String] = [:]
        if let key = config.apiKeys.openai, !key.isEmpty { env["OPENAI_API_KEY"] = key }

        let result = try runner.run(executable: executable, arguments: arguments,
                                    cwd: Paths.root, environment: env, timeout: query.timeout)

        if result.timedOut { throw KestrelError.backendTimedOut(name: "codex", seconds: Int(query.timeout)) }

        let text = CodexBackend.parse(lastMessageFile: lastMessage, stdout: result.stdout)
        // Same rule as Claude: a quota error is read only out of a run that actually failed. The
        // transcript on stdout contains the answer, and an answer is not a diagnostic.
        if result.exitCode != 0 || text.isEmpty {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? result.stdout : result.stderr
            if BackendSupport.isQuotaError(detail) {
                throw KestrelError.quotaExhausted("Codex", resets: BackendSupport.quotaReset(in: detail))
            }
        }
        guard result.exitCode == 0 || !text.isEmpty else {
            let printed = result.stderr.isEmpty ? result.stdout : result.stderr
            throw KestrelError.backendFailed(name: "codex", stderr: BackendSupport.readableFailure(printed) ?? "")
        }
        guard !text.isEmpty else {
            throw KestrelError.backendFailed(name: "codex", stderr: "empty response")
        }
        log.debug("codex answered in \(result.durationMs)ms")
        return Answer(text: text, raw: result.stdout, durationMs: result.durationMs)
    }

    /// Prefer the `--output-last-message` file; fall back to the tail of stdout, which is the
    /// transcript with a leading banner and per-event headers.
    static func parse(lastMessageFile: URL, stdout: String) -> String {
        if let file = try? String(contentsOf: lastMessageFile, encoding: .utf8) {
            let text = BackendSupport.cleanAnswer(file)
            if !text.isEmpty { return text }
        }
        return BackendSupport.cleanAnswer(stripTranscript(stdout))
    }

    /// Drops `codex exec`'s banner and `[timestamp] label` event lines, keeping the final block.
    static func stripTranscript(_ stdout: String) -> String {
        let lines = stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var kept: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.contains("]") && trimmed.count < 120 { kept.removeAll(); continue }
            if trimmed.hasPrefix("--------") { continue }
            if trimmed.hasPrefix("OpenAI Codex") || trimmed.hasPrefix("workdir:") || trimmed.hasPrefix("model:")
                || trimmed.hasPrefix("provider:") || trimmed.hasPrefix("approval:") || trimmed.hasPrefix("sandbox:")
                || trimmed.hasPrefix("reasoning ") || trimmed.hasPrefix("tokens used:") {
                continue
            }
            kept.append(line)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
