import Foundation
import os

/// Every action Kestrel takes, appended to `~/.kestrel/logs/actions.jsonl`.
///
/// An assistant that can click things has to be auditable after the fact: what it did, to which
/// app, whether the user was asked, and whether it worked. One JSON object per line so it can be
/// read with `tail -f` while it happens.
enum ActionLog {
    struct Entry: Codable, Equatable {
        var at: Date
        var kind: Action.Kind
        var describe: String
        var app: String?
        var decision: ActionPolicy.Decision
        var confirmed: Bool
        var succeeded: Bool
        var detail: String?
    }

    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "actions")
    private static let queue = DispatchQueue(label: "dev.0xash.kestrel.actionlog")

    static var url: URL { Paths.logs.appendingPathComponent("actions.jsonl") }

    static func record(_ entry: Entry) {
        log.info("\(entry.kind.rawValue, privacy: .public) \(entry.describe, privacy: .public) → \(entry.succeeded ? "ok" : "failed", privacy: .public)")
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

    private static func append(_ line: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
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
