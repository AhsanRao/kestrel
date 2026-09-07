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
    let sounds = SoundBoard()
    let overlay = OverlayWindow()
    let selection = SelectionOverlay()
    let dragTracker = DragTracker()
    lazy var walkthrough = WalkthroughSession(overlay: overlay)
    let agentOverlay = AgentOverlay()
    let annotations = AnnotationOverlay()
    let actuator = Actuator()
    let escapeWatcher = EscapeWatcher()
    var activeRun: ActionRunner?
    /// Told whenever the session moves, so the menu bar can reflect it.
    var onStateChange: ((SessionState) -> Void)?

    var machine = SessionMachine()
    /// Kept alive for the whole walkthrough: the overlay needs its geometry to place the drawing.
    var pendingCapture: ScreenCapture?
    /// True once part of the answer has been read out while it streamed.
    var streamedSpeech = false
    /// Controls read out of the frontmost app for the answer currently being planned.
    var scannedElements: [AXElementScanner.Element] = []
    /// How many times the current walkthrough has been extended onto a new screen.
    var walkthroughContinuations = 0
    /// A walkthrough that runs past one screen is picked up again this many times before Kestrel
    /// stops on its own. Enough for a menu ▸ dialog ▸ confirm route; short of a loop.
    static let maximumContinuations = 3
    /// How much of the control list a plain answer is offered. A walkthrough gets all of it; an
    /// answer only needs enough to point at what it is talking about.
    static let maximumPointableControls = 120
    /// Apps the user has said yes to during the run in flight. Cleared when the run ends.
    var grantedApps: Set<String> = []
    /// How many times one request may be re-planned after opening an app. Enough for launch ▸ act,
    /// and for one correction after it; short of a loop.
    static let maximumActionRounds = 3
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
        audio.onLevel = { [weak self] level in self?.panel.model.level = Double(level) }
        walkthrough.onFinish = { [weak self] _ in self?.walkthroughEnded() }
        walkthrough.onAdvance = { [weak self] step in self?.walkthroughAdvanced(to: step) }
        walkthrough.onNeedsMore = { [weak self] done in self?.continueWalkthrough(after: done) }
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
        sounds.stop()
        annotations.hide()
        escapeWatcher.stop()
        activeRun?.cancel()
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
        onStateChange?(machine.state)
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
        case .clearOverlay:
            walkthroughContinuations = 0
            walkthrough.stop(completed: false, notify: false)
            escapeWatcher.stop()
            agentOverlay.hide()
            annotations.hide()
        case .reset: reset()
        }
    }
}
