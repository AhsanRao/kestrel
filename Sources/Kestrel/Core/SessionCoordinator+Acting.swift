import AppKit
import Foundation

/// The model's hands (spec §8.18): the socket its tools are served on, the session behind one
/// question, and the yes-or-no the user is asked before anything irreversible.
extension SessionCoordinator {
    /// How long a confirmation waits before it is taken as a no.
    static let confirmationTimeout: TimeInterval = 30
    /// Controls listed to the model after a step. Fewer than a question gets: they cost tokens on
    /// every step, and the model only needs the ones it might press next.
    static let maximumListedControls = 60

    /// How many steps the question in flight has taken. For the probe's report.
    var actingSteps: Int { acting?.steps ?? lastActingSteps }

    func startToolServer() {
        toolServer.handler = { [weak self] line in
            guard let self else { return nil }
            return MCPProtocol(call: { call in
                let session = DispatchQueue.main.sync { self.acting }
                return session?.handle(call) ?? .failure("Kestrel isn't in the middle of a question.")
            }).respond(to: line)
        }
        toolServer.start()
    }

    /// A fresh session for the question about to be asked. Called on `work`.
    func beginActing(with capture: ScreenCapture?) -> ActionSession {
        let config = config
        let hooks = ActionSession.Hooks(
            confirm: { [weak self] what in self?.askPermission(for: what) ?? false },
            perform: { call, capture in try Actuator.perform(call, screenshot: capture, config: config) },
            observe: { [weak self] in self?.observe() ?? .init(controls: "") },
            frontmostBundleID: { TextInjector.frontmostBundleID() },
            elementLabel: { Actuator.elementLabel(at: $0) },
            progress: { [weak self] line in
                DispatchQueue.main.async { self?.panel.model.aside = line; self?.render() }
            },
            capHit: { [weak self] in DispatchQueue.main.async { self?.outOfSteps() } })
        let session = ActionSession(policy: config.actionPolicy, maximumSteps: config.maxAgentSteps,
                                    initialCapture: capture, hooks: hooks)
        DispatchQueue.main.sync { self.acting = session }
        return session
    }

    /// The answer has landed: the session's screenshots go, and later tool calls are refused.
    func endActing() {
        lastActingSteps = acting?.steps ?? 0
        acting?.cancel()
        acting?.cleanUp()
        acting = nil
    }

    /// Esc, a failure, a new question: stop the hands, and let go of anything waiting on a yes.
    func abandonActing() {
        guard acting != nil else { return }
        decide(false)
        endActing()
        router.cancel()
    }

    // MARK: - Looking

    /// The screen after a step. Runs on the socket queue; the pause is for the app to catch up
    /// with what was just done to it — a menu still animating open is not the result.
    private func observe() -> ActionSession.Observation {
        Thread.sleep(forTimeInterval: 0.6)
        let capture = try? ScreenGrabber.capture(maxEdge: config.screenshotMaxEdge, mode: config.captureMode)
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName
        var lines: [String] = []
        if let capture {
            for element in AXElementScanner.scanFrontmostApp().prefix(SessionCoordinator.maximumListedControls) {
                let centre = CGPoint(x: element.frame.midX, y: element.frame.midY)
                guard let pixel = capture.pixel(forScreenPoint: centre),
                      pixel.x >= 0, pixel.y >= 0, pixel.x <= capture.pixelSize.width,
                      pixel.y <= capture.pixelSize.height else { continue }
                lines.append("\(element.asTarget.listing) at \(Int(pixel.x)), \(Int(pixel.y))")
            }
        }
        return .init(capture: capture, controls: lines.joined(separator: "\n"), frontmost: frontmost)
    }

    // MARK: - Asking

    /// Called on the socket queue. Says what is about to happen and blocks until the user
    /// answers with the hotkey, or the wait runs out — which is a no.
    func askPermission(for what: String) -> Bool {
        let answered = DispatchSemaphore(value: 0)
        var decision = false
        DispatchQueue.main.async {
            guard case .thinking = self.machine.state else { answered.signal(); return }
            self.pendingDecision = { decision = $0; answered.signal() }
            self.apply(.confirmationNeeded(what))
            self.panel.model.aside = "About to \(what)"
            self.render()
            if self.config.speakAnswers {
                self.speech.speak(Confirmation.prompt(for: what), config: self.config)
            } else {
                self.panel.announce(Confirmation.prompt(for: what))
            }
        }
        if answered.wait(timeout: .now() + SessionCoordinator.confirmationTimeout) == .timedOut {
            DispatchQueue.main.async { self.decide(false) }
        }
        return decision
    }

    /// The hotkey went down while a confirmation was waiting: record what is said, if anything.
    func beginConfirmRecording() {
        speech.stop()
        sounds.play(.listening, config: config)
        do {
            try audio.start(maxDuration: 10)
        } catch {
            decide(false)
        }
    }

    /// …and came up again. Nothing recorded is a tap, and a tap is a yes.
    func finishConfirmRecording() {
        sounds.play(.heard, config: config)
        guard let wav = audio.stop() else { return decide(true) }
        work.async { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: wav) }
            let heard = (try? self.transcriber.transcribe(wav, config: self.config)) ?? ""
            DispatchQueue.main.async { self.decide(Confirmation.isYes(heard)) }
        }
    }

    /// Main thread. Releases whoever is waiting, once.
    func decide(_ yes: Bool) {
        guard let finish = pendingDecision else { return }
        pendingDecision = nil
        if case .confirming = machine.state {
            panel.model.aside = yes ? "Going ahead" : "Leaving it"
            apply(yes ? .confirmed : .declined)
        }
        finish(yes)
    }

    /// The budget is gone. Said here, before the model's own last sentence, so the user hears
    /// the plain fact first and the explanation after.
    private func outOfSteps() {
        panel.model.aside = "Out of steps"
        render()
        guard config.speakAnswers, speech.speak("I couldn't complete that.", config: config) else { return }
        // The model's next sentence queues behind this rather than cutting it off.
        spokeAcknowledgement = true
    }
}
