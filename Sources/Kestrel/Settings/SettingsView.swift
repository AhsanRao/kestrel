import AVFoundation
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Which tab is showing. A binding rather than TabView's own state so `SettingsPreview` can
    /// open straight onto one.
    @State private var tab = SettingsView.initialTab

    /// `KESTREL_PREVIEW_SETTINGS` names a tab, for the preview harness.
    static var initialTab: Int {
        switch ProcessInfo.processInfo.environment["KESTREL_PREVIEW_SETTINGS"] {
        case "voice": return 1
        case "advanced": return 2
        default: return 0
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            general.tabItem { Label("Basics", systemImage: "gearshape") }.tag(0)
            speech.tabItem { Label("Voice", systemImage: "waveform") }.tag(1)
            advanced.tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .padding(16)
        .frame(width: 470, height: 580)
        .background(GlassBackground().ignoresSafeArea())
        // A settling arrival, matching the panel and onboarding rather than the flat pop of a
        // stock window.
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appeared = true }
        }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Picker("Brain", selection: model.binding(\.backend)) {
                ForEach(BackendKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            HotkeyRecorder(title: "Ask me something (hold)", binding: model.binding(\.hotkeys.ask))
            HotkeyRecorder(title: "Type for me (tap)", binding: model.binding(\.hotkeys.dictate),
                           allowsBareChord: false)
            if model.config.hotkeys.ask.isModifierOnly {
                Text("Bare modifiers go through Accessibility. Hold it a moment to start me — "
                     + "hit any key while it's down and I'll back off, so your normal "
                     + "\(model.config.hotkeys.ask.display) shortcuts still work.")
                    .font(.caption).foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Toggle("Tidy up what I type for you", isOn: model.binding(\.cleanupDictation))
            Toggle("Circle what I'm talking about", isOn: model.binding(\.answerAnnotations))
            Text("When the answer is \"that button there\", I'll draw a ring around it rather "
                 + "than describe where it is.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Let you circle part of the screen as you ask", isOn: model.binding(\.spatialContext))
            Picker("What I look at", selection: model.binding(\.captureMode)) {
                ForEach(Config.CaptureMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("The front window keeps small text readable. Go wider only when your question "
                 + "spans more than one window.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("How I put text in", selection: model.binding(\.injectMode)) {
                Text("Paste (⌘V)").tag(Config.InjectMode.paste)
                Text("Typing").tag(Config.InjectMode.type)
            }
            Toggle("Start up with your Mac", isOn: model.binding(\.launchAtLogin))

            Section {
                Button("Open what I remember") { MemoryStore.openInEditor() }
                Text("I read this before every answer. Keep it short and it stays useful.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.config.hotkeys.ask.isModifierOnly)
    }

    // MARK: - Speech

    private var speech: some View {
        Form {
            Toggle("Say answers out loud", isOn: model.binding(\.speakAnswers))
            Toggle("Little sounds as I go", isOn: model.binding(\.sounds))

            Picker("Voice", selection: model.binding(\.voiceEngine)) {
                ForEach(Config.VoiceEngine.allCases, id: \.self) { Text($0.title).tag($0) }
            }

            if model.config.voiceEngine == .kokoro {
                HStack {
                    Picker("Which one", selection: model.binding(\.kokoroVoice)) {
                        ForEach(KokoroVoice.all) { voice in
                            Text("\(voice.title) · \(voice.note)").tag(voice.id)
                        }
                    }
                    Button("Preview") { model.previewVoice() }
                }
                if !KokoroInstall.isReady {
                    Label("Not downloaded yet, so I'm on a macOS voice for now. Grab it from the "
                          + "setup window whenever you like.",
                          systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    Picker("Which one", selection: model.optionalStringBinding(\.voiceIdentifier)) {
                        Text("Best available").tag("")
                        ForEach(model.voices, id: \.identifier) { voice in
                            Text(SystemSpeaker.describe(voice)).tag(voice.identifier)
                        }
                    }
                    Button("Preview") { model.previewVoice() }
                }
            }
            if model.config.voiceEngine == .system, SystemSpeaker.hasOnlyCompactVoices {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("You've only got the compact voices — the robotic ones. Open Spoken Content, "
                             + "then Manage Voices…, and grab a Premium one like Ava or Zoe. "
                             + "I'll pick the best of what's there.")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Spoken Content…") { model.openVoiceDownloads() }
                            .controlSize(.small)
                    }
                }
            }

            Section("Hearing you") {
                Picker("Engine", selection: model.binding(\.transcriptionEngine)) {
                    ForEach(Config.TranscriptionEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                TextField("Words to expect — names, jargon, Roman Urdu",
                          text: model.optionalStringBinding(\.transcriptionHint))
                if model.config.transcriptionEngine == .whisper {
                    TextField("Whisper binary", text: model.binding(\.whisperBinary))
                    TextField("Whisper model", text: model.binding(\.whisperModel))
                }
                Text("Your audio never leaves this Mac. English only — Roman Urdu comes out in "
                     + "English letters, which is how it's written anyway.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Advanced

    private var advanced: some View {
        Form {
            Section("Brains") {
                ModelPicker(title: "Claude", options: ModelOption.claude,
                            value: model.optionalStringBinding(\.claudeModel))
                TextField("Codex model", text: model.optionalStringBinding(\.codexModel),
                          prompt: Text("Whatever the CLI picks"))
                Toggle("Send quick questions to Codex", isOn: model.binding(\.autoRoute))
            }
            Section("The island") {
                Stepper("Stick around for \(model.config.panelAutoHideSeconds)s",
                        value: model.binding(\.panelAutoHideSeconds), in: 2...120)
                Stepper("Screenshot up to \(model.config.screenshotMaxEdge)px wide",
                        value: model.binding(\.screenshotMaxEdge), in: 512...4096, step: 256)
            }
            Section("API keys — only if you need them") {
                SecureField("ANTHROPIC_API_KEY", text: model.optionalStringBinding(\.apiKeys.anthropic))
                SecureField("OPENAI_API_KEY", text: model.optionalStringBinding(\.apiKeys.openai))
                Text("Leave these empty and I'll go through the CLIs on your own subscriptions. "
                     + "I'm built for one person — if you share this Mac, use keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text("Everything here lives in \(Paths.tildeAbbreviated(Paths.config))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
