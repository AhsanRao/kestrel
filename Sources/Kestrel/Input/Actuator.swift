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
    func perform(_ action: Action, on element: AXElementScanner.Element?) throws
}

final class Actuator: ActionPerforming {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "actuator")

    func perform(_ action: Action, on element: AXElementScanner.Element?) throws {
        guard AXIsProcessTrusted() else { throw KestrelError.accessibilityDenied }

        switch action.kind {
        case .launchApp:
            try launch(bundleID: action.value)
        case .press:
            try press(element)
        case .setValue:
            try setValue(action.value ?? "", on: element)
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
        let amount: Int32 = direction.lowercased().hasPrefix("up") ? 6 : -6
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                  wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)
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

    /// A press posted to the owning process. Still background: the user's cursor stays put.
    private func clickThroughEvents(at frame: CGRect, ref: AXUIElement, describe: String) throws {
        guard let pid = pid(of: ref) else { throw KestrelError.actionFailed("press \(describe)") }
        let centre = CGPoint(x: frame.midX, y: ScreenGrabber.appKitFrame(fromCoreGraphics: frame).midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: centre, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: centre, mouseButton: .left)
        else { throw KestrelError.actionFailed("press \(describe)") }
        down.postToPid(pid)
        up.postToPid(pid)
    }

    private func pid(of element: AXUIElement?) -> pid_t? {
        guard let element else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
}
