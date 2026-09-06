import AVFoundation
import CoreGraphics
import Foundation

/// The in-app twin of `scripts/check-deps.sh`, shown from the menu bar.
enum DependencyCheck {
    struct Item {
        var name: String
        var ok: Bool
        var detail: String
    }

    struct Report {
        var items: [Item]
        var allGood: Bool { items.allSatisfy(\.ok) }
        var summary: String {
            items.map { "\($0.ok ? "✓" : "✗")  \($0.name) — \($0.detail)" }.joined(separator: "\n")
        }
    }

    static func run(config: Config) -> Report {
        var items: [Item] = []

        for name in ["claude", "codex"] {
            if let url = CLIRunner.locate(name) {
                items.append(Item(name: name, ok: true, detail: url.path))
            } else {
                let fix = name == "claude"
                    ? "install Claude Code, then run: claude auth"
                    : "npm i -g @openai/codex && codex login"
                items.append(Item(name: name, ok: false, detail: "not found — \(fix)"))
            }
        }

        let whisper = config.whisperBinaryURL
        items.append(FileManager.default.isExecutableFile(atPath: whisper.path)
            ? Item(name: "whisper-cli", ok: true, detail: whisper.path)
            : Item(name: "whisper-cli", ok: false, detail: "not found — brew install whisper-cpp"))

        let model = config.whisperModelURL
        items.append(FileManager.default.fileExists(atPath: model.path)
            ? Item(name: "whisper model", ok: true, detail: Paths.tildeAbbreviated(model))
            : Item(name: "whisper model", ok: false, detail: "missing — run scripts/download-whisper-model.sh"))

        items.append(Item(name: "Microphone", ok: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                          detail: "System Settings ▸ Privacy & Security ▸ Microphone"))
        items.append(Item(name: "Screen Recording", ok: CGPreflightScreenCaptureAccess(),
                          detail: "System Settings ▸ Privacy & Security ▸ Screen Recording"))
        items.append(Item(name: "Accessibility", ok: AXIsProcessTrusted(),
                          detail: "needed for dictation paste"))

        return Report(items: items)
    }
}
