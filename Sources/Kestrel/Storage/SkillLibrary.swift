import Foundation
import os

/// Per-app notes injected when that app is frontmost (spec §16).
///
/// `~/.kestrel/skills/<bundle-id>.md` is loaded whenever that app is in front, and `default.md`
/// is loaded always. It is how the user teaches Kestrel their own vocabulary — which Linear team
/// is theirs, what "the deploy script" means — without editing prompts or rebuilding.
enum SkillLibrary {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "skills")

    /// Prompts are sent on every question, so a runaway skill file must not quietly cost seconds.
    static let maximumCharacters = 6_000

    private static var cache: [String: (modified: Date, text: String)] = [:]
    private static let cacheLock = NSLock()

    /// The notes to send for the app in front, or nil when there are none.
    static func notes(forBundleID bundleID: String?) -> String? {
        var parts: [String] = []
        if let general = read(named: "default") { parts.append(general) }
        if let bundleID, let specific = read(named: bundleID) {
            parts.append("Notes for the app in front (\(bundleID)):\n\(specific)")
        }
        guard !parts.isEmpty else { return nil }
        return String(parts.joined(separator: "\n\n").prefix(maximumCharacters))
    }

    /// Reads a skill file, re-reading only when it has actually changed on disk.
    static func read(named name: String) -> String? {
        let url = Paths.skills.appendingPathComponent("\(name).md")
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate else { return nil }

        cacheLock.lock()
        if let cached = cache[name], cached.modified == modified {
            cacheLock.unlock()
            return cached.text.isEmpty ? nil : cached.text
        }
        cacheLock.unlock()

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let text = String(strip(raw).prefix(maximumCharacters))
        cacheLock.lock()
        cache[name] = (modified, text)
        cacheLock.unlock()
        log.debug("loaded skill \(name, privacy: .public) (\(text.count) chars)")
        return text.isEmpty ? nil : text
    }

    /// Drops comment lines and blank runs, so a file of headings costs nothing.
    static func strip(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("<!--") }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func invalidate() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    /// Writes the starter files on first launch. Never overwrites the user's own.
    static func bootstrap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.skills, withIntermediateDirectories: true)
        for (name, body) in [("README", SkillLibrary.readmeTemplate),
                             ("default", SkillLibrary.defaultTemplate)] {
            let url = Paths.skills.appendingPathComponent("\(name).md")
            guard !fm.fileExists(atPath: url.path) else { continue }
            try? body.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static let readmeTemplate = """
    # Skills

    Drop a markdown file in this folder and Kestrel sends it with every question you ask while that
    app is in front.

    - `default.md` — sent always.
    - `<bundle id>.md` — sent only when that app is frontmost, for example
      `com.apple.Terminal.md`, `com.tinyspeck.slackmacgap.md`, `com.figma.Desktop.md`.

    Find an app's bundle id with:

        osascript -e 'id of app "Slack"'

    Keep each file short. Everything here is sent on every question, so length costs latency.
    Files are re-read as soon as you save them; there is nothing to restart.
    """

    static let defaultTemplate = """
    <!-- Sent with every question, whatever app is in front. Keep it to things that are always true. -->

    - Prefer short answers. Say the thing, then stop.
    - When naming a menu or button, use the label exactly as it appears on screen.
    """
}
