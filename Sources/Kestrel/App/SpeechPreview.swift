import AppKit
import Foundation

/// Reads `KESTREL_PREVIEW_SPEECH` aloud through the real `SpeechOutput`, then exits. Sentences go
/// in one at a time, as `SessionCoordinator` feeds them.
///
/// The synthesizer is a subprocess with fixed flags; what can go wrong is the queueing around it —
/// play order, staying ahead of the ear, whether `onFinish` arrives. None of it unit-testable.
enum SpeechPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_SPEECH"] != nil
    }

    /// Runs the real download and install. The onboarding button is the only other way in, and a
    /// button cannot be pressed from a script.
    static var isDownloadRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_VOICE_DOWNLOAD"] != nil
    }

    /// `"<engine.tar.bz2>:<model.tar.bz2>"` — installs tarballs already on disk, so unpacking and
    /// layout can be checked without waiting out a slow network.
    static var installTarballs: (engine: URL, model: URL)? {
        let raw = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_VOICE_INSTALL"] ?? ""
        let parts = raw.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return nil }
        return (URL(fileURLWithPath: parts[0]), URL(fileURLWithPath: parts[1]))
    }

    static func runInstall(_ tarballs: (engine: URL, model: URL)) {
        do {
            print("unpacking \(tarballs.engine.lastPathComponent)…")
            try KokoroInstall.installEngine(fromExtracted: KokoroDownloader.extract(tarballs.engine))
            print("unpacking \(tarballs.model.lastPathComponent)…")
            try KokoroInstall.installModel(fromExtracted: KokoroDownloader.extract(tarballs.model))
            print("isReady: \(KokoroInstall.isReady)")
        } catch {
            print("FAILED — \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }

    @MainActor
    static func runDownload() {
        let downloader = KokoroDownloader()
        let started = Date()
        var last = ""
        downloader.start()
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            MainActor.assumeIsolated {
                let elapsed = String(format: "%6.1fs", Date().timeIntervalSince(started))
                switch downloader.phase {
                case .downloading(let received, let total):
                    let line = "\(elapsed)  downloading \(received * 100 / max(total, 1))%"
                    if line != last { print(line); last = line }
                case .installing:
                    if last != "installing" { print("\(elapsed)  installing"); last = "installing" }
                case .done:
                    print("\(elapsed)  done — isReady=\(KokoroInstall.isReady)")
                    timer.invalidate()
                    NSApp.terminate(nil)
                case .failed(let message):
                    print("\(elapsed)  FAILED — \(message)")
                    timer.invalidate()
                    NSApp.terminate(nil)
                case .idle:
                    break
                }
            }
        }
    }

    static func run(on coordinator: SessionCoordinator) {
        let text = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_SPEECH"] ?? ""
        let config = ConfigStore.shared.current
        let started = Date()
        let sentences = text
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) + "." }
            .filter { $0.count > 1 }

        print("engine: \(config.voiceEngine.rawValue)   voice: \(config.kokoroVoice)")
        print("kokoro installed: \(KokoroInstall.isReady)")
        print("sentences: \(sentences.count)")

        coordinator.speech.onFinish = {
            print(String(format: "finished after %.2fs", Date().timeIntervalSince(started)))
            NSApp.terminate(nil)
        }

        for (index, sentence) in sentences.enumerated() {
            let spoke = index == 0
                ? coordinator.speech.speak(sentence, config: config)
                : coordinator.speech.enqueue(sentence, config: config)
            print("  [\(index)] spoke=\(spoke)  \(sentence.prefix(48))")
        }

        // Fail loudly rather than hang forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            print("TIMED OUT — onFinish never arrived")
            NSApp.terminate(nil)
        }
    }
}
