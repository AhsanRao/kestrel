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
    /// Separate from `captureQueue`: the screenshot is a subprocess and the scan is Accessibility
    /// traffic, so putting them on one queue would make each wait for the other.
    let scanQueue = DispatchQueue(label: "dev.0xash.kestrel.scan", qos: .userInitiated)

    private let hotkeys = HotkeyService()
    let audio = AudioCapture()
    let transcriber: Transcriber = RoutingTranscriber()
    let router = BackendRouter()
    let speech = SpeechOutput()
    let sounds = SoundBoard()
    let selection = SelectionOverlay()
    let dragTracker = DragTracker()
    let annotations = AnnotationOverlay()
    let escapeWatcher = EscapeWatcher()
    /// Told whenever the session moves, so the menu bar can reflect it.
    var onStateChange: ((SessionState) -> Void)?

    var machine = SessionMachine()
    /// Kept alive until the answer lands: the crop is cut from it, and it is deleted either way.
    var pendingCapture: ScreenCapture?
    /// True once part of the answer has been read out while it streamed.
    var streamedSpeech = false
    /// The "let me look" line, waiting to see whether the answer beats it.
    var pendingAcknowledgement: DispatchWorkItem?
    /// True once it has been said, so the first real sentence queues behind it instead of cutting
    /// it off mid-word.
    var spokeAcknowledgement = false
    /// True once a streamed answer has reached its `DRAFT:` line: nothing after it is spoken.
    var streamingDraft = false
    /// The screen as it was when the hotkey was released, read alongside the transcript.
    var pendingScreen: ScreenSnapshot?
    /// Controls read out of the frontmost app for the answer currently being planned.
    var scannedElements: [AXElementScanner.Element] = []
    /// How much of the control list an answer is offered — enough to point at what it is talking
    /// about, short of a list so long the model loses its place in it.
    static let maximumPointableControls = 120
    /// The last few exchanges, so "the other one" has something to refer to.
    var conversation = Conversation()
    /// The region the user circled while holding the hotkey, in global AppKit points.
    var focusRegion: CGRect?
    var pendingCrop: URL?
    var listeningStartedAt: Date?
    /// The live engine, while a dictation is being typed as it is spoken. Nil for a recorded take.
    var live: LiveDictating?
    /// Everything this take has already put into the app. Empty also means nothing has been typed
    /// yet, which is what decides whether the next phrase needs a space in front of it.
    var liveText = ""
    /// The engine's running guess at the phrase still being said, kept so a phrase cut by the
    /// chord's release is not lost if its final result has not landed yet.
    var liveGuess = ""
    /// Questions heard while one was still being answered, in the order they were said.
    var phrases: [String] = []
    /// Where the streaming engine comes from. The probe swaps in one that says scripted phrases,
    /// which is how the live-ask flow is exercised without a microphone.
    var makeLiveEngine: (Config) -> LiveDictating? = { LiveDictation.make(for: $0) }
    /// The tools `claude -p` is offered, served from inside the app (spec §8.18).
    let toolServer = MCPSocketServer(path: Paths.mcpSocket)
    /// The hands behind the question in flight, if it was allowed any.
    var acting: ActionSession?
    /// Whoever is blocked waiting for the user's yes or no.
    var pendingDecision: ((Bool) -> Void)?
    /// Steps the last question took, kept for the probe's report after the session is gone.
    var lastActingSteps = 0
    /// Which take the work in flight belongs to. Bumped by every new take and every Esc, on the
    /// main thread; a result that comes back carrying an older number is for a question the user
    /// has already walked away from, and is dropped. Without this, an answer cancelled with Esc
    /// landed on the *next* question — ending its action session, so every tool call after that
    /// was refused as "cancelled" and the model ground round to the step cap, and deleting its
    /// screenshot from under it.
    var generation = 0
    private var accessibilityRetry: Timer?

    var config: Config { ConfigStore.shared.current }

    // MARK: - Lifecycle

    func start() {
        Jev.warmUp(config: config.jev)
        panel.onOpenPermission = { NSWorkspace.shared.open($0) }
        speech.onFinish = { [weak self] in self?.scheduleAutoHide() }
        audio.onAutoStop = { [weak self] url in self?.audioStoppedOnItsOwn(url) }
        audio.onLevel = { [weak self] level in self?.panel.model.level = Double(level) }
        dragTracker.onChange = { [weak self] points in self?.selection.update(points: points) }
        annotations.onHide = { [weak self] in self?.updateEscapeWatch() }

        hotkeys.handler = { [weak self] action, phase in self?.handle(action, phase) }
        hotkeys.registrationFailure = { [weak self] combo in
            self?.fail(KestrelError.hotkeyRegistrationFailed(combo))
        }
        hotkeys.chordAborted = { [weak self] _ in self?.chordAborted() }
        hotkeys.accessibilityMissing = { [weak self] in self?.chordNeedsAccessibility() }
        hotkeys.start(with: config.hotkeys)
        applyConfigToPanel(config)
        startToolServer()

        ConfigStore.shared.addObserver { [weak self] config in
            self?.hotkeys.apply(config.hotkeys)
            self?.applyConfigToPanel(config)
        }
    }

    func stop() {
        abandonActing()
        toolServer.stop()
        cancelLiveDictation()
        sounds.stop()
        annotations.hide()
        escapeWatcher.stop()
        dragTracker.end()
        selection.hide()
        accessibilityRetry?.invalidate()
        accessibilityRetry = nil
        hotkeys.stop()
        speech.stop()
        audio.stop()
    }

    /// The modifiers turned out to be the start of a real shortcut — ⌘⌥ plus a letter — so the
    /// recording that the chord began is thrown away without a word.
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
    }

    // MARK: - Hotkeys

    func handle(_ action: HotkeyService.Action, _ phase: HotkeyService.Phase) {
        // The chord let go after its first phrase already went off: the engine has outlived the
        // listening state, and this is where it stops. Listening and confirming stop it on their
        // own release paths.
        if action == .ask, phase == .released,
           ![.listening, .dictating].contains(machine.state), !isConfirming, finishLiveAsk() {
            return
        }
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
        updateEscapeWatch()
    }

    private var isConfirming: Bool {
        if case .confirming = machine.state { return true }
        return false
    }

    /// Esc takes back whatever Kestrel is doing, from wherever the user is.
    ///
    /// It used to reach only the marks, and only while they were drawn — so an answer the user had
    /// finished with could not be dismissed at all, and a pointer resting near the notch held it
    /// there. Anything that puts itself on the screen has to have a way off it that does not
    /// require finding a window first.
    func cancelSession() {
        guard machine.state != .idle else {
            // Nothing running, but the marks outlive the panel — Esc still has to reach them.
            annotations.hide()
            return
        }
        generation += 1
        phrases = []
        cancelLiveDictation()
        abandonActing()
        audio.stop()
        speech.stop()
        discardCapture()
        panel.hideImmediately()
        apply(.cancelled)
    }


    /// The tap runs while Kestrel has something on the screen and not a moment longer: an event tap
    /// left listening after the last mark has faded is a tap for no reason.
    func updateEscapeWatch() {
        guard machine.state != .idle || annotations.isVisible else {
            return escapeWatcher.stop()
        }
        guard !escapeWatcher.isWatching else { return }
        escapeWatcher.onEscape = { [weak self] in self?.cancelSession() }
        escapeWatcher.start()
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .startListening: beginRecording(intent: .ask)
        case .startDictating: beginRecording(intent: .dictation)
        case .finishListening: finishRecording(intent: .ask)
        case .finishDictating: finishRecording(intent: .dictation)
        case .startConfirming: beginConfirmRecording()
        case .finishConfirming: finishConfirmRecording()
        case .interruptSpeech: speech.stop()
        case .pulse: panel.pulse()
        case .clearOverlay: annotations.hide()
        case .reset: reset()
        }
    }
}
