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

    var executableName: String { rawValue }
}

/// Vendor-neutral contract. Implementations spawn the vendor CLI; nothing here ever touches an
/// OAuth token or a vendor REST endpoint (spec §2, §3).
protocol Backend: AnyObject {
    var kind: BackendKind { get }
    /// Blocking. Call from a background queue. Throws `KestrelError` on failure.
    func ask(_ query: Query, config: Config) throws -> Answer
    func cancel()
}

enum BackendSupport {
    /// The user's plan quota, not a crash. Detected by string because neither CLI has a stable
    /// exit code for it.
    static func isQuotaError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let needles = [
            "usage limit", "rate limit", "quota", "credit balance",
            "insufficient_quota", "too many requests", "429",
        ]
        return needles.contains { lowered.contains($0) }
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
