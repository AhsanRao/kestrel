import AppKit
import CoreGraphics

/// The listen-only event tap a walkthrough runs on: clicks advance it, Esc ends it.
///
/// Split from `WalkthroughSession` so the session file stays about the walkthrough rather than
/// about Core Graphics. The tap never swallows an event — the app underneath still gets the click
/// that moved the user forward.
extension WalkthroughSession {
    // MARK: - Event tap

    func installTap() -> Bool {
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: walkthroughTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("could not create event tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
    }

    func reenableTap() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

/// C callback for the tap. Listen-only, so the event is always passed straight through.
let walkthroughTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<WalkthroughSession>.fromOpaque(userInfo).takeUnretainedValue()

    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        session.reenableTap()
    case .leftMouseDown, .rightMouseDown:
        let point = WalkthroughSession.appKitPoint(from: event.location)
        DispatchQueue.main.async { session.handleClick(at: point) }
    case .keyDown:
        if event.getIntegerValueField(.keyboardEventKeycode) == 53 {   // Esc
            DispatchQueue.main.async { session.handleEscape() }
        }
    default:
        break
    }
    return Unmanaged.passUnretained(event)
}
