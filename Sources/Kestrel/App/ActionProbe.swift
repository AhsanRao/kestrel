import AppKit
import Foundation

/// Asks the question in `KESTREL_ASK` through the real pipeline — screenshot, model, tools, voice —
/// with the transcript typed in rather than spoken, then prints what happened and quits.
///
/// This is how the act-observe loop is exercised without a microphone: the hotkey still works
/// for confirmations, or `KESTREL_ASK_CONFIRM=yes|no` answers them from the script after a beat,
/// which is what lets the gate be checked unattended.
enum ActionProbe {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["KESTREL_ASK"] != nil }

    static func run(on coordinator: SessionCoordinator) {
        let env = ProcessInfo.processInfo.environment
        let text = env["KESTREL_ASK"] ?? ""
        let scripted = env["KESTREL_ASK_CONFIRM"].map { $0.lowercased().hasPrefix("y") }
        let started = Date()
        print("asking: \(text)")

        coordinator.onStateChange = { state in
            let elapsed = String(format: "%5.1fs", Date().timeIntervalSince(started))
            print("\(elapsed)  \(state)")
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

        coordinator.machine = SessionMachine(state: .thinking)
        coordinator.panel.model.transcript = text
        coordinator.render()
        let config = coordinator.config
        coordinator.captureQueue.async {
            coordinator.pendingCapture = try? ScreenGrabber.capture(maxEdge: config.screenshotMaxEdge,
                                                                     mode: config.captureMode)
            coordinator.pendingScreen = ScreenSnapshot.read(bundleID: TextInjector.frontmostBundleID())
            coordinator.work.async { coordinator.runAsk(text) }
        }
    }

    private static func finish(after seconds: TimeInterval, coordinator: SessionCoordinator) {
        // Let the last sentence be heard before quitting.
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard !coordinator.speech.isSpeaking else { return finish(after: 1, coordinator: coordinator) }
            NSApp.terminate(nil)
        }
    }
}
