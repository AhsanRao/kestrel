import Foundation

/// Reads the files build.sh copies into `Kestrel.app/Contents/Resources`.
/// Falls back to the source tree so `swift run` and `swift test` work without an app bundle.
enum BundleResources {
    enum Prompt: String {
        case ask = "ask"
        /// Appended only when the question asks for words to paste somewhere else.
        case askDraft = "ask-draft"
        /// Appended only when macOS handed over nothing but the app's own chrome.
        case askBrowser = "ask-browser"
        /// Appended when the model has hands: how and when to use the six tools.
        case askTools = "ask-tools"
        case dictationCleanup = "dictation-cleanup"
    }

    /// Read once. The files do not change between questions, and reading three of them off disk on
    /// the way to every answer is time the user is waiting.
    private static var promptCache: [Prompt: String] = [:]
    private static let promptLock = NSLock()

    static func prompt(_ prompt: Prompt) -> String {
        promptLock.lock()
        defer { promptLock.unlock() }
        if let cached = promptCache[prompt] { return cached }
        let text = string(at: "Prompts/\(prompt.rawValue).txt") ?? ""
        promptCache[prompt] = text
        return text
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
