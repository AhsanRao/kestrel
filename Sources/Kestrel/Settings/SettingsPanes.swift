import SwiftUI

/// One page of settings. Every pane is a `Form` of `Setting` rows, so they all indent, wrap and
/// space the same way without each one saying so.
struct SettingsPane: View {
    let section: SettingsSection
    @ObservedObject var model: SettingsModel
    var onOpenSetup: () -> Void
    var onCheckInstalled: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One width for every control in the right-hand column. Picked to hold the longest value any
    /// of the pickers offers — "Kokoro (neural, on this Mac)" — without an ellipsis.
    static let controlWidth: CGFloat = 212

    var body: some View {
        Form {
            switch section {
            case .brain: brain
            case .shortcuts: shortcuts
            case .seeing: seeing
            case .typing: typing
            case .voice: voice
            case .hearing: hearing
            case .memory: memory
            case .advanced: advanced
            case .about: EmptyView()   // AboutPane is not a Form; SettingsView shows it directly
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2),
                   value: model.config.hotkeys.ask.isModifierOnly)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.config.voiceEngine)
    }

    // MARK: - Brain

    @ViewBuilder private var brain: some View {
        Section {
            Picker("Who answers", selection: model.binding(\.backend)) {
                ForEach(BackendKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            SettingNote("Both run on your own subscription, through the CLI you already signed in "
                        + "to. Nothing goes to an API you pay per token for.")
        }
        Section("Models") {
            ModelPicker(title: "Claude", options: ModelOption.claude,
                        value: model.optionalStringBinding(\.claudeModel))
            Setting(title: "Codex") {
                TextField("", text: model.optionalStringBinding(\.codexModel),
                          prompt: Text("Whatever the CLI picks"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: SettingsPane.controlWidth)
            }
            ToggleSetting(title: "Send quick questions to Codex",
                          note: "Short factual questions go to whichever is faster. Anything about "
                              + "your screen still goes to the one you picked.",
                          isOn: model.binding(\.autoRoute))
        }
    }

    // MARK: - Shortcuts

    @ViewBuilder private var shortcuts: some View {
        Section {
            HotkeyRecorder(title: "Ask me something (hold)", binding: model.binding(\.hotkeys.ask))
            HotkeyRecorder(title: "Type for me (tap)", binding: model.binding(\.hotkeys.dictate),
                           allowsBareChord: false)
            if model.config.hotkeys.ask.isModifierOnly {
                SettingNote("Bare modifiers go through Accessibility. Hold it a moment to start me "
                            + "— hit any key while it's down and I'll back off, so your normal "
                            + "\(model.config.hotkeys.ask.display) shortcuts still work.")
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        Section {
            ToggleSetting(title: "Start up with your Mac", isOn: model.binding(\.launchAtLogin))
        }
    }

    // MARK: - Seeing

    @ViewBuilder private var seeing: some View {
        Section {
            Setting(title: "What I look at",
                    note: "The front window keeps small text readable. Go wider only when your "
                        + "question spans more than one window.") {
                Picker("", selection: model.binding(\.captureMode)) {
                    ForEach(Config.CaptureMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: SettingsPane.controlWidth)
            }
        }
        Section("Pointing things out") {
            ToggleSetting(title: "Circle what I'm talking about",
                          note: "When the answer is \"that button there\", I'll draw a ring around "
                              + "it rather than describe where it is.",
                          isOn: model.binding(\.answerAnnotations))
            ToggleSetting(title: "Let you circle part of the screen as you ask",
                          note: "Drag a box while the hotkey is down and I'll look only at that.",
                          isOn: model.binding(\.spatialContext))
        }
    }

    // MARK: - Typing

    @ViewBuilder private var typing: some View {
        Section {
            Setting(title: "How I put text in",
                    note: "Paste is instant. Typing is slower but works in the few apps that "
                        + "refuse a paste.") {
                Picker("", selection: model.binding(\.injectMode)) {
                    Text("Paste (⌘V)").tag(Config.InjectMode.paste)
                    Text("Typing").tag(Config.InjectMode.type)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: SettingsPane.controlWidth)
            }
            ToggleSetting(title: "Tidy up what I type for you",
                          note: "Punctuation, capitals, and the ums taken out.",
                          isOn: model.binding(\.cleanupDictation))
        }
    }
}
