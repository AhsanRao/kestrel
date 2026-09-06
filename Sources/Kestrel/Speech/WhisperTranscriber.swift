import Foundation
import os

/// whisper.cpp via its `whisper-cli` binary (spec §8.4).
///
/// Flags verified against `whisper-cli --help`, whisper.cpp shipped with ggml 0.23.0 (2026-09-06):
///   -m <model> -f <wav>   model and input
///   -nt                   no timestamps in the output
///   -np                   no prints other than the result
///   -l <lang>             language, or "auto"
///   -t N                  decode threads; the default of 4 leaves an M-series chip idle
///   -mc 0                 no text context carried between segments, which is where whisper's
///                         invented sentences usually come from on short clips
///   -sns                  suppress non-speech tokens, so coughs and clicks stop becoming words
///   --prompt              optional vocabulary hint (names, jargon) from config
final class WhisperTranscriber: Transcriber {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "whisper")
    private let runner = CLIRunner()

    func cancel() { runner.cancel() }

    /// Leaves a couple of cores for the UI and the CLI that is about to run.
    static var threadCount: Int {
        max(4, ProcessInfo.processInfo.activeProcessorCount - 2)
    }

    /// The configured model, or the best one actually installed. Falling back beats failing when
    /// the user has downloaded a different size than the config names.
    static func resolveModel(config: Config) -> URL? {
        let configured = config.whisperModelURL
        if FileManager.default.fileExists(atPath: configured.path) { return configured }
        let installed = (try? FileManager.default.contentsOfDirectory(at: Paths.models,
                                                                     includingPropertiesForKeys: [.fileSizeKey]))?
            .filter { $0.pathExtension == "bin" && $0.lastPathComponent.hasPrefix("ggml-") } ?? []
        // Larger model, better transcript; whisper's sizes sort that way by file size.
        return installed.max { a, b in
            let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sizeA < sizeB
        }
    }

    func transcribe(_ wav: URL, config: Config) throws -> String {
        let binary = config.whisperBinaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw KestrelError.whisperBinaryMissing(Paths.tildeAbbreviated(binary))
        }
        guard let model = WhisperTranscriber.resolveModel(config: config) else {
            throw KestrelError.whisperModelMissing(Paths.tildeAbbreviated(config.whisperModelURL))
        }

        var arguments = ["-m", model.path, "-f", wav.path, "-nt", "-np",
                         "-l", WhisperTranscriber.language(forModel: model, config: config),
                         "-t", String(WhisperTranscriber.threadCount),
                         "-mc", "0", "-sns"]
        if let hint = config.transcriptionHint, !hint.isEmpty {
            arguments += ["--prompt", hint]
        }
        let result = try runner.run(executable: binary, arguments: arguments,
                                    cwd: Paths.tmp, timeout: 120)
        if result.timedOut { throw KestrelError.transcriptionFailed("whisper timed out") }
        guard result.exitCode == 0 else {
            throw KestrelError.transcriptionFailed(
                String(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)))
        }
        let text = WhisperTranscriber.parse(result.stdout)
        log.debug("transcribed \(text.count) chars in \(result.durationMs)ms")
        return text
    }

    /// An English-only model rejects `auto`; force `en` so the default setup just works.
    /// Keyed off the model actually being run, which may not be the one named in the config.
    static func language(forModel model: URL, config: Config) -> String {
        if model.lastPathComponent.contains(".en") { return "en" }
        return config.language.isEmpty ? "auto" : config.language
    }

    /// Strips timestamps, whisper's own bracket markers, and the filler it hallucinates on silence.
    static func parse(_ stdout: String) -> String {
        var lines: [String] = []
        for rawLine in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            var line = String(rawLine)
            // "[00:00:00.000 --> 00:00:02.000]  text" when -nt is unsupported by an older build.
            if let close = line.firstIndex(of: "]"), line.hasPrefix("["), line.contains("-->") {
                line = String(line[line.index(after: close)...])
            }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") { continue }   // [BLANK_AUDIO], [MUSIC]
            if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") { continue }   // (blank_audio)
            if trimmed.hasPrefix("whisper_") || trimmed.hasPrefix("main:") || trimmed.hasPrefix("system_info") {
                continue
            }
            lines.append(trimmed)
        }
        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isNoise(joined) ? "" : joined
    }

    /// Whisper emits confident nonsense on near-silence. These are the usual suspects.
    static func isNoise(_ text: String) -> Bool {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?…\"'"))
        if normalized.count < 3 { return true }
        let blocklist: Set<String> = [
            "you", "thank you", "thanks", "thank you very much", "thanks for watching",
            "thank you for watching", "bye", "okay", "uh", "um", "hmm", "so",
            "please subscribe", "subtitles by the amara org community", "the end",
        ]
        return blocklist.contains(normalized)
    }
}
