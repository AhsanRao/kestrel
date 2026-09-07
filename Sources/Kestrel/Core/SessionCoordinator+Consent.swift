import AppKit
import Foundation

/// Asking the user, and asking the model again.
///
/// Both are about the same thing: a run only continues on terms someone has agreed to — the user
/// for the app being touched, the model for a screen it has not seen yet.
extension SessionCoordinator {
    /// Opening an app is never the whole task — "open Spotify and play something" is a launch plus
    /// everything that follows it, and everything that follows was planned against the app the user
    /// was looking at a second ago. So the launched app is scanned fresh and the model is asked what
    /// to do now, with what has already happened spelled out.
    func replan(after bundleID: String, request: String, done: ActionRunner.Result,
                        continuing: ActionContinuation?) {
        let carried = continuing ?? ActionContinuation(done: [], rounds: 0)
        let next = carried.advanced(with: done.steps.map(\.action.describe), app: bundleID)
        guard next.rounds <= SessionCoordinator.maximumActionRounds else {
            log.info("action re-plan limit reached")
            return finished(done)
        }
        // The user vouched for the app they were in; the app just launched is a new question, but
        // only asked once thanks to the run grant.
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let maxEdge = config.screenshotMaxEdge
        let mode = config.captureMode
        work.async { [weak self] in
            guard let self else { return }
            if let app { Actuator.waitUntilReady(app) }
            // The screen the next steps are planned from has to be the screen that is there now.
            if let capture = try? ScreenGrabber.capture(maxEdge: maxEdge, mode: mode) {
                DispatchQueue.main.sync { self.pendingCapture = capture }
            }
            self.runAgent(request, bundleID: bundleID, continuing: next)
        }
    }

    /// Modal, and deliberately so: this is the one moment the user has to be in the loop.
    ///
    /// Three answers, not two. "Every time" was the whole complaint: a four-step task in an app the
    /// user has already watched Kestrel work in is four identical alerts, which teaches them to
    /// click through without reading — the opposite of what a confirmation is for.
    func askPermission(for action: Action, app: String?) -> ActionRunner.Consent {
        var consent = ActionRunner.Consent.no
        let ask = {
            // The alert has to come forward to be answered, which takes the user out of the app
            // being worked on. Put them back afterwards.
            let previous = NSWorkspace.shared.frontmostApplication
            defer {
                if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    previous.activate()
                }
            }
            NSApp.activate(ignoringOtherApps: true)
            let name = app.flatMap(SessionCoordinator.appName(for:))
            let alert = NSAlert()
            alert.messageText = action.describe
            alert.informativeText = name.map { "Kestrel wants to do this in \($0)." }
                ?? "Kestrel wants to do this."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Do it")
            if let name { alert.addButton(withTitle: "Always allow \(name)") }
            alert.addButton(withTitle: "Stop")

            switch alert.runModal() {
            case .alertFirstButtonReturn: consent = .once
            case .alertSecondButtonReturn where name != nil:
                consent = .always
                if let app { ActionPolicy.allow(app: app) }
            default: consent = .no
            }
            if consent != .no, let app { self.grantedApps.insert(app) }
        }
        if Thread.isMainThread { ask() } else { DispatchQueue.main.sync(execute: ask) }
        return consent
    }

    /// "Spotify", not "com.spotify.client" — the alert is read by a person.
    static func appName(for bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    func stopRun() {
        activeRun?.cancel()
    }

    func finished(_ result: ActionRunner.Result) {
        escapeWatcher.stop()
        activeRun = nil
        grantedApps.removeAll()
        agentOverlay.model.isFinishing = true
        agentOverlay.hide()

        sounds.play(result.completed ? .answered : .failed, config: config)
        panel.model.answer = result.summary
        apply(.actionsFinished)
        panel.model.state = machine.state
        panel.model.answer = result.summary
        panel.show()
        if config.speakAnswers { speech.speak(result.summary, config: config) }
        panel.hide(after: 6)
    }
}
