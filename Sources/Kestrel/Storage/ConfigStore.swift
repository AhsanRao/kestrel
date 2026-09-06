import Foundation
import os

/// Owns the in-memory `Config`, writes it back to disk, and reloads it when the file changes on
/// disk so hand edits apply without relaunching (spec §8.13).
final class ConfigStore {
    static let shared = ConfigStore()

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "config")
    private let queue = DispatchQueue(label: "dev.0xash.kestrel.config")
    private var watcher: DispatchSourceFileSystemObject?
    private var observers: [(Config) -> Void] = []

    private(set) var current: Config = .defaults

    private init() {}

    /// Loads config.json, writing a fully-populated default file if none exists.
    func start() {
        current = ConfigStore.read() ?? .defaults
        if !FileManager.default.fileExists(atPath: Paths.config.path) {
            try? write(current)
        }
        startWatching()
    }

    func addObserver(_ block: @escaping (Config) -> Void) {
        observers.append(block)
    }

    /// Mutates and persists. Skips the watcher-driven reload for our own write.
    func update(_ mutate: (inout Config) -> Void) {
        var copy = current
        mutate(&copy)
        guard copy != current else { return }
        current = copy
        try? write(copy)
        notify()
    }

    func reload() {
        guard let fresh = ConfigStore.read(), fresh != current else { return }
        current = fresh
        log.info("config reloaded from disk")
        notify()
    }

    // MARK: - Disk

    static func read() -> Config? {
        guard let data = try? Data(contentsOf: Paths.config) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> Config? {
        try? JSONDecoder().decode(Config.self, from: data)
    }

    private func write(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: Paths.config, options: .atomic)
    }

    private func notify() {
        let snapshot = current
        DispatchQueue.main.async { self.observers.forEach { $0(snapshot) } }
    }

    // MARK: - Hot reload

    /// Watches the directory, not the file: editors and atomic writes replace the inode, which a
    /// file-level watcher would silently stop following.
    private func startWatching() {
        let fd = open(Paths.root.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            // Coalesce: a single save can fire several events.
            self?.queue.asyncAfter(deadline: .now() + 0.2) { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
