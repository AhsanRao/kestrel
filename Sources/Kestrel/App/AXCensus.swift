import AppKit
import ApplicationServices

/// A diagnostic for one question: what does this app actually put in its Accessibility tree?
///
/// Used by `KESTREL_PREVIEW_OVERLAY=live`. Chrome answered "72 controls, all of them my own
/// toolbar", and there is no way to tell from that whether the page tree is absent, deeper than the
/// walk reaches, or switched off — so this counts every role under the window with no filtering and
/// no depth limit worth mentioning, and reports whether the switches to turn web content on took.
enum AXCensus {
    static func report(pid: pid_t) -> [String] {
        let application = AXUIElementCreateApplication(pid)
        var lines = ["--- accessibility census ---"]

        for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
            let status = AXUIElementSetAttributeValue(application, attribute as CFString, kCFBooleanTrue)
            lines.append("set \(attribute) → \(name(for: status))")
        }
        // The tree is built asynchronously; give it a moment before counting.
        Thread.sleep(forTimeInterval: 1.5)

        guard let window = AXElementScanner.child(of: application,
                                                  attribute: kAXFocusedWindowAttribute as CFString) else {
            return lines + ["no focused window"]
        }
        var histogram: [String: Int] = [:]
        var deepest = 0
        var counted = 0
        census(window, depth: 0, histogram: &histogram, deepest: &deepest, counted: &counted)
        lines.append("elements: \(counted)   deepest: \(deepest)")
        lines += histogram.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "  \($0.value)×  \($0.key)" }
        return lines
    }

    private static func census(_ element: AXUIElement, depth: Int, histogram: inout [String: Int],
                               deepest: inout Int, counted: inout Int) {
        guard depth < 60, counted < 6000 else { return }
        counted += 1
        deepest = max(deepest, depth)
        if let role = AXElementScanner.string(element, kAXRoleAttribute) {
            histogram[role, default: 0] += 1
        }
        for child in AXElementScanner.children(of: element, attribute: kAXChildrenAttribute as CFString) {
            census(child, depth: depth + 1, histogram: &histogram, deepest: &deepest, counted: &counted)
        }
    }

    private static func name(for status: AXError) -> String {
        switch status {
        case .success: return "success"
        case .attributeUnsupported: return "attributeUnsupported"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .cannotComplete: return "cannotComplete"
        case .notImplemented: return "notImplemented"
        case .apiDisabled: return "apiDisabled"
        default: return "error \(status.rawValue)"
        }
    }
}
