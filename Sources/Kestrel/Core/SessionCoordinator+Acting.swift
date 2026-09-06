import AppKit
import Foundation

/// Doing what was asked, rather than describing it.
///
/// The run happens on the background queue so the UI stays live, but every decision the user is
/// part of — the confirmation, the overlay, the summary — hops to the main thread.
extension SessionCoordinator {
    func runAgent(_ text: String, bundleID: String?) {
        let elements = AXElementScanner.scanFrontmostApp()
        guard !elements.isEmpty else {
            // Nothing to act on: answer the question instead of guessing at coordinates.
            return runAsk(text, forceAnswer: true)
        }
        DispatchQueue.main.sync { self.scannedElements = elements }

        let query = Query(text: text, screenshot: pendingCapture?.url, mode: .agent,
                          elements: elements, skills: SkillLibrary.notes(forBundleID: bundleID))
        do {
            let answer = try router.ask(query, config: config)
            guard let plan = ActionPlanParser.parse(answer.text), !plan.actions.isEmpty else {
                let reason = ActionPlanParser.parse(answer.text)?.goal ?? answer.text
                discardCapture()
                DispatchQueue.main.async {
                    self.present(Answer(text: reason.isEmpty ? "I couldn't work out how to do that here."
                                                             : reason,
                                        raw: answer.raw, durationMs: answer.durationMs))
                }
                return
            }
            discardCapture()
            DispatchQueue.main.async { self.begin(plan, elements: elements, bundleID: bundleID) }
        } catch is CancellationError {
            discardCapture()
        } catch {
            discardCapture()
            finish(with: error)
        }
    }

    // MARK: - Running

    private func begin(_ plan: ActionPlan, elements: [AXElementScanner.Element], bundleID: String?) {
        apply(.actionsReady)
        render()
        panel.hideImmediately()

        agentOverlay.model.begin(goal: plan.goal, stepCount: min(plan.actions.count, ActionPlan.maximumActions))
        agentOverlay.show()

        let runner = ActionRunner(performer: actuator) { [weak self] action, app in
            self?.askPermission(for: action, app: app) ?? false
        }
        activeRun = runner
        escapeWatcher.onEscape = { [weak self] in self?.stopRun() }
        escapeWatcher.start()

        let policy = ActionPolicy.load()
        let byID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        work.async { [weak self] in
            guard let self else { return }
            let result = runner.run(plan, elements: elements, policy: policy, bundleID: bundleID,
                                    onStep: { [weak self] action, index, _ in
                DispatchQueue.main.async {
                    self?.agentOverlay.model.show(action, at: action.element.flatMap { byID[$0]?.frame },
                                                  index: index)
                }
                // A beat between steps: the user has to be able to see what is happening.
                Thread.sleep(forTimeInterval: 0.45)
            })
            DispatchQueue.main.async { self.finished(result) }
        }
    }

    /// Modal, and deliberately so: this is the one moment the user has to be in the loop.
    private func askPermission(for action: Action, app: String?) -> Bool {
        var allowed = false
        let ask = {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = action.describe
            alert.informativeText = app.map { "Kestrel wants to do this in \($0)." }
                ?? "Kestrel wants to do this."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Do it")
            alert.addButton(withTitle: "Stop")
            allowed = alert.runModal() == .alertFirstButtonReturn
        }
        if Thread.isMainThread { ask() } else { DispatchQueue.main.sync(execute: ask) }
        return allowed
    }

    func stopRun() {
        activeRun?.cancel()
    }

    private func finished(_ result: ActionRunner.Result) {
        escapeWatcher.stop()
        activeRun = nil
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
