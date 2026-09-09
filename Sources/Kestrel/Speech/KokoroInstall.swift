import Foundation
import os

/// Where Kokoro lives on disk, and whether it is usable.
///
/// Two pieces, downloaded separately because they come from different releases: the sherpa-onnx
/// command-line synthesizer (a binary and the ONNX runtime it links against) and the Kokoro model
/// itself. Both land under `~/.kestrel/kokoro`, like every other thing Kestrel installs.
///
/// The binary finds `libonnxruntime.dylib` through an `@loader_path/../lib` rpath, which is why
/// `bin` and `lib` must stay siblings — moving either one breaks the launch with no useful error.
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

    /// Everything the synthesizer needs before it can be spawned.
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

    /// Roughly what the two downloads cost, for the onboarding row to promise before it starts.
    static let downloadSummary = "About 370 MB, once."

    /// The engine's own tarball layout puts everything under one versioned directory. The files
    /// Kestrel keeps are pulled out of it by name, so a new sherpa-onnx release can be dropped in
    /// without the paths above changing.
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
        // Downloaded executables are quarantined; left set, launching one shows a Gatekeeper
        // panel that a background app cannot dismiss.
        clearQuarantine(binary)
        clearQuarantine(runtimeLibrary)
    }

    /// The model tarball holds one directory of loose files. Its whole contents are kept: beyond
    /// the model and voices there is the espeak-ng data the phonemizer reads, which is a tree, and
    /// the lexicon the v1.0 models need.
    ///
    /// The quantized build names its weights `model.int8.onnx`; renaming it on the way in means
    /// nothing downstream has to know which of the two was downloaded.
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
        // Fails harmlessly when the attribute was never set, which is the common case.
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
