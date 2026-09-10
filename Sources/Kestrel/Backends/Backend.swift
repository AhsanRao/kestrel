import Foundation

enum BackendKind: String, Codable, CaseIterable, Equatable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

/// Vendor-neutral contract. Implementations spawn the vendor CLI; nothing here ever touches an
/// OAuth token or a vendor REST endpoint (spec §2, §3).
protocol Backend: AnyObject {
    var kind: BackendKind { get }
    /// Blocking. Call from a background queue. Throws `KestrelError` on failure.
    ///
    /// - Parameter onDelta: called on a background queue with each fragment of the answer as the
    ///   model writes it, when the backend can stream. Kestrel speaks the answer sentence by
    ///   sentence off this, so the reply starts out loud seconds before the model has finished.
    func ask(_ query: Query, config: Config, onDelta: ((String) -> Void)?) throws -> Answer
    func cancel()
}

extension Backend {
    func ask(_ query: Query, config: Config) throws -> Answer {
        try ask(query, config: config, onDelta: nil)
    }
}

enum BackendSupport {
    /// The user's plan quota, not a crash. Detected by string because neither CLI has a stable
    /// exit code for it.
    ///
    /// Only ever call this on text a CLI emitted as a *failure* — stderr from a non-zero exit, or
    /// an error envelope's message. Run against the whole of stdout it reports a quota error for
    /// answers that merely discuss one, and for any `stream-json` run whose token count or
    /// `duration_ms` happens to contain "429". Both looked identical to the user: a full answer,
    /// spoken, followed by "Claude usage limit reached".
    static func isQuotaError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = [
            "usage limit reached", "usage limit exceeded", "exceeded your usage",
            "rate limit", "rate_limit", "quota exceeded", "exceeded your quota",
            "insufficient quota", "insufficient_quota", "out of credits",
            "credit balance is too low", "too many requests",
        ]
        if phrases.contains(where: lowered.contains) { return true }
        // A bare "429" matches token counts, durations and prices. Require HTTP framing.
        return ["status 429", "status: 429", "http 429", "error 429", "code 429", "(429)"]
            .contains { lowered.contains($0) }
    }

    /// Strips the wrapper models sometimes add despite being told not to.
    static func cleanAnswer(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if out.hasPrefix("```") {
            let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 2 {
                var body = Array(lines.dropFirst())
                if body.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { body.removeLast() }
                out = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if out.count > 1, out.hasPrefix("\""), out.hasSuffix("\"") {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }
}
