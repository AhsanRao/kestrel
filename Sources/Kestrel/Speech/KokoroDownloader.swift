import Foundation
import os

/// Fetches and installs Kokoro, reporting progress for the onboarding row (spec §8.9).
///
/// Both pieces are pinned to an exact release: drifting flags or a reordered speaker table would
/// break quietly rather than loudly.
@MainActor
final class KokoroDownloader: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, total: Int64)
        case installing
        case done
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    var isBusy: Bool {
        switch phase {
        case .downloading, .installing: return true
        default: return false
        }
    }

    /// 0…1 across both files, so the bar fills once.
    var fraction: Double {
        switch phase {
        case .downloading(let received, let total):
            return total > 0 ? min(1, Double(received) / Double(total)) : 0
        case .installing: return 1
        case .done: return 1
        default: return 0
        }
    }

    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "speech")
    private static let engineURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.7/sherpa-onnx-v1.13.7-osx-arm64-shared.tar.bz2")!
    private static let modelURL = URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2")!
    /// Full precision, not int8: measured 3.6x real time against int8's 1.5x on Apple Silicon, so
    /// quantizing would cost quality and buy only a smaller download.
    ///
    /// Published content lengths, for one bar across two downloads.
    private static let engineBytes: Int64 = 20_262_139
    private static let modelBytes: Int64 = 349_906_910
    static var totalBytes: Int64 { engineBytes + modelBytes }

    private var task: Task<Void, Never>?

    func start() {
        guard !isBusy else { return }
        phase = .downloading(received: 0, total: Self.totalBytes)
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    private func run() async {
        do {
            let staging = Paths.tmp.appendingPathComponent("kokoro-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let engine = try await download(Self.engineURL, to: staging, alreadyReceived: 0)
            let model = try await download(Self.modelURL, to: staging, alreadyReceived: Self.engineBytes)

            phase = .installing
            try await Task.detached(priority: .userInitiated) {
                let engineDirectory = try KokoroDownloader.extract(engine)
                try KokoroInstall.installEngine(fromExtracted: engineDirectory)
                let modelDirectory = try KokoroDownloader.extract(model)
                try KokoroInstall.installModel(fromExtracted: modelDirectory)
            }.value

            guard KokoroInstall.isReady else {
                throw KestrelError.speech("The voice installed but is missing a file — try again.")
            }
            ConfigStore.shared.update { $0.voiceEngine = .kokoro }
            phase = .done
        } catch is CancellationError {
            phase = .idle
        } catch {
            Self.log.error("kokoro download failed: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL, to directory: URL, alreadyReceived: Int64) async throws -> URL {
        let total = Self.totalBytes
        return try await FileDownload.fetch(url, to: directory.appendingPathComponent(url.lastPathComponent)) { written in
            Task { @MainActor [weak self] in
                guard let self, self.isBusy else { return }
                self.phase = .downloading(received: alreadyReceived + written, total: total)
            }
        }
    }

    /// bzip2, unpacked with the system tar.
    nonisolated static func extract(_ tarball: URL) throws -> URL {
        let directory = tarball.deletingLastPathComponent()
            .appendingPathComponent(tarball.lastPathComponent + "-out", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xjf", tarball.path, "-C", directory.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw KestrelError.speech("The voice download could not be unpacked.")
        }
        return directory
    }
}
