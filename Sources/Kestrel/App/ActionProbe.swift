import AppKit
import Foundation

/// Asks the question in `KESTREL_ASK` through the real pipeline — screenshot, model, tools, voice —
/// with the transcript typed in rather than spoken, then prints what happened and quits.
///
/// This is how the act-observe loop is exercised without a microphone: the hotkey still works
/// for confirmations, or `KESTREL_ASK_CONFIRM=yes|no` answers them from the script after a beat,
/// which is what lets the gate be checked unattended.
enum ActionProbe {
    static var isRequested: Bool {
        let env = ProcessInfo.processInfo.environment
        return ["KESTREL_ASK", "KESTREL_TRIAGE", "KESTREL_JUDGE", "KESTREL_CONSENT", "KESTREL_AIM", "KESTREL_TYPE",
                "KESTREL_SAY"]
            .contains { env[$0] != nil }
    }

    static func run(on coordinator: SessionCoordinator) {
        let env = ProcessInfo.processInfo.environment
        if let lines = env["KESTREL_TRIAGE"] { return triage(lines, config: coordinator.config) }
        if let lines = env["KESTREL_JUDGE"] { return judge(lines, config: coordinator.config) }
        if let lines = env["KESTREL_CONSENT"] { return consent(lines, config: coordinator.config) }
        if let label = env["KESTREL_AIM"] { return aim(label, config: coordinator.config) }
        if let spec = env["KESTREL_TYPE"] { return typeTest(spec, config: coordinator.config) }
        if let lines = env["KESTREL_SAY"] {
            return say(lines, release: env["KESTREL_SAY_RELEASE"].flatMap(Double.init) ?? 4, on: coordinator)
        }
        let text = env["KESTREL_ASK"] ?? ""
        let scripted = env["KESTREL_ASK_CONFIRM"].map { $0.lowercased().hasPrefix("y") }
        // `KESTREL_ASK_CANCEL_AFTER=3`: Esc three seconds in, then the same question again — the
        // second run has to come out clean, with the first's late results dropped on the floor.
        let cancelAfter = env["KESTREL_ASK_CANCEL_AFTER"].flatMap(Double.init)
        let started = Date()
        print("asking: \(text)")
        if let cancelAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) {
                print(String(format: "%5.1fs  ESC", Date().timeIntervalSince(started)))
                coordinator.cancelSession()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    print(String(format: "%5.1fs  asking again", Date().timeIntervalSince(started)))
                    ask(text, on: coordinator)
                }
            }
        }

        coordinator.onStateChange = { state in
            let elapsed = String(format: "%5.1fs", Date().timeIntervalSince(started))
            print("\(elapsed)  \(state)")
            if cancelAfter != nil, Date().timeIntervalSince(started) < (cancelAfter ?? 0) + 1 { return }
            if case .confirming(let what) = state, let scripted {
                print("\(elapsed)  confirmation wanted: \(what) → scripted \(scripted ? "yes" : "no")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { coordinator.decide(scripted) }
            }
            switch state {
            case .answering:
                print("answer: \(coordinator.panel.model.answer)")
                print("steps: \(coordinator.actingSteps)")
                finish(after: 2, coordinator: coordinator)
            case .error(let message):
                print("error: \(message)")
                finish(after: 1, coordinator: coordinator)
            default:
                break
            }
        }

        ask(text, on: coordinator)
    }

    private static func ask(_ text: String, on coordinator: SessionCoordinator) {
        coordinator.machine = SessionMachine(state: .thinking)
        coordinator.panel.model.transcript = text
        coordinator.render()
        let config = coordinator.config
        coordinator.captureQueue.async {
            coordinator.pendingCapture = try? ScreenGrabber.capture(maxEdge: config.screenshotMaxEdge,
                                                                     mode: config.captureMode)
            coordinator.pendingScreen = ScreenSnapshot.read(bundleID: TextInjector.frontmostBundleID())
            let stamp = DispatchQueue.main.sync { coordinator.beginGeneration() }
            coordinator.work.async { coordinator.runAsk(text, stamp: stamp) }
        }
    }

    /// The live-ask flow with a scripted microphone: the chord goes down, the phrases are "said"
    /// on a clock, the chord comes up after `release` seconds, and every state change is printed.
    private static func say(_ lines: String, release: TimeInterval, on coordinator: SessionCoordinator) {
        let phrases = lines.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let started = Date()
        var answers = 0
        func stamp() -> String { String(format: "%5.1fs", Date().timeIntervalSince(started)) }
        coordinator.makeLiveEngine = { _ in ScriptedMicrophone(phrases: phrases) }
        coordinator.onStateChange = { state in
            print("\(stamp())  \(state)  drag=\(coordinator.dragTracker.isTracking) queued=\(coordinator.phrases.count)")
            if case .answering = state {
                answers += 1
                print("answer: \(coordinator.panel.model.answer)")
                if answers == phrases.count { finish(after: 2, coordinator: coordinator) }
            }
            if case .error(let message) = state { print("error: \(message)") }
        }
        print("chord down; saying: \(phrases.joined(separator: " / "))")
        coordinator.handle(.ask, .pressed)
        DispatchQueue.main.asyncAfter(deadline: .now() + release) {
            print("\(stamp())  chord up")
            coordinator.handle(.ask, .released)
        }
        // Whatever happens, do not sit here forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { print("gave up"); exit(1) }
    }

    private static func finish(after seconds: TimeInterval, coordinator: SessionCoordinator) {
        // Let the last sentence be heard before quitting.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard !coordinator.speech.isSpeaking else { return finish(after: 1, coordinator: coordinator) }
            NSApp.terminate(nil)
        }
    }
}
