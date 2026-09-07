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

    static func friendlyRole(_ role: String) -> String {
        role.replacingOccurrences(of: "AX", with: "")
            .replacingOccurrences(of: "MenuBarItem", with: "menu")
            .replacingOccurrences(of: "MenuItem", with: "menu item")
            .lowercased()
    }
}
