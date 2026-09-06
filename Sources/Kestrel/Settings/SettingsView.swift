import AVFoundation
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            speech.tabItem { Label("Speech", systemImage: "waveform") }
            advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(width: 460, height: 560)
    }

    // MARK: - General

    private var general: some View {
        Form {
            Picker("Backend", selection: model.binding(\.backend)) {
                ForEach(BackendKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            HotkeyRecorder(title: "Ask (hold)", binding: model.binding(\.hotkeys.ask))
            HotkeyRecorder(title: "Dictate (toggle)", binding: model.binding(\.hotkeys.dictate))

            Toggle("Clean up dictated text with the model", isOn: model.binding(\.cleanupDictation))
            Picker("Insert dictation by", selection: model.binding(\.injectMode)) {
                Text("Paste (⌘V)").tag(Config.InjectMode.paste)
                Text("Typing").tag(Config.InjectMode.type)
            }
            Toggle("Launch at login", isOn: model.binding(\.launchAtLogin))

            Section {
                Button("Open memory file (KESTREL.md)") { MemoryStore.openInEditor() }
                Text("Loaded automatically by both CLIs on every request. Keep it short.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Speech

    private var speech: some View {
        Form {
            Toggle("Speak answers out loud", isOn: model.binding(\.speakAnswers))

            Picker("Voice", selection: model.optionalStringBinding(\.voiceIdentifier)) {
                Text("System default").tag("")
                ForEach(model.voices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                }
            }
            HStack {
                Text("Rate")
                Slider(value: model.binding(\.voiceRate), in: 0.3...0.7)
                Button("Preview") { model.previewVoice() }
            }

            Section("Transcription") {
                TextField("Whisper binary", text: model.binding(\.whisperBinary))
                TextField("Whisper model", text: model.binding(\.whisperModel))
                TextField("Language (auto, en, ur…)", text: model.binding(\.language))
                Text("Audio never leaves this Mac. For Urdu or mixed speech use ggml-small.bin.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced

    private var advanced: some View {
        Form {
            Section("Models") {
                TextField("Claude model (blank = CLI default)", text: model.optionalStringBinding(\.claudeModel))
                TextField("Codex model (blank = CLI default)", text: model.optionalStringBinding(\.codexModel))
                Toggle("Auto-route short questions to Codex", isOn: model.binding(\.autoRoute))
            }
            Section("Panel") {
                Stepper("Auto-hide after \(model.config.panelAutoHideSeconds)s",
                        value: model.binding(\.panelAutoHideSeconds), in: 2...120)
                Stepper("Screenshot max edge \(model.config.screenshotMaxEdge)px",
                        value: model.binding(\.screenshotMaxEdge), in: 512...4096, step: 256)
            }
            Section("API keys (optional)") {
                SecureField("ANTHROPIC_API_KEY", text: model.optionalStringBinding(\.apiKeys.anthropic))
                SecureField("OPENAI_API_KEY", text: model.optionalStringBinding(\.apiKeys.openai))
                Text("Leave blank to use your Claude and ChatGPT subscriptions through the CLIs. "
                     + "Kestrel is single-user: if you share it, use API keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Config file: \(Paths.tildeAbbreviated(Paths.config))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
