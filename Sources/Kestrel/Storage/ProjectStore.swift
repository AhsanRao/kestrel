import AppKit
import Foundation
import os

/// A folder per task, under `~/.kestrel/projects`.
///
/// HeyClicky gives each task its own project directory and leaves the output there — the copy on
/// this machine had a generated PDF and an HTML page sitting in one. The same idea: a task that
/// produces something needs somewhere to put it that the user can find afterwards, and a working
/// directory that cannot wander outside `~/.kestrel`.
enum ProjectStore {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "projects")

    static let maximumSlugLength = 48

    /// A folder name from a spoken goal: lowercase, hyphenated, ASCII, and never empty.
    static func slug(from goal: String) -> String {
        let lowered = goal.lowercased()
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(cleaned)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let trimmed = String(collapsed.prefix(maximumSlugLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "task" : trimmed
    }

    /// Creates the folder for a task, adding a suffix rather than reusing or clobbering an existing
    /// one. Returns nil if the path would escape the projects directory.
    static func create(for goal: String, now: Date = Date()) -> URL? {
        let base = slug(from: goal)
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.projects, withIntermediateDirectories: true)

        for attempt in 0..<50 {
            let name = attempt == 0 ? base : "\(base)-\(attempt + 1)"
            guard let url = resolve(name) else { return nil }
            if !fm.fileExists(atPath: url.path) {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true)
                linkMemory(into: url)
                log.debug("project \(name, privacy: .public)")
                return url
            }
        }
        return nil
    }

    /// Refuses anything that would resolve outside `~/.kestrel/projects`, whatever the goal said.
    static func resolve(_ name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
        let url = Paths.projects.appendingPathComponent(name).standardizedFileURL
        let root = Paths.projects.standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        return url
    }

    /// Both CLIs read their memory file from the working directory, so a project gets the same
    /// links `~/.kestrel` has — otherwise running a task there would forget everything.
    private static func linkMemory(into project: URL) {
        let fm = FileManager.default
        for name in ["CLAUDE.md", "AGENTS.md"] {
            let link = project.appendingPathComponent(name)
            guard !fm.fileExists(atPath: link.path) else { continue }
            try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: Paths.memory.path)
        }
    }

    /// Files a task actually produced — the memory symlinks and dotfiles are not output.
    static func outputs(in project: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter { !["CLAUDE.md", "AGENTS.md"].contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: Paths.projects, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Paths.projects)
    }
}
