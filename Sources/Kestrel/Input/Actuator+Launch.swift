import AppKit
import ApplicationServices

/// Opening an app, and waiting until there is actually an app there to work with.
///
/// Its own file because the waiting is the whole substance of it: every other action in `Actuator`
/// happens to a control that already exists, and this one has to bring the controls into being
/// first.
extension Actuator {
    /// Launches the app **and waits for it to be usable**.
    ///
    /// `openApplication` returns the moment the request is filed, which for a cold start is several
    /// seconds before the app has a window, a menu bar, or anything at all in its Accessibility
    /// tree. Anything Kestrel did next therefore acted on an app that was not there yet — which is
    /// what "it opens Spotify but never plays anything" actually was.
    func launch(bundleID: String?) throws {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { throw KestrelError.actionFailed("find that app") }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        let done = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        var failure: Error?
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
            launched = app
            failure = error
            done.signal()
        }
        guard done.wait(timeout: .now() + Actuator.launchTimeout) == .success else {
            throw KestrelError.actionFailed("open that app")
        }
        if let failure { throw KestrelError.actionFailed(failure.localizedDescription) }
        guard let launched else { throw KestrelError.actionFailed("open that app") }
        Actuator.waitUntilReady(launched)
    }

    static let launchTimeout: TimeInterval = 20

    /// Polls until the app has finished launching and has something to act on, or gives up.
    ///
    /// A window is the signal that matters: `isFinishedLaunching` flips well before an app like
    /// Spotify has drawn one, and a scan taken in that gap comes back empty.
    static func waitUntilReady(_ app: NSRunningApplication, timeout: TimeInterval = 12) {
        let deadline = Date().addingTimeInterval(timeout)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        while Date() < deadline {
            if app.isFinishedLaunching {
                var windows: CFTypeRef?
                let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows)
                if status == .success, let list = windows as? [AXUIElement], !list.isEmpty { break }
                // An app with no Accessibility windows may still be driveable through its menu bar.
                if status == .apiDisabled || status == .notImplemented { break }
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        app.activate()
        // A beat for the frontmost-app change to land before anything is scanned or posted.
        Thread.sleep(forTimeInterval: 0.4)
    }
}
