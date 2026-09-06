import AppKit
import CoreGraphics
import os

/// Listens for Esc while Kestrel is doing something on the user's behalf.
///
/// Anything that acts on its own has to have a way to be stopped that does not require finding a
/// window first. A listen-only tap sees the key wherever the user is, and never swallows it.
final class EscapeWatcher {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "escape")
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onEscape: (() -> Void)?

    var isWatching: Bool { tap != nil }

    /// Returns false when Accessibility has not been granted, so the caller can say so.
    @discardableResult
    func start() -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: escapeTapCallback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("could not create escape tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    fileprivate func fire() {
        onEscape?()
    }

    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private let escapeTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let watcher = Unmanaged<EscapeWatcher>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        watcher.reenable()
    case .keyDown where event.getIntegerValueField(.keyboardEventKeycode) == 53:
        DispatchQueue.main.async { watcher.fire() }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
