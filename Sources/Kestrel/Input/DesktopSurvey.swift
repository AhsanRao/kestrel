import AppKit
import CoreGraphics

/// What else is open. HeyClicky exposes `list_apps` / `list_windows` / `get_desktop_state`; this is
/// the same information, gathered only when a question actually needs it, because every extra line
/// in the prompt costs tokens and latency on questions that do not.
enum DesktopSurvey {
    struct Window: Equatable {
        var title: String
        var app: String
        var bundleID: String?
        var frame: CGRect
        var isFrontmost: Bool

        var listing: String {
            let where_ = "\(Int(frame.width))×\(Int(frame.height))"
            let name = title.isEmpty ? app : "\(app) — \(title)"
            return isFrontmost ? "\(name) [\(where_), in front]" : "\(name) [\(where_)]"
        }
    }

    /// Windows smaller than this are palettes, tooltips and shadows, not things to switch to.
    static let minimumSize = CGSize(width: 200, height: 120)
    static let maximumWindows = 18

    static func windows() -> [Window] {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        let bundleIDs = Dictionary(
            NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, String)? in
                guard let bundleID = app.bundleIdentifier else { return nil }
                return (app.processIdentifier, bundleID)
            }, uniquingKeysWith: { first, _ in first })
        return windows(from: raw, frontmostPID: frontmost, bundleIDs: bundleIDs)
    }

    /// Split out from the CoreGraphics call so the filtering and ordering can be tested.
    static func windows(from raw: [[String: Any]], frontmostPID: pid_t?,
                        bundleIDs: [pid_t: String] = [:]) -> [Window] {
        let parsed = raw.compactMap { entry -> Window? in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,           // normal windows only
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let app = entry[kCGWindowOwnerName as String] as? String,
                  let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width >= minimumSize.width, rect.height >= minimumSize.height
            else { return nil }
            return Window(title: (entry[kCGWindowName as String] as? String) ?? "",
                          app: app,
                          bundleID: bundleIDs[pid],
                          frame: rect,
                          isFrontmost: pid == frontmostPID)
        }
        // The window in front first, then biggest first: that is roughly the order a person would
        // list what is on their screen.
        return Array(parsed.sorted { left, right in
            if left.isFrontmost != right.isFrontmost { return left.isFrontmost }
            return left.frame.width * left.frame.height > right.frame.width * right.frame.height
        }.prefix(maximumWindows))
    }

    /// Ordinary apps with a Dock presence — not agents, helpers or daemons.
    static func runningApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .sorted()
    }

    /// The block handed to the model, or nil when there is nothing worth saying.
    static func summary(windows: [Window], apps: [String]) -> String? {
        guard !windows.isEmpty || !apps.isEmpty else { return nil }
        var parts: [String] = []
        if !windows.isEmpty {
            parts.append("Windows open right now:\n" + windows.map { "- \($0.listing)" }.joined(separator: "\n"))
        }
        if !apps.isEmpty {
            parts.append("Apps running: " + apps.joined(separator: ", "))
        }
        return parts.joined(separator: "\n\n")
    }

    static func summary() -> String? {
        summary(windows: windows(), apps: runningApps())
    }
}

/// Whether a question is about the desktop rather than about what is on screen.
enum DesktopContextDetector {
    private static let phrases = [
        "what else is open", "what's open", "what is open", "which apps", "what apps",
        "other window", "other windows", "switch to", "running", "my windows", "open apps",
        "on my desktop", "other tab", "what am i running",
    ]

    static func needsDesktopContext(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return phrases.contains { lowered.contains($0) }
    }
}
