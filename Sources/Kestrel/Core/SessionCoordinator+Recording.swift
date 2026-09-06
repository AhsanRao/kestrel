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

        // The screenshot and the transcript do not depend on each other, so they are taken at the
        // same time. On a busy screen that is a few hundred milliseconds the user does not wait.
        var captureError: Error?
        let capturing = DispatchGroup()
        if intent == .ask {
            capturing.enter()
            captureQueue.async { [weak self] in
                defer { capturing.leave() }
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
        }

        work.async { [weak self] in
            guard let self else { return }
            self.transcribe(wav, intent: intent) {
                capturing.wait()
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
