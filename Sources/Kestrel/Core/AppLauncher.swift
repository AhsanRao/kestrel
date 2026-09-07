import AppKit
import os

/// Opening an app, and nothing else.
///
/// This is all that is left of Kestrel acting on the Mac. Driving an app from the outside — pressing
/// its buttons, filling its fields — was removed: it needed a policy, a confirmation for every step,
/// and a plan that went stale the moment anything moved, and it was never what made Kestrel useful.
/// Opening something is different in kind: one verb, instantly obvious, nothing to undo.
enum AppLauncher {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "launch")

    /// Phrasings that mean "put this app in front of me".
    private static let openers = ["open", "launch", "start up", "switch to", "bring up", "go to"]

    /// The app named in the request, if it is one Kestrel can open.
    ///
    /// Deliberately strict: only a leading verb, and only when the rest of the sentence names an app
    /// that is actually installed. "Open the File menu" names no app and so is a question about the
    /// screen, which is the branch that should get it.
    static func requestedApp(in text: String) -> (bundleID: String, name: String)? {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let verb = openers.first(where: { lowered.hasPrefix("\($0) ") }) else { return nil }
        var name = String(lowered.dropFirst(verb.count + 1))
        for filler in ["the ", "my ", "app ", "application "] where name.hasPrefix(filler) {
            name = String(name.dropFirst(filler.count))
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\"'"))
        // "open spotify and play something" is still an app to open; the rest is not Kestrel's job
        // any more, and saying so is better than half-doing it.
        for tail in [" and ", " then ", " to ", " for "] {
            if let range = name.range(of: tail) { name = String(name[..<range.lowerBound]) }
        }
        guard name.count >= 2 else { return nil }
        return installedApp(named: name)
    }

    /// Matches the spoken name against what is installed, by display name.
    static func installedApp(named name: String) -> (bundleID: String, name: String)? {
        let wanted = name.lowercased()
        // Anything already running is the best guess: it is what the user can see in their Dock.
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, let localized = app.localizedName else { continue }
            if localized.lowercased() == wanted { return (bundleID, localized) }
        }
        for directory in ["/Applications", "/System/Applications",
                          NSHomeDirectory() + "/Applications"] {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            for entry in contents where entry.hasSuffix(".app") {
                let display = String(entry.dropLast(4))
                guard display.lowercased() == wanted else { continue }
                let url = URL(fileURLWithPath: directory).appendingPathComponent(entry)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { continue }
                return (id, display)
            }
        }
        return nil
    }

    /// Blocking; call from a background queue. Returns once the app is actually usable.
    @discardableResult
    static func launch(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let done = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, _ in
            launched = app
            done.signal()
        }
        guard done.wait(timeout: .now() + 20) == .success, let launched else { return false }
        waitUntilReady(launched)
        log.info("opened \(bundleID, privacy: .public)")
        return true
    }

    /// A cold-starting app reports itself launched well before it has drawn anything, and a
    /// screenshot taken in that gap is of nothing.
    static func waitUntilReady(_ app: NSRunningApplication, timeout: TimeInterval = 12) {
        let deadline = Date().addingTimeInterval(timeout)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        while Date() < deadline {
            if app.isFinishedLaunching {
                var windows: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString,
                                                           &windows)
                if status == .success, let list = windows as? [AXUIElement], !list.isEmpty { break }
                if status == .apiDisabled || status == .notImplemented { break }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.activate()
        Thread.sleep(forTimeInterval: 0.4)
    }
}
