import AppKit
import Foundation

/// Taking it all away again: the temp files, the error, the panel's own clock.
extension SessionCoordinator {
    /// Main thread. The number the take starting now is stamped with.
    func beginGeneration() -> Int {
        generation += 1
        return generation
    }

    /// Whether work stamped `stamp` is still the take the user is waiting on. Main thread.
    func isCurrent(_ stamp: Int) -> Bool { stamp == generation }

    /// The same question from a background queue.
    func stillCurrent(_ stamp: Int) -> Bool { DispatchQueue.main.sync { isCurrent(stamp) } }

    func discardCapture() {
        if let capture = pendingCapture { try? FileManager.default.removeItem(at: capture.url) }
        if let crop = pendingCrop { try? FileManager.default.removeItem(at: crop) }
        pendingCapture = nil
        pendingCrop = nil
        pendingScreen = nil
        focusRegion = nil
    }

    /// - Parameter stamp: the take the error belongs to; an error from a take the user has
    ///   already cancelled is not shown over whatever they are doing now.
    func finish(with error: Error, stamp: Int? = nil) {
        DispatchQueue.main.async {
            if let stamp, !self.isCurrent(stamp) { return }
            self.fail(error)
        }
    }

    func fail(_ error: Error) {
        generation += 1
        cancelAcknowledgement()
        abandonActing()
        panel.model.aside = nil
        sounds.play(.failed, config: config)
        discardCapture()
        let kestrelError = error as? KestrelError
        let message = kestrelError?.errorDescription ?? error.localizedDescription
        log.error("\(message, privacy: .public)")
        panel.model.permissionURL = kestrelError?.settingsURL
        apply(.failed(message))
        render()
        panel.show()
        // Errors are never read out, so this is the only way one reaches a screen reader.
        panel.announce(message)
        dismiss(after: 8)
        askNextPhrase()
    }

    /// Takes a line down again once it has been read, and puts the session back to idle with it.
    ///
    /// Hiding the window is not enough on its own. The machine stays in `.error` with the failed
    /// message in it, so the next press starts out of an error state carrying a stale transcript;
    /// worse, an error that arrives on a path which never calls this at all — an empty transcript
    /// used to be one — leaves the island open on screen with nothing to dismiss it.
    func dismiss(after seconds: TimeInterval) {
        panel.hide(after: seconds)
        // A beat behind the window, which fades over 0.2s: clearing the text on the same tick
        // empties the island while the user can still see it.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.3) { [weak self] in
            // Only if nothing has happened since: a question asked inside the window is now the
            // live session, and clearing it would take the user's own answer off the screen.
            guard let self, case .error = self.machine.state else { return }
            // Hovering means it is being read, and the panel pauses its own timer for exactly
            // that. The state has to wait with it, or the message goes blank under the pointer —
            // and it gives up at the same moment the window does, not later.
            guard !self.panel.canHoldForHover else { return self.dismiss(after: 3) }
            self.apply(.autoHideElapsed)
        }
    }

    func reset() {
        cancelAcknowledgement()
        spokeAcknowledgement = false
        panel.model.transcript = ""
        panel.model.answer = ""
        panel.model.aside = nil
        panel.model.draft = nil
        panel.model.permissionURL = nil
        discardCapture()
    }

    func scheduleAutoHide() {
        guard case .answering = machine.state else { return }
        panel.hide(after: TimeInterval(config.panelAutoHideSeconds))
        // A mark outlives the panel a little: the user is usually still looking at the control.
        // How much longer depends on how many marks there are, because they are drawn one after
        // another — see `AnnotationOverlay.lifetime`.
        annotations.hide(after: AnnotationOverlay.lifetime(
            forMarks: annotations.markCount,
            atLeast: TimeInterval(config.panelAutoHideSeconds) + 4))
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(config.panelAutoHideSeconds)) { [weak self] in
            guard let self, case .answering = self.machine.state else { return }
            self.apply(.autoHideElapsed)
        }
    }

    func render() {
        panel.model.state = machine.state
        // Idle is not a thing to announce. The island used to sit there afterwards reading
        // "Ready" — for three seconds after a dictation, and again at the end of an answer — which
        // is a window telling the user that nothing is happening.
        guard machine.state != .idle else { return panel.rollUp() }
        panel.show()
    }
}
