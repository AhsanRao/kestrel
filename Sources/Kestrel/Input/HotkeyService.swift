import AppKit
import Carbon.HIToolbox
import os

/// Two global hotkeys. A binding with a key code goes to Carbon `RegisterEventHotKey`, which
/// delivers press *and* release and needs no permission (spec §8.1). A bare modifier chord — ⌘⌥
/// held alone — cannot be registered that way and is watched by `ModifierChordWatcher` instead,
/// which does need Accessibility.
final class HotkeyService {
    enum Action: Hashable { case ask, dictate }
    enum Phase: Hashable { case pressed, released }

    /// Delivered on the main thread.
    var handler: ((Action, Phase) -> Void)?
    var registrationFailure: ((String) -> Void)?
    /// The chord turned out to be the start of a real shortcut; whatever it began must be undone.
    var chordAborted: ((Action) -> Void)?
    /// A bare-chord hotkey is configured but Accessibility has not been granted.
    var accessibilityMissing: (() -> Void)?

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "hotkey")
    private let chords = ModifierChordWatcher()
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: (ref: EventHotKeyRef, action: Action)] = [:]
    private var presses = HotkeyPressFilter()

    private static let signature: OSType = 0x6B73746C  // 'kstl'
    private static weak var active: HotkeyService?

    func start(with hotkeys: Config.Hotkeys) {
        HotkeyService.active = self
        installHandlerIfNeeded()
        apply(hotkeys)
    }

    /// Re-registers from scratch. Called on every config change (spec §8.1).
    func apply(_ hotkeys: Config.Hotkeys) {
        unregisterAll()
        chords.stop()

        var chordBindings: [(Action, HotkeyBinding)] = []
        for (binding, id, action) in [(hotkeys.ask, UInt32(1), Action.ask),
                                      (hotkeys.dictate, UInt32(2), Action.dictate)] {
            guard binding.isValid else { registrationFailure?(binding.display); continue }
            if binding.isModifierOnly {
                chordBindings.append((action, binding))
            } else {
                register(binding, id: id, action: action)
            }
        }
        guard !chordBindings.isEmpty else { return }

        chords.onPress = { [weak self] action in self?.dispatchChord(action, phase: .pressed) }
        chords.onRelease = { [weak self] action in self?.dispatchChord(action, phase: .released) }
        chords.onAbort = { [weak self] action in self?.chordAborted?(action) }
        chords.onPermissionMissing = { [weak self] in self?.accessibilityMissing?() }
        chords.watch(chordBindings)
    }

    func stop() {
        chords.stop()
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    // MARK: - Registration

    private func register(_ binding: HotkeyBinding, id: UInt32, action: Action) {
        guard let keyCode = binding.keyCode else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: id)
        let status = RegisterEventHotKey(keyCode, binding.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            registrations[id] = (ref, action)
            log.info("registered \(binding.display, privacy: .public)")
        } else {
            log.error("hotkey \(binding.display, privacy: .public) failed: \(status)")
            registrationFailure?(binding.display)
        }
    }

    private func unregisterAll() {
        for (_, entry) in registrations { UnregisterEventHotKey(entry.ref) }
        registrations.removeAll()
        presses = HotkeyPressFilter()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, specs.count, &specs, nil, &eventHandler)
    }

    /// Chord events already arrive on the main thread and carry their own press/release pairing.
    private func dispatchChord(_ action: Action, phase: Phase) {
        handler?(action, phase)
    }

    fileprivate func dispatch(id: UInt32, phase: Phase) {
        guard let action = registrations[id]?.action else { return }
        guard presses.allows(action, phase) else {
            log.debug("\(String(describing: action), privacy: .public) \(String(describing: phase), privacy: .public) ignored")
            return
        }
        log.debug("\(String(describing: action), privacy: .public) \(String(describing: phase), privacy: .public)")
        let block = handler
        DispatchQueue.main.async { block?(action, phase) }
    }

    fileprivate static func handle(_ event: EventRef?) -> OSStatus {
        guard let service = active, let event else { return OSStatus(eventNotHandledErr) }
        let kind = GetEventKind(event)
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard status == noErr, hotKeyID.signature == signature else { return OSStatus(eventNotHandledErr) }
        service.dispatch(id: hotKeyID.id, phase: kind == UInt32(kEventHotKeyPressed) ? .pressed : .released)
        return noErr
    }
}

/// Carbon needs a bare C function pointer, so the instance is reached through `HotkeyService.active`.
private let hotkeyCallback: EventHandlerUPP = { _, event, _ in
    HotkeyService.handle(event)
}

/// Which Carbon hot key events count as real.
///
/// Carbon repeats a held hot key at the keyboard's repeat rate, so presses have to be de-duplicated
/// — but it also drops `kEventHotKeyReleased` altogether when the modifiers come up before the key,
/// which is how most people let go of ⌃⌘K. Pairing each press against a remembered "still down"
/// flag therefore left that flag stuck after the first lost release, and every later press was
/// swallowed as a repeat: dictation turned on and could not be turned off again, because the toggle
/// only ever acts on a press. A press now stands on its own, and only the keyboard's own repeat
/// rate can suppress it.
struct HotkeyPressFilter {
    /// Nothing a person does twice lands this close together; the keyboard's repeat does.
    static let repeatWindow: TimeInterval = 0.3

    private var lastPress: [HotkeyService.Action: Date] = [:]
    private var down: Set<HotkeyService.Action> = []

    mutating func allows(_ action: HotkeyService.Action, _ phase: HotkeyService.Phase,
                         at now: Date = Date()) -> Bool {
        switch phase {
        case .pressed:
            if let last = lastPress[action], now.timeIntervalSince(last) < HotkeyPressFilter.repeatWindow {
                return false
            }
            lastPress[action] = now
            down.insert(action)
            return true
        case .released:
            // A release with no press behind it is Carbon catching up on a combination Kestrel
            // never saw start.
            return down.remove(action) != nil
        }
    }
}
