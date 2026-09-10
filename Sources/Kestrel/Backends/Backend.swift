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

    /// The reset time a CLI names when it refuses on quota. Claude Code reports the limit as
    /// `Claude AI usage limit reached|<epoch seconds>`; nothing else in the output carries one.
    static func quotaReset(in text: String) -> Date? {
        guard let range = text.range(of: "usage limit reached|", options: .caseInsensitive) else { return nil }
        let digits = text[range.upperBound...].prefix(while: \.isNumber)
        guard let seconds = TimeInterval(digits), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// What a failed run should say to a person.
    ///
    /// A CLI's output is a mix of JSON stream events, hook chatter and the odd plain line. Handed
    /// to the panel raw it read `claude stopped short — {"type":"system","subtype":"hook_started"…`,
    /// which is 400 characters that name neither the failure nor anything to do about it. Only the
    /// human-readable fields of each object survive; the machinery around them does not.
    static func readableFailure(_ text: String) -> String? {
        var parts: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.hasPrefix("{") else { parts.append(trimmed); continue }
            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            for key in ["error", "result", "message"] {
                if let value = object[key] as? String, !value.isEmpty { parts.append(value); break }
            }
        }
        var seen = Set<String>()
        let joined = parts.filter { seen.insert($0).inserted }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : String(joined.prefix(300))
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
