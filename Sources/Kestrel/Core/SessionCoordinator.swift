import AppKit
import Foundation
import os

/// Drives the whole loop: hotkey → record → transcribe → (screenshot + backend | cleanup + paste).
/// All UI touches happen on the main thread; audio, whisper and the CLIs run on `work`.
final class SessionCoordinator {
    let panel = PanelWindow()

    let log = Logger(subsystem: "dev.0xash.kestrel", category: "session")
    let work = DispatchQueue(label: "dev.0xash.kestrel.session", qos: .userInitiated)

    private let hotkeys = HotkeyService()
    private let audio = AudioCapture()
    let transcriber: Transcriber = WhisperTranscriber()
    let router = BackendRouter()
    let speech = SpeechOutput()
    let overlay = OverlayWindow()
    lazy var walkthrough = WalkthroughSession(overlay: overlay)

    var machine = SessionMachine()
    /// Kept alive for the whole walkthrough: the overlay needs its geometry to place the drawing.
    var pendingCapture: ScreenCapture?
    private var listeningStartedAt: Date?

    var config: Config { ConfigStore.shared.current }

    // MARK: - Lifecycle

    func start() {
        panel.onOpenPermission = { NSWorkspace.shared.open($0) }
        speech.onFinish = { [weak self] in self?.scheduleAutoHide() }
        audio.onAutoStop = { [weak self] url in self?.audioStoppedOnItsOwn(url) }
        walkthrough.onFinish = { [weak self] _ in self?.walkthroughEnded() }
        walkthrough.onAdvance = { [weak self] step in self?.walkthroughAdvanced(to: step) }

        hotkeys.handler = { [weak self] action, phase in self?.handle(action, phase) }
        hotkeys.registrationFailure = { [weak self] combo in
            self?.fail(KestrelError.hotkeyRegistrationFailed(combo))
        }
        hotkeys.start(with: config.hotkeys)
        applyConfigToPanel(config)

        ConfigStore.shared.addObserver { [weak self] config in
            self?.hotkeys.apply(config.hotkeys)
            self?.applyConfigToPanel(config)
        }
    }

    func stop() {
        hotkeys.stop()
        speech.stop()
        audio.stop()
    }

    private func applyConfigToPanel(_ config: Config) {
        panel.model.backend = config.backend
        panel.model.askHint = config.hotkeys.ask.display
        panel.model.dictateHint = config.hotkeys.dictate.display
    }

    // MARK: - Hotkeys

    private func handle(_ action: HotkeyService.Action, _ phase: HotkeyService.Phase) {
        let event: SessionEvent?
        switch (action, phase) {
        case (.ask, .pressed): event = .askPressed
        case (.ask, .released): event = .askReleased
        case (.dictate, .pressed): event = .dictateToggled
        case (.dictate, .released): event = nil        // toggle acts on press only
        }
        guard let event else { return }
        apply(event)
    }

    func apply(_ event: SessionEvent) {
        let effects = machine.apply(event)
        panel.model.state = machine.state
        for effect in effects { perform(effect) }
        render()
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .startListening: beginRecording(intent: .ask)
        case .startDictating: beginRecording(intent: .dictation)
        case .finishListening: finishRecording(intent: .ask)
        case .finishDictating: finishRecording(intent: .dictation)
        case .interruptSpeech: speech.stop()
        case .pulse: panel.pulse()
        case .clearOverlay: walkthrough.stop(completed: false, notify: false)
        case .reset: reset()
        }
    }

    // MARK: - Recording

    private func beginRecording(intent: SessionIntent) {
        panel.model.transcript = ""
        panel.model.answer = ""
        panel.model.permissionURL = nil
        panel.show()
        listeningStartedAt = Date()

        AudioCapture.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { self.fail(KestrelError.microphoneDenied); return }
            do {
                try self.audio.start(maxDuration: intent == .ask ? 60 : 600)
            } catch AudioCapture.Failure.permissionDenied {
                self.fail(KestrelError.microphoneDenied)
            } catch {
                self.fail(KestrelError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    private func finishRecording(intent: SessionIntent) {
        let wav = audio.stop()
        guard let wav else {
            // Under 300 ms: an accidental tap, not a question.
            apply(.cancelled)
            panel.hideImmediately()
            return
        }
        let maxEdge = config.screenshotMaxEdge
        work.async { [weak self] in
            guard let self else { return }
            if intent == .ask {
                do {
                    self.pendingCapture = try ScreenGrabber.capture(maxEdge: maxEdge)
                } catch {
                    self.finish(with: error)
                    return
                }
            }
            self.transcribe(wav, intent: intent)
        }
    }

    /// The engine stopped by itself: max duration hit, or the input device went away.
    private func audioStoppedOnItsOwn(_ url: URL?) {
        guard machine.state == .listening || machine.state == .dictating else { return }
        let intent: SessionIntent = machine.state == .dictating ? .dictation : .ask
        guard url != nil else { apply(.cancelled); panel.hideImmediately(); return }
        apply(intent == .ask ? .askReleased : .dictateToggled)
    }
}
