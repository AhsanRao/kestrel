import Foundation

/// Every path Kestrel is allowed to write to. Nothing outside `~/.kestrel` is ever created.
enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// User data root. Also the working directory for every spawned CLI, so that the memory file
    /// (CLAUDE.md / AGENTS.md) is auto-loaded by both vendors.
    static let root = home.appendingPathComponent(".kestrel", isDirectory: true)

    static let config = root.appendingPathComponent("config.json")
    static let policy = root.appendingPathComponent("policy.json")
    static let memory = root.appendingPathComponent("KESTREL.md")
    static let claudeMemoryLink = root.appendingPathComponent("CLAUDE.md")
    static let codexMemoryLink = root.appendingPathComponent("AGENTS.md")

    static let models = root.appendingPathComponent("models", isDirectory: true)
    static let skills = root.appendingPathComponent("skills", isDirectory: true)
    static let logs = root.appendingPathComponent("logs", isDirectory: true)
    static let projects = root.appendingPathComponent("projects", isDirectory: true)
    static let tmp = root.appendingPathComponent("tmp", isDirectory: true)

    static let defaultWhisperModel = models.appendingPathComponent("ggml-base.en.bin")
    static let defaultWhisperBinary = "/opt/homebrew/bin/whisper-cli"

    /// PATH handed to every spawned subprocess. Homebrew and ~/.local/bin are where `claude`,
    /// `codex` and `whisper-cli` actually live; a GUI app inherits neither from the shell.
    static var subprocessPath: String {
        let extras = [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",
            home.appendingPathComponent(".local/bin").path,
            "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ]
        let inherited = ProcessInfo.processInfo.environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
        var seen = Set<String>()
        return (extras + inherited).filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    /// Creates the user data tree. Safe to call on every launch.
    static func bootstrap() throws {
        let fm = FileManager.default
        for dir in [root, models, skills, logs, projects, tmp] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // Old temp captures are worthless after a crash; do not let them accumulate.
        for file in (try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: file)
        }
    }

    static func temporaryFile(ext: String) -> URL {
        tmp.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    /// Collapses `/Users/<me>/...` to `~/...` for display in the panel and errors.
    static func tildeAbbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
