import AppKit
import ApplicationServices

/// Reading one value out of an Accessibility element, with all the CoreFoundation bridging that
/// entails. Kept apart from the walk so that file stays about *what* is worth collecting.
extension AXElementScanner {
    // MARK: - Attributes

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func children(of element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    static func child(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Accessibility reports top-left screen coordinates; the overlay wants AppKit's.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return ScreenGrabber.appKitFrame(fromCoreGraphics: CGRect(origin: point, size: size))
    }

    /// Asks a Chromium app to build its web content into the Accessibility tree.
    ///
    /// Without this, Chrome offers its toolbar, its tab strip and its bookmarks bar and *nothing
    /// whatsoever from the page* — measured on a real window: 72 controls, every one of them
    /// browser furniture, and not a single character of page text. Chromium keeps the renderer's
    /// tree switched off until an assistive client asks for it, because building it costs memory on
    /// every tab. `AXManualAccessibility` is the documented way to ask; it is the same switch
    /// VoiceOver throws, without pretending to be VoiceOver.
    ///
    /// Setting an attribute an app does not have simply fails, so this is safe to call on anything.
    /// The tree is built asynchronously — the first read after switching it on may still be thin,
    /// and the one after it is not.
    static func enableWebContent(for application: AXUIElement) {
        guard enabledApplications.insert(application).inserted else { return }
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Apps already asked, so only the first question in a browser pays for switching it on. Only
    /// ever touched from the serial background queue that owns every scan.
    private nonisolated(unsafe) static var enabledApplications = Set<AXUIElement>()

    static func friendlyRole(_ role: String) -> String {
        role.replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "MenuBarItem", with: "menu")
            .replacingOccurrences(of: "MenuItem", with: "menu item")
            .lowercased()
    }
}
