import Foundation
import os

/// Every tool call, appended to `~/.kestrel/logs/actions.jsonl`.
///
/// An assistant that can click things has to be auditable after the fact: what it did, whether the
/// user was asked, and whether it worked — especially for the steps taken while they were looking
/// somewhere else. One JSON object per line, so `tail -f` reads it as it happens.
enum ActionLog {
    struct Entry: Codable, Equatable {
        var at: Date
        var tool: String
        var arguments: [String: String]
        var verdict: String         // allow | confirm | deny
        var confirmed: Bool?        // only when asked
        var ok: Bool
        var result: String
        var durationMs: Int
    }

    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "actions")
    private static let queue = DispatchQueue(label: "dev.0xash.kestrel.actionlog")
    /// Enough to see what happened, short of the log becoming the output.
    static let resultLimit = 500

    static var url: URL { Paths.logs.appendingPathComponent("actions.jsonl") }

    static func record(_ entry: Entry) {
        log.info("\(entry.tool, privacy: .public) \(entry.verdict, privacy: .public) → \(entry.ok ? "ok" : "failed", privacy: .public)")
        queue.async {
            guard let line = encode(entry) else { return }
            append(line)
        }
    }

    static func encode(_ entry: Entry) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(entry), let json = String(data: data, encoding: .utf8)
        else { return nil }
        return json + "\n"
    }

    /// Arguments as strings, whatever the model sent.
    static func flatten(_ arguments: [String: Any]) -> [String: String] {
        arguments.mapValues { value in
            if let text = value as? String { return text }
            if let list = value as? [Any] { return list.map { "\($0)" }.joined(separator: ",") }
            return "\(value)"
        }
    }

    private static func append(_ line: String) {
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}
