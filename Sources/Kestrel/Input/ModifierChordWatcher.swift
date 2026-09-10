import AppKit
import CoreGraphics
import os

/// Watches for bare modifier chords (⌃⌥ held alone) through a listen-only `CGEventTap`.
///
/// Carbon's `RegisterEventHotKey` needs a key code, so it cannot express this. The tap can, at the
/// cost of Accessibility permission — the same grant dictation already requires.
final class ModifierChordWatcher {
    struct Registration {
        var action: HotkeyService.Action
        var detector: ModifierChordDetector
    }

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "chord")
    private var registrations: [Registration] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dwellTimers: [Int: DispatchWorkItem] = [:]

    /// Delivered on the main thread. `.abort` means the chord was a shortcut prefix after all.
    var onPress: ((HotkeyService.Action) -> Void)?
    var onRelease: ((HotkeyService.Action) -> Void)?
    var onAbort: ((HotkeyService.Action) -> Void)?
    var onPermissionMissing: (() -> Void)?

    var isWatching: Bool { tap != nil }

    /// Replaces every registration. Returns false when Accessibility is not granted.
    @discardableResult
    func watch(_ chords: [(HotkeyService.Action, HotkeyBinding)]) -> Bool {
        stop()
        registrations = chords.map {
            Registration(action: $0.0, detector: ModifierChordDetector(required: $0.1.normalizedModifiers))
        }
        guard !registrations.isEmpty else { return true }
        guard TextInjector.hasAccessibilityPermission else {
            log.info("chord hotkey needs accessibility permission")
            onPermissionMissing?()
            return false
        }
        return installTap()
    }

    func stop() {
        dwellTimers.values.forEach { $0.cancel() }
        dwellTimers.removeAll()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        registrations.removeAll()
    }

    // MARK: - Dispatch

    fileprivate func handle(_ input: ModifierChordDetector.Input) {
        for index in registrations.indices {
            guard let output = registrations[index].detector.apply(input) else { continue }
            let action = registrations[index].action
            switch output {
            case .arm:
                let work = DispatchWorkItem { [weak self] in self?.handleDwell(index) }
                dwellTimers[index]?.cancel()
                dwellTimers[index] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + ModifierChordDetector.dwell, execute: work)
            case .disarm:
                dwellTimers[index]?.cancel()
                dwellTimers[index] = nil
            case .fire:
                onPress?(action)
            case .release:
                onRelease?(action)
            case .abort:
                onAbort?(action)
            }
        }
    }

    private func handleDwell(_ index: Int) {
        dwellTimers[index] = nil
        guard registrations.indices.contains(index) else { return }
        guard let output = registrations[index].detector.apply(.dwellElapsed), output == .fire else { return }
        onPress?(registrations[index].action)
    }

    fileprivate func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: chordTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("could not create chord event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }
}

/// Listen-only, so events always pass straight through to whatever the user is actually using.
private let chordTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let watcher = Unmanaged<ModifierChordWatcher>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        watcher.reenableTap()
    case .flagsChanged:
        let flags = NSEvent(cgEvent: event)?.modifierFlags ?? []
        DispatchQueue.main.async { watcher.handle(.flagsChanged(flags)) }
    case .keyDown:
        DispatchQueue.main.async { watcher.handle(.keyPressed) }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
