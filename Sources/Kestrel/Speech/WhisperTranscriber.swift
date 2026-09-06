import Foundation
import os

/// whisper.cpp via its `whisper-cli` binary (spec §8.4).
/// Flags: -m <model> -f <wav> -nt (no timestamps) -np (no progress) --no-prints -l <lang>
final class WhisperTranscriber: Transcriber {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "whisper")
    private let runner = CLIRunner()

    func cancel() { runner.cancel() }

    func transcribe(_ wav: URL, config: Config) throws -> String {
        let binary = config.whisperBinaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw KestrelError.whisperBinaryMissing(Paths.tildeAbbreviated(binary))
        }
        let model = config.whisperModelURL
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw KestrelError.whisperModelMissing(Paths.tildeAbbreviated(model))
        }

        let arguments = ["-m", model.path, "-f", wav.path, "-nt", "-np", "--no-prints",
                         "-l", WhisperTranscriber.language(config: config)]
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
    static func language(config: Config) -> String {
        let isEnglishOnly = config.whisperModelURL.lastPathComponent.contains(".en")
        if isEnglishOnly { return "en" }
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
