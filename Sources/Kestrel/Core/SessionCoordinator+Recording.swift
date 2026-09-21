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
            // Dictation types as it hears, where the engine can: nothing is worth waiting for the
            // end of a sentence to see. Anything that cannot stream records a take instead.
            if intent == .dictation, self.beginLiveDictation() { return }
            // A question is heard the same way, and sent at the first pause rather than the release.
            if intent == .ask, self.beginLiveAsk() { return }
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
        if intent == .dictation, finishLiveDictation() { return }
        if intent == .ask, finishLiveAsk() { return }
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
        let stamp = beginGeneration()
        let awaitScreen = intent == .ask ? gatherScreen(stamp: stamp) : nil
        work.async { [weak self] in
            self?.transcribe(wav, intent: intent, stamp: stamp, awaitCapture: awaitScreen)
        }
    }

    /// Starts the screenshot and the Accessibility scan, and returns what blocks until both have
    /// landed. Main thread.
    ///
    /// The transcript, the screenshot and the scan all describe the same moment and none of them
    /// needs the others, so all three run at once. Reading the screen after the transcript landed
    /// used to add its whole cost to the wait; now it is free.
    func gatherScreen(stamp: Int) -> () throws -> Void {
        let maxEdge = config.screenshotMaxEdge
        let captureMode = config.captureMode
        var captureError: Error?
        let gathering = DispatchGroup()
        gathering.enter()
        captureQueue.async { [weak self] in
            defer { gathering.leave() }
            do {
                let capture = try ScreenGrabber.capture(maxEdge: maxEdge, mode: captureMode)
                // Esc while the screenshot was being taken: it is nobody's now.
                guard self?.stillCurrent(stamp) == true else {
                    try? FileManager.default.removeItem(at: capture.url)
                    return
                }
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
        return {
            gathering.wait()
            if let captureError { throw captureError }
        }
    }

    /// The engine stopped by itself: max duration hit, or the input device went away.
    func audioStoppedOnItsOwn(_ url: URL?) {
        // A yes held for ten seconds is still a yes; decide on what was heard.
        if case .confirming = machine.state { return apply(.askReleased) }
        guard machine.state == .listening || machine.state == .dictating else { return }
        let intent: SessionIntent = machine.state == .dictating ? .dictation : .ask
        guard url != nil else { apply(.cancelled); panel.hideImmediately(); return }
        apply(intent == .ask ? .askReleased : .dictateToggled)
    }
}
