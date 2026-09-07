import AppKit
import Foundation
import os

/// Seeds and exposes `~/.kestrel/KESTREL.md`, plus the two symlinks that make both CLIs load it
/// automatically from their working directory (spec §8.14).
enum MemoryStore {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "memory")

    static func bootstrap() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Paths.memory.path) {
            try? BundleResources.defaultMemory.write(to: Paths.memory, atomically: true, encoding: .utf8)
            log.info("seeded KESTREL.md")
        }
        link(Paths.claudeMemoryLink)
        link(Paths.codexMemoryLink)
    }

    static func read() -> String {
        (try? String(contentsOf: Paths.memory, encoding: .utf8)) ?? ""
    }

    /// Overwrites the memory file. The only writer is `MemoryWriter`, which builds the new text
    /// from the old rather than appending blindly.
    static func write(_ text: String) {
        try? text.write(to: Paths.memory, atomically: true, encoding: .utf8)
    }

    static func openInEditor() {
        NSWorkspace.shared.open(Paths.memory)
    }

    /// Points `link` at KESTREL.md. Leaves a real file alone: the user may have replaced the
    /// symlink with their own CLAUDE.md deliberately.
    private static func link(_ link: URL) {
        let fm = FileManager.default
        if let destination = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            guard destination != Paths.memory.lastPathComponent else { return }
            try? fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            return
        }
        try? fm.createSymbolicLink(atPath: link.path, withDestinationPath: Paths.memory.lastPathComponent)
    }
}
