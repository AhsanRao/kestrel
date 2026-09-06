import AppKit
import Carbon.HIToolbox
import os

/// Two global hotkeys via Carbon `RegisterEventHotKey`. Carbon is used deliberately: it delivers
/// press *and* release and needs no Accessibility permission, unlike a CGEventTap (spec §8.1).
final class HotkeyService {
    enum Action { case ask, dictate }
    enum Phase { case pressed, released }

    /// Delivered on the main thread.
    var handler: ((Action, Phase) -> Void)?
    var registrationFailure: ((String) -> Void)?

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "hotkey")
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: (ref: EventHotKeyRef, action: Action)] = [:]
    private var isDown: [Action: Bool] = [:]

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
        register(hotkeys.ask, id: 1, action: .ask)
        register(hotkeys.dictate, id: 2, action: .dictate)
    }

    func stop() {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    // MARK: - Registration

    private func register(_ binding: HotkeyBinding, id: UInt32, action: Action) {
        guard binding.isValid else {
            registrationFailure?(binding.display)
            return
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: id)
        let status = RegisterEventHotKey(binding.keyCode, binding.carbonModifiers, hotKeyID,
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
        isDown.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, specs.count, &specs, nil, &eventHandler)
    }

    fileprivate func dispatch(id: UInt32, phase: Phase) {
        guard let action = registrations[id]?.action else { return }
        // Carbon can repeat a press if a modifier is re-pressed while held; collapse duplicates.
        switch phase {
        case .pressed:
            if isDown[action] == true { return }
            isDown[action] = true
        case .released:
            if isDown[action] != true { return }
            isDown[action] = false
        }
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
