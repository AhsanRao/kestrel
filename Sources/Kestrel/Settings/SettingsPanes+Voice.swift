import SwiftUI

/// The second half of `SettingsPane`: the pages about speaking, listening, remembering, and the
/// dials nobody needs on a first run.
extension SettingsPane {
    // MARK: - Voice

    @ViewBuilder var voice: some View {
        Section {
            ToggleSetting(title: "Say answers out loud", isOn: model.binding(\.speakAnswers))
            ToggleSetting(title: "Little sounds as I go",
                          note: "A tick when I start listening, another when I'm done.",
                          isOn: model.binding(\.sounds))
        }
        Section("What I sound like") {
            Setting(title: "Engine") {
                Picker("", selection: model.binding(\.voiceEngine)) {
                    ForEach(Config.VoiceEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: SettingsPane.controlWidth)
            }
            Setting(title: "Which one") {
                HStack(spacing: 8) {
                    voicePicker
                    Button("Preview") { model.previewVoice() }
                }
            }
            if model.config.voiceEngine == .kokoro, !KokoroInstall.isReady {
                SettingWarning(text: "Not downloaded yet, so I'm on a macOS voice for now. Grab it "
                                   + "from setup whenever you like.",
                               actionTitle: "Open setup…", action: onOpenSetup)
            }
            if model.config.voiceEngine == .system, SystemSpeaker.hasOnlyCompactVoices {
                SettingWarning(text: "You've only got the compact voices — the robotic ones. Open "
                                   + "Spoken Content, then Manage Voices…, and grab a Premium one "
                                   + "like Ava or Zoe. I'll pick the best of what's there.",
                               actionTitle: "Open Spoken Content…",
                               action: model.openVoiceDownloads)
            }
        }
    }

    @ViewBuilder private var voicePicker: some View {
        if model.config.voiceEngine == .kokoro {
            Picker("", selection: model.binding(\.kokoroVoice)) {
                ForEach(KokoroVoice.all) { voice in
                    Text("\(voice.title) · \(voice.note)").tag(voice.id)
                }
            }
            .labelsHidden()
            .frame(width: SettingsPane.controlWidth)
        } else {
            Picker("", selection: model.optionalStringBinding(\.voiceIdentifier)) {
                Text("Best available").tag("")
                ForEach(model.voices, id: \.identifier) { voice in
                    Text(SystemSpeaker.describe(voice)).tag(voice.identifier)
                }
            }
            .labelsHidden()
            .frame(width: SettingsPane.controlWidth)
        }
    }

    // MARK: - Hearing

    @ViewBuilder var hearing: some View {
        Section {
            Setting(title: "Engine") {
                Picker("", selection: model.binding(\.transcriptionEngine)) {
                    ForEach(Config.TranscriptionEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: SettingsPane.controlWidth)
            }
            Setting(title: "Words to expect",
                    note: "Names, jargon, Roman Urdu — anything I'd otherwise mishear. Your audio "
                        + "never leaves this Mac, and it's English only: Roman Urdu comes out in "
                        + "English letters, which is how it's written anyway.") {
                TextField("", text: model.optionalStringBinding(\.transcriptionHint))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsPane.controlWidth)
            }
        }
        if model.config.transcriptionEngine == .whisper {
            Section("Whisper") {
                Setting(title: "Binary") {
                    TextField("", text: model.binding(\.whisperBinary))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsPane.controlWidth)
                }
                Setting(title: "Model") {
                    TextField("", text: model.binding(\.whisperModel))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsPane.controlWidth)
                }
            }
        }
    }

    // MARK: - Memory

    @ViewBuilder var memory: some View {
        Section {
            Setting(title: "What I remember about you",
                    note: "I read this before every answer. Keep it short and it stays useful.") {
                Button("Open…") { MemoryStore.openInEditor() }
            }
            SettingNote("It's a plain Markdown file at \(Paths.tildeAbbreviated(Paths.memory)).")
        }
    }

    // MARK: - Advanced

    @ViewBuilder var advanced: some View {
        Section("The island") {
            Stepper("Stick around for \(model.config.panelAutoHideSeconds)s",
                    value: model.binding(\.panelAutoHideSeconds), in: 2...120)
            Stepper("Screenshot up to \(model.config.screenshotMaxEdge)px wide",
                    value: model.binding(\.screenshotMaxEdge), in: 512...4096, step: 256)
        }
        Section("API keys — only if you need them") {
            Setting(title: "ANTHROPIC_API_KEY") {
                SecureField("", text: model.optionalStringBinding(\.apiKeys.anthropic))
                    .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsPane.controlWidth)
            }
            Setting(title: "OPENAI_API_KEY") {
                SecureField("", text: model.optionalStringBinding(\.apiKeys.openai))
                    .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: SettingsPane.controlWidth)
            }
            SettingNote("Leave these empty and I'll go through the CLIs on your own subscriptions. "
                        + "I'm built for one person — if you share this Mac, use keys.")
        }
        Section {
            Setting(title: "Start over",
                    note: "Puts every setting back the way it shipped. Your memory file and the "
                        + "downloaded voice stay where they are.") {
                Button("Reset…") { model.resetToDefaults() }
            }
            SettingNote("Everything here lives in \(Paths.tildeAbbreviated(Paths.config)).")
        }
    }
}
