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

    var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") || $0.language.hasPrefix(Locale.current.language.languageCode?.identifier ?? "en") }
            .sorted { $0.name < $1.name }
    }

    func previewVoice() {
        let output = SpeechOutput()
        output.speak("Kestrel is ready. Hold the hotkey and ask about your screen.", config: config)
        // Held only for the length of the utterance; the synthesizer keeps itself alive while speaking.
        previewHolder = output
    }

    private var previewHolder: SpeechOutput?
}
