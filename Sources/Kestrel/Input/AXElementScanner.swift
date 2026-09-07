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
    /// Acting needs more of the app than describing it does: driving Spotify means reaching
    /// Playback ▸ Next, which is a menu item, not a button on the window.
    static let maximumElementsWhenActing = 420
    /// How far into the menu bar the planning scan walks: menus and their titles, not their items.
    /// Every item of every menu would crowd out the window's own controls at `maximumElements`.
    static let menuDepth = maximumDepth - 11
    /// Two levels further: the items inside each menu, not just the menu titles. Used by the live
    /// re-targeting scan and by anything that has to actually drive the app.
    static let deepMenuDepth = maximumDepth - 9

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
    ///
    /// - Parameters:
    ///   - menuDepth: how far into the menu bar to walk. The default reaches the menu titles;
    ///     `deepMenuDepth` reaches the items inside them.
    ///   - limit: total elements to return.
    static func scanFrontmostApp(menuDepth: Int = menuDepth,
                                 limit: Int = maximumElements) -> [Element] {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return [] }
        return scan(pid: pid, menuDepth: menuDepth, limit: limit)
    }

    static func scan(pid: pid_t, menuDepth: Int = menuDepth, limit: Int = maximumElements) -> [Element] {
        guard isAvailable else { return [] }
        let application = AXUIElementCreateApplication(pid)
        var found: [Element] = []
        var seen = Set<String>()

        // The menu bar first — "how do I…" answers so often start with a menu — but on its own
        // budget. A deep walk of every menu in an app like Spotify runs to hundreds of items, and
        // without a separate allowance those would use up the whole scan before a single control
        // in the window itself was seen.
        if let menuBar = child(of: application, attribute: kAXMenuBarAttribute as CFString) {
            walk(menuBar, depth: menuDepth, into: &found, seen: &seen,
                 limit: min(limit, menuBudget(for: limit)))
        }
        // The focused window first, and minimised or off-screen windows not at all. An app with
        // several windows was offering controls from the one the user is *not* looking at, and a
        // model picking by label has no way to tell them apart — which is a mark drawn confidently
        // onto a window behind the one on screen.
        let windows = children(of: application, attribute: kAXWindowsAttribute as CFString)
        let focused = child(of: application, attribute: kAXFocusedWindowAttribute as CFString)
        let ordered = focused.map { [$0] + windows.filter { $0 != focused! } } ?? windows
        for window in ordered where isUsable(window) {
            walk(window, depth: maximumDepth, into: &found, seen: &seen, limit: limit)
        }

        for index in found.indices { found[index].id = index + 1 }
        log.debug("scanned \(found.count) clickable elements")
        return found
    }

    /// Menus may take at most half the scan.
    static func menuBudget(for limit: Int) -> Int { max(limit / 2, 40) }

    // MARK: - Walking

    private static func walk(_ element: AXUIElement, depth: Int,
                             into found: inout [Element], seen: inout Set<String>, limit: Int) {
        guard depth > 0, found.count < limit else { return }

        if let candidate = describe(element), !candidate.label.isEmpty {
            let key = "\(candidate.role)|\(candidate.label)|\(Int(candidate.frame.minX)),\(Int(candidate.frame.minY))"
            if seen.insert(key).inserted { found.append(candidate) }
        }
        for child in children(of: element, attribute: kAXChildrenAttribute as CFString) {
            walk(child, depth: depth - 1, into: &found, seen: &seen, limit: limit)
        }
    }

    /// A window worth reading: on screen, not minimised, and somewhere a user could see it.
    private static func isUsable(_ window: AXUIElement) -> Bool {
        var minimized: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           (minimized as? Bool) == true { return false }
        guard let frame = frame(of: window) else { return true }
        return isOnScreen(frame)
    }

    /// True when the rect actually overlaps a display. A frame that does not is either stale or
    /// belongs to a window parked off screen; either way a mark drawn there lands nowhere.
    static func isOnScreen(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// Where this control is **now**.
    ///
    /// The frame in an `Element` was true when the app was scanned, which for an answer is several
    /// seconds and one model round trip ago. Anything that scrolled, resized or reflowed in between
    /// moved the control out from under the mark. Asking macOS again costs one call and is the
    /// difference between pointing at the button and pointing at where it used to be.
    static func currentFrame(of element: Element) -> CGRect? {
        guard let ref = element.ref, let frame = frame(of: ref), isOnScreen(frame) else { return nil }
        return frame
    }

    private static func describe(_ element: AXUIElement) -> Element? {
        guard let role = string(element, kAXRoleAttribute), clickableRoles.contains(role) else { return nil }
        guard let frame = frame(of: element), frame.width >= 8, frame.height >= 8,
              frame.width < 3000, frame.height < 2000, isOnScreen(frame) else { return nil }

        let label = [string(element, kAXTitleAttribute),
                     string(element, kAXDescriptionAttribute),
                     string(element, kAXValueAttribute),
                     string(element, kAXHelpAttribute)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0.count <= 60 } ?? ""

        return Element(id: 0, label: label, role: role, frame: frame, ref: element)
    }
}
