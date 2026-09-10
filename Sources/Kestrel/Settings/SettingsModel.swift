import AppKit
import AVFoundation
import SwiftUI

/// Bridges `ConfigStore` to SwiftUI bindings. Every setter writes straight through to
/// `~/.kestrel/config.json`, so the file and the UI can never drift apart.
final class SettingsModel: ObservableObject {
    @Published var config: Config = ConfigStore.shared.current

    init() {
        ConfigStore.shared.addObserver { [weak self] config in
            guard let self, config != self.config else { return }
            self.config = config
        }
    }

    /// A binding that persists on write.
    func binding<T: Equatable>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { newValue in
                guard self.config[keyPath: keyPath] != newValue else { return }
                ConfigStore.shared.update { $0[keyPath: keyPath] = newValue }
                self.config = ConfigStore.shared.current
                if keyPath == \Config.launchAtLogin {
                    LaunchAtLogin.sync(with: ConfigStore.shared.current.launchAtLogin)
                }
            }
        )
    }

    /// String binding for an optional field, where empty text means "use the CLI default".
    func optionalStringBinding(_ keyPath: WritableKeyPath<Config, String?>) -> Binding<String> {
        Binding(
            get: { self.config[keyPath: keyPath] ?? "" },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                let stored: String? = trimmed.isEmpty ? nil : trimmed
                guard self.config[keyPath: keyPath] != stored else { return }
                ConfigStore.shared.update { $0[keyPath: keyPath] = stored }
                self.config = ConfigStore.shared.current
            }
        )
    }

    var voices: [AVSpeechSynthesisVoice] { SystemSpeaker.rankedVoices() }

    /// Back to the shipped values, after a confirmation. The memory file and the downloaded voice
    /// are deliberately left alone: they are the user's own work and the slow part of setup, and
    /// neither is a setting.
    func resetToDefaults() {
        let alert = NSAlert()
        alert.messageText = "Put every setting back?"
        alert.informativeText = "Your shortcuts, voice and preferences go back to the way Kestrel "
            + "shipped. What I remember about you, and the voice you downloaded, stay where they are."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ConfigStore.shared.update { $0 = Config.defaults }
        config = ConfigStore.shared.current
        LaunchAtLogin.sync(with: config.launchAtLogin)
    }

    /// Opens System Settings ▸ Accessibility ▸ Spoken Content, the only place macOS lets you
    /// install the neural voices. It opens the pane; the download itself is Apple's "Manage
    /// Voices…" sheet, which Kestrel cannot drive.
    ///
    /// Bundle id is the modern Settings extension. The old `com.apple.preference.universalaccess`
    /// pane still exists but its anchors no longer resolve.
    func openVoiceDownloads() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Speech",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func previewVoice() {
        let output = SpeechOutput()
        output.speak("Kestrel is ready. Hold the hotkey and ask about your screen.", config: config)
        // Held only for the length of the utterance; the synthesizer keeps itself alive while speaking.
        previewHolder = output
    }

    private var previewHolder: SpeechOutput?
}
