import AppKit
import Foundation

/// Starting and stopping a take: microphone, the circle-a-region gesture, and the screenshot that
/// is captured alongside the transcript rather than after it.
extension SessionCoordinator {
    // MARK: - Recording

    func beginRecording(intent: SessionIntent) {
        focusRegion = nil
        // Marks from the last answer belong to the last answer.
        annotations.hide()
        // While the hotkey is held the user may circle something; the trail is drawn as they go.
        if intent == .ask, config.spatialContext {
            selection.show()
            dragTracker.begin()
        }
        panel.model.transcript = ""
        panel.model.answer = ""
        panel.model.permissionURL = nil
        panel.show()
        sounds.play(.listening, config: config)
        listeningStartedAt = Date()

        AudioCapture.requestPermission { [weak self] granted in
            guard let self else { return }
            guard granted else { self.fail(KestrelError.microphoneDenied); return }
            do {
                try self.audio.start(maxDuration: intent == .ask ? 60 : 600)
            } catch AudioCapture.Failure.permissionDenied {
                self.fail(KestrelError.microphoneDenied)
            } catch {
                self.fail(KestrelError.transcriptionFailed(error.localizedDescription))
            }
        }
    }

    func finishRecording(intent: SessionIntent) {
        focusRegion = dragTracker.end()
        selection.settle(focusRegion)
        sounds.play(.heard, config: config)
        let wav = audio.stop()
        guard let wav else {
            // Under 300 ms, or nothing above the noise floor: not a question.
            apply(.cancelled)
            panel.hideImmediately()
            return
        }
        let maxEdge = config.screenshotMaxEdge
        let captureMode = config.captureMode

        // The transcript, the screenshot and the Accessibility scan all describe the same moment
        // and none of them needs the others, so all three run at once. Reading the screen after the
        // transcript landed used to add its whole cost to the wait; now it is free.
        var captureError: Error?
        let gathering = DispatchGroup()
        if intent == .ask {
            gathering.enter()
            captureQueue.async { [weak self] in
                defer { gathering.leave() }
                do {
                    let capture = try ScreenGrabber.capture(maxEdge: maxEdge, mode: captureMode)
                    self?.pendingCapture = capture
                    if let region = self?.focusRegion {
                        self?.pendingCrop = ScreenGrabber.crop(capture, to: region)
                    }
                } catch {
                    captureError = error
                }
            }
            let bundleID = TextInjector.frontmostBundleID()
            gathering.enter()
            scanQueue.async { [weak self] in
                defer { gathering.leave() }
                self?.pendingScreen = ScreenSnapshot.read(bundleID: bundleID)
            }
        }

        work.async { [weak self] in
            guard let self else { return }
            self.transcribe(wav, intent: intent) {
                gathering.wait()
                if let captureError { throw captureError }
            }
        }
    }

    /// The engine stopped by itself: max duration hit, or the input device went away.
    func audioStoppedOnItsOwn(_ url: URL?) {
        guard machine.state == .listening || machine.state == .dictating else { return }
        let intent: SessionIntent = machine.state == .dictating ? .dictation : .ask
        guard url != nil else { apply(.cancelled); panel.hideImmediately(); return }
        apply(intent == .ask ? .askReleased : .dictateToggled)
    }
}
