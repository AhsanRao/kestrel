import AppKit
import ApplicationServices
import os

/// Performs actions on the Mac through Accessibility.
///
/// Accessibility is chosen over synthetic clicks for one reason: `AXUIElementPerformAction` is
/// delivered straight to the control. The real cursor never moves, focus is not stolen, and the
/// user can keep typing while Kestrel works — the property HeyClicky gets from its driver's
/// `delivery_mode: background` constraint. Synthetic events are the fallback, and are posted to
/// the owning process rather than the global event stream for the same reason.
protocol ActionPerforming: AnyObject {
    /// - Parameter app: the process the plan was made against. Keystrokes and typed text go there
    ///   when no control was named, rather than to whatever happens to be frontmost at the time —
    ///   which, right after a confirmation dialog, is Kestrel.
    func perform(_ action: Action, on element: AXElementScanner.Element?, in app: pid_t?) throws
}

final class Actuator: ActionPerforming {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "actuator")

    func perform(_ action: Action, on element: AXElementScanner.Element?, in app: pid_t? = nil) throws {
        guard AXIsProcessTrusted() else { throw KestrelError.accessibilityDenied }

        switch action.kind {
        case .launchApp:
            try launch(bundleID: action.value)
        case .press:
            try press(element)
        case .rightClick:
            try rightClick(element)
        case .setValue:
            try setValue(action.value ?? "", on: element)
        case .typeText:
            try type(action.value ?? "", into: element, app: app)
        case .key:
            try key(action.value ?? "", on: element, app: app)
        case .focus:
            try focus(element)
        case .scroll:
            try scroll(element, direction: action.value ?? "down")
        }
        log.info("performed \(action.kind.rawValue, privacy: .public): \(action.describe, privacy: .public)")
    }

    // MARK: - Actions

    private func press(_ element: AXElementScanner.Element?) throws {
        guard let element, let ref = element.ref else { throw KestrelError.actionFailed("find that control") }
        if AXUIElementPerformAction(ref, kAXPressAction as CFString) == .success { return }
        // Some controls expose no press action; a click posted to the owning process still counts
        // as background delivery.
        try clickThroughEvents(at: element.frame, ref: ref, describe: element.label)
    }

    /// A context menu, asked for through Accessibility where the control offers it. The synthetic
    /// fallback is a right button pair posted to the owning process, same as `press`.
    private func rightClick(_ element: AXElementScanner.Element?) throws {
        guard let element, let ref = element.ref else { throw KestrelError.actionFailed("find that control") }
        if AXUIElementPerformAction(ref, kAXShowMenuAction as CFString) == .success { return }
        guard let pid = pid(of: ref) else { throw KestrelError.actionFailed("right-click \(element.label)") }
        try mouse(.rightMouseDown, .rightMouseUp, at: element.frame, pid: pid, describe: element.label)
    }

    /// Types alongside what is already there. `setValue` replaces a field; this appends to it, or
    /// to whatever has focus when no control was named.
    private func type(_ text: String, into element: AXElementScanner.Element?, app: pid_t?) throws {
        guard !text.isEmpty else { throw KestrelError.actionFailed("type an empty string") }
        if let ref = element?.ref {
            AXUIElementSetAttributeValue(ref, kAXFocusedAttribute as CFString, true as CFTypeRef)
        }
        guard let pid = pid(of: element?.ref) ?? app ?? frontmostPID() else {
            throw KestrelError.actionFailed("find the app to type into")
        }
        try KeyEvents.type(text, to: pid)
    }

    /// A keystroke or chord, delivered to one process rather than to the system.
    private func key(_ raw: String, on element: AXElementScanner.Element?, app: pid_t?) throws {
        guard let chord = KeyChord(raw) else { throw KestrelError.actionFailed("press \(raw)") }
        guard let pid = pid(of: element?.ref) ?? app ?? frontmostPID() else {
            throw KestrelError.actionFailed("find the app to press \(chord.display) in")
        }
        try KeyEvents.press(chord, to: pid)
    }

    private func setValue(_ value: String, on element: AXElementScanner.Element?) throws {
        guard let element, let ref = element.ref else { throw KestrelError.actionFailed("find that field") }
        AXUIElementSetAttributeValue(ref, kAXFocusedAttribute as CFString, true as CFTypeRef)
        guard AXUIElementSetAttributeValue(ref, kAXValueAttribute as CFString, value as CFTypeRef) == .success
        else { throw KestrelError.actionFailed("type into \(element.label)") }
    }

    private func focus(_ element: AXElementScanner.Element?) throws {
        guard let element, let ref = element.ref else { throw KestrelError.actionFailed("find that control") }
        AXUIElementPerformAction(ref, kAXRaiseAction as CFString)
        guard AXUIElementSetAttributeValue(ref, kAXFocusedAttribute as CFString, true as CFTypeRef) == .success
        else { throw KestrelError.actionFailed("focus \(element.label)") }
    }

    private func scroll(_ element: AXElementScanner.Element?, direction: String) throws {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                  wheel1: Actuator.scrollAmount(direction), wheel2: 0, wheel3: 0)
        else { throw KestrelError.actionFailed("scroll") }
        if let pid = pid(of: element?.ref) {
            event.postToPid(pid)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }

    private func launch(bundleID: String?) throws {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { throw KestrelError.actionFailed("find that app") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    // MARK: - Fallback

    /// Lines per scroll. A page is a screenful rather than a nudge, which is what "page down" and
    /// "scroll to the bottom" both mean in practice.
    static func scrollAmount(_ direction: String) -> Int32 {
        // Whole words, not substrings: "stop" contains "top" and means neither up nor far.
        let words = Set(direction.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        let far: Int32 = words.isDisjoint(with: ["page", "screen", "top", "bottom", "end"]) ? 6 : 30
        let up = !words.isDisjoint(with: ["up", "top", "back", "previous", "start"])
        return up ? far : -far
    }

    /// A press posted to the owning process. Still background: the user's cursor stays put.
    private func clickThroughEvents(at frame: CGRect, ref: AXUIElement, describe: String) throws {
        guard let pid = pid(of: ref) else { throw KestrelError.actionFailed("press \(describe)") }
        try mouse(.leftMouseDown, .leftMouseUp, at: frame, pid: pid, describe: describe)
    }

    private func mouse(_ downType: CGEventType, _ upType: CGEventType, at frame: CGRect,
                       pid: pid_t, describe: String) throws {
        let button: CGMouseButton = downType == .rightMouseDown ? .right : .left
        let centre = CGPoint(x: frame.midX, y: ScreenGrabber.appKitFrame(fromCoreGraphics: frame).midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                                 mouseCursorPosition: centre, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                               mouseCursorPosition: centre, mouseButton: button)
        else { throw KestrelError.actionFailed("press \(describe)") }
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    private func pid(of element: AXUIElement?) -> pid_t? {
        guard let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
}
