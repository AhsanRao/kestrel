import Foundation
import os

/// Where Kokoro lives, and whether it is usable. Two downloads: sherpa-onnx's synthesizer, and
/// the model.
///
/// `bin` and `lib` must stay siblings — the binary finds `libonnxruntime.dylib` through an
/// `@loader_path/../lib` rpath, and moving either breaks the launch with no useful error.
enum KokoroInstall {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")

    static let root = Paths.root.appendingPathComponent("kokoro", isDirectory: true)
    static let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
    static let libDirectory = root.appendingPathComponent("lib", isDirectory: true)
    static let modelDirectory = root.appendingPathComponent("model", isDirectory: true)

    static let binary = binDirectory.appendingPathComponent("sherpa-onnx-offline-tts")
    static let runtimeLibrary = libDirectory.appendingPathComponent("libonnxruntime.dylib")

    static let model = modelDirectory.appendingPathComponent("model.onnx")
    static let voices = modelDirectory.appendingPathComponent("voices.bin")
    static let tokens = modelDirectory.appendingPathComponent("tokens.txt")
    static let espeakData = modelDirectory.appendingPathComponent("espeak-ng-data", isDirectory: true)
    static let lexicon = modelDirectory.appendingPathComponent("lexicon-us-en.txt")

    /// Everything needed before the synthesizer can be spawned.
    static var isReady: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: binary.path)
            && fm.fileExists(atPath: runtimeLibrary.path)
            && fm.fileExists(atPath: model.path)
            && fm.fileExists(atPath: voices.path)
            && fm.fileExists(atPath: tokens.path)
            && fm.fileExists(atPath: espeakData.path)
            && fm.fileExists(atPath: lexicon.path)
    }

    /// What the onboarding row promises before starting.
    static let downloadSummary = "About 370 MB, once."

    /// Pulled out by name, so a new sherpa-onnx release drops in without changing the paths.
    static func installEngine(fromExtracted directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: libDirectory, withIntermediateDirectories: true)
        guard let found = firstFile(named: "sherpa-onnx-offline-tts", under: directory),
              let runtime = firstFile(named: "libonnxruntime.dylib", under: directory)
        else { throw KestrelError.speech("The speech engine download was missing its binary.") }
        try replace(found, with: binary)
        try replace(runtime, with: runtimeLibrary)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        // Quarantined executables raise a Gatekeeper panel a background app cannot dismiss.
        clearQuarantine(binary)
        clearQuarantine(runtimeLibrary)
    }

    /// Keeps the whole directory: the espeak-ng data and lexicon matter as much as the weights.
    /// The quantized build names them `model.int8.onnx`, renamed here so nothing downstream cares.
    static func installModel(fromExtracted directory: URL) throws {
        let names = ["model.onnx", "model.int8.onnx"]
        guard let weights = names.compactMap({ firstFile(named: $0, under: directory) }).first else {
            throw KestrelError.speech("The voice download was missing its model.")
        }
        try replace(weights.deletingLastPathComponent(), with: modelDirectory)
        let landed = modelDirectory.appendingPathComponent(weights.lastPathComponent)
        if landed != model {
            try? FileManager.default.removeItem(at: model)
            try FileManager.default.moveItem(at: landed, to: model)
        }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Files

    private static func replace(_ source: URL, with destination: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(),
                               withIntermediateDirectories: true)
        try fm.moveItem(at: source, to: destination)
    }

    private static func clearQuarantine(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        process.standardError = FileHandle.nullDevice
        // Fails harmlessly when the attribute was never set.
        try? process.run()
        process.waitUntilExit()
    }

    private static func firstFile(named name: String, under directory: URL) -> URL? {
        enumerate(directory).first { $0.lastPathComponent == name }
    }

    private static func firstDirectory(containing name: String, under directory: URL) -> URL? {
        enumerate(directory).first { $0.lastPathComponent == name }?.deletingLastPathComponent()
    }

    private static func enumerate(_ directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
    }
}
