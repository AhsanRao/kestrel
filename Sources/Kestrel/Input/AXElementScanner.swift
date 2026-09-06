import AppKit
import ApplicationServices
import os

/// Reads the real controls of the frontmost app out of the Accessibility tree.
///
/// Asking a vision model for pixel coordinates was the wrong instrument: it landed a button or two
/// off, because locating a small control in a resized screenshot is genuinely hard for it. macOS
/// already knows exactly where every button is. So the model is given a numbered list of the real
/// controls and only has to pick one — a judgement it is good at — and the ring is drawn on the
/// frame macOS reported, which is exact by construction.
enum AXElementScanner {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "ax")

    /// Roles worth offering: things a user can actually click.
    static let clickableRoles: Set<String> = [
        kAXButtonRole, kAXMenuItemRole, kAXMenuBarItemRole, kAXCheckBoxRole, kAXRadioButtonRole,
        kAXPopUpButtonRole, "AXLink", kAXTabGroupRole, kAXTextFieldRole, kAXTextAreaRole,
        kAXSliderRole, kAXComboBoxRole, kAXIncrementorRole, kAXDisclosureTriangleRole,
        kAXToolbarRole, kAXRowRole, kAXCellRole, kAXImageRole,
    ]

    /// Bounds on the walk: some apps have enormous trees and Kestrel is on the user's clock.
    static let maximumDepth = 14
    static let maximumElements = 220

    struct Element: Equatable {
        var id: Int
        var label: String
        var role: String
        /// Global AppKit points, origin bottom-left — ready to hand to the overlay.
        var frame: CGRect
        /// The live Accessibility handle, kept so the element can be acted on and not merely drawn
        /// around. Absent in tests and in anything reconstructed from disk.
        var ref: AXUIElement?

        init(id: Int, label: String, role: String, frame: CGRect, ref: AXUIElement? = nil) {
            self.id = id
            self.label = label
            self.role = role
            self.frame = frame
            self.ref = ref
        }

        /// Identity is what the model and the user see; the opaque handle is not part of it.
        static func == (lhs: Element, rhs: Element) -> Bool {
            lhs.id == rhs.id && lhs.label == rhs.label && lhs.role == rhs.role && lhs.frame == rhs.frame
        }

        /// "3. Export  (button)" — the line the model chooses from.
        var listing: String {
            "\(id). \(label)  (\(AXElementScanner.friendlyRole(role)))"
        }
    }

    static var isAvailable: Bool { AXIsProcessTrusted() }

    /// The clickable controls of the frontmost app, numbered from 1.
    static func scanFrontmostApp() -> [Element] {
        guard isAvailable,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return [] }

        let application = AXUIElementCreateApplication(pid)
        var found: [Element] = []
        var seen = Set<String>()

        // The menu bar first: "how do I…" answers so often start with a menu.
        if let menuBar = child(of: application, attribute: kAXMenuBarAttribute as CFString) {
            walk(menuBar, depth: maximumDepth - 11, into: &found, seen: &seen)
        }
        for window in children(of: application, attribute: kAXWindowsAttribute as CFString) {
            walk(window, depth: maximumDepth, into: &found, seen: &seen)
        }

        for index in found.indices { found[index].id = index + 1 }
        log.debug("scanned \(found.count) clickable elements")
        return found
    }

    // MARK: - Walking

    private static func walk(_ element: AXUIElement, depth: Int,
                             into found: inout [Element], seen: inout Set<String>) {
        guard depth > 0, found.count < maximumElements else { return }

        if let candidate = describe(element), !candidate.label.isEmpty {
            let key = "\(candidate.role)|\(candidate.label)|\(Int(candidate.frame.minX)),\(Int(candidate.frame.minY))"
            if seen.insert(key).inserted { found.append(candidate) }
        }
        for child in children(of: element, attribute: kAXChildrenAttribute as CFString) {
            walk(child, depth: depth - 1, into: &found, seen: &seen)
        }
    }

    private static func describe(_ element: AXUIElement) -> Element? {
        guard let role = string(element, kAXRoleAttribute), clickableRoles.contains(role) else { return nil }
        guard let frame = frame(of: element), frame.width >= 8, frame.height >= 8,
              frame.width < 3000, frame.height < 2000 else { return nil }

        let label = [string(element, kAXTitleAttribute),
                     string(element, kAXDescriptionAttribute),
                     string(element, kAXValueAttribute),
                     string(element, kAXHelpAttribute)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.count <= 60 } ?? ""

        return Element(id: 0, label: label, role: role, frame: frame, ref: element)
    }

    // MARK: - Attributes

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(of element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private static func child(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// Accessibility reports top-left screen coordinates; the overlay wants AppKit's.
    private static func frame(of element: AXUIElement) -> CGRect? {
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
