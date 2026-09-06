import Foundation

/// Reads the files build.sh copies into `Kestrel.app/Contents/Resources`.
/// Falls back to the source tree so `swift run` and `swift test` work without an app bundle.
enum BundleResources {
    enum Prompt: String {
        case ask = "ask"
        case dictationCleanup = "dictation-cleanup"
        case walkthrough = "walkthrough"
        case walkthroughElements = "walkthrough-elements"
        case agent = "agent"
        case acknowledgements = "acknowledgements"
    }

    static func prompt(_ prompt: Prompt) -> String {
        string(at: "Prompts/\(prompt.rawValue).txt") ?? ""
    }

    /// One of the short "let me look" lines spoken while the model is still thinking.
    static func randomAcknowledgement() -> String {
        let lines = prompt(.acknowledgements)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.randomElement() ?? "One sec."
    }

    static var defaultMemory: String {
        string(at: "DefaultMemory.md") ?? "# Kestrel memory\n"
    }

    static func url(for relativePath: String) -> URL? {
        for base in searchPaths {
            let candidate = base.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func string(at relativePath: String) -> String? {
        url(for: relativePath).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private static var searchPaths: [URL] {
        var paths: [URL] = []
        if let resources = Bundle.main.resourceURL { paths.append(resources) }
        paths.append(sourceTreeResources)
        return paths
    }

    /// `<repo>/Resources`, derived from this file's own location at compile time.
    private static var sourceTreeResources: URL {
        URL(fileURLWithPath: #filePath)          // Sources/Kestrel/Storage/BundleResources.swift
            .deletingLastPathComponent()          // Storage
            .deletingLastPathComponent()          // Kestrel
            .deletingLastPathComponent()          // Sources
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("Resources")
    }
}
