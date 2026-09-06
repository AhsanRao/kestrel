import AppKit
import Foundation
import os

/// Drives the whole loop: hotkey → record → transcribe → (screenshot + backend | cleanup + paste).
/// All UI touches happen on the main thread; audio, whisper and the CLIs run on `work`.
final class SessionCoordinator {
    let panel = PanelWindow()

    let log = Logger(subsystem: "dev.0xash.kestrel", category: "session")
    let work = DispatchQueue(label: "dev.0xash.kestrel.session", qos: .userInitiated)
    let captureQueue = DispatchQueue(label: "dev.0xash.kestrel.capture", qos: .userInitiated)

    private let hotkeys = HotkeyService()
    let audio = AudioCapture()
    let transcriber: Transcriber = WhisperTranscriber()
    let router = BackendRouter()
    let speech = SpeechOutput()
    let overlay = OverlayWindow()
    let selection = SelectionOverlay()
    let dragTracker = DragTracker()
    lazy var walkthrough = WalkthroughSession(overlay: overlay)

    var machine = SessionMachine()
    /// Kept alive for the whole walkthrough: the overlay needs its geometry to place the drawing.
    var pendingCapture: ScreenCapture?
    /// True once part of the answer has been read out while it streamed.
    var streamedSpeech = false
    /// Controls read out of the frontmost app for the walkthrough currently being planned.
    var scannedElements: [AXElementScanner.Element] = []
    /// The last few exchanges, so "the other one" has something to refer to.
    var conversation = Conversation()
    /// The region the user circled while holding the hotkey, in global AppKit points.
    var focusRegion: CGRect?
    var pendingCrop: URL?
    var listeningStartedAt: Date?
    private var accessibilityRetry: Timer?

    var config: Config { ConfigStore.shared.current }

    // MARK: - Lifecycle

    func start() {
        panel.onOpenPermission = { NSWorkspace.shared.open($0) }
        speech.onFinish = { [weak self] in self?.scheduleAutoHide() }
        audio.onAutoStop = { [weak self] url in self?.audioStoppedOnItsOwn(url) }
        walkthrough.onFinish = { [weak self] _ in self?.walkthroughEnded() }
        walkthrough.onAdvance = { [weak self] step in self?.walkthroughAdvanced(to: step) }
        dragTracker.onChange = { [weak self] points in self?.selection.update(points: points) }

        hotkeys.handler = { [weak self] action, phase in self?.handle(action, phase) }
        hotkeys.registrationFailure = { [weak self] combo in
            self?.fail(KestrelError.hotkeyRegistrationFailed(combo))
        }
        hotkeys.chordAborted = { [weak self] _ in self?.chordAborted() }
        hotkeys.accessibilityMissing = { [weak self] in self?.chordNeedsAccessibility() }
        hotkeys.start(with: config.hotkeys)
        applyConfigToPanel(config)

        ConfigStore.shared.addObserver { [weak self] config in
            self?.hotkeys.apply(config.hotkeys)
            self?.applyConfigToPanel(config)
        }
    }

    func stop() {
        dragTracker.end()
        selection.hide()
        accessibilityRetry?.invalidate()
        accessibilityRetry = nil
        hotkeys.stop()
        speech.stop()
        audio.stop()
    }

    /// The modifiers turned out to be the start of a real shortcut (⌃⌘K, ⌃⌘Q…), so the recording
    /// that the chord began is thrown away without a word.
    private func chordAborted() {
        guard machine.state == .listening else { return }
        audio.stop()
        apply(.cancelled)
        panel.hideImmediately()
    }

    /// A bare-chord hotkey cannot be seen without Accessibility. Ask for it, say why, and keep
    /// checking so the hotkey starts working the moment it is granted — no relaunch needed.
    private func chordNeedsAccessibility() {
        TextInjector.requestAccessibilityPermission()
        fail(KestrelError.hotkeyNeedsAccessibility(config.hotkeys.ask.display))
        guard accessibilityRetry == nil else { return }
        accessibilityRetry = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard TextInjector.hasAccessibilityPermission else { return }
            timer.invalidate()
            self.accessibilityRetry = nil
            self.hotkeys.apply(self.config.hotkeys)
            self.log.info("accessibility granted, chord hotkey live")
        }
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
}
