import AppKit
import Foundation

/// Doing what was asked, rather than describing it.
///
/// The run happens on the background queue so the UI stays live, but every decision the user is
/// part of — the confirmation, the overlay, the summary — hops to the main thread.
extension SessionCoordinator {
    func runAgent(_ text: String, bundleID: String?, continuing: ActionContinuation? = nil) {
        // Without Accessibility, the scan below always comes back empty — which used to be read as
        // "nothing to act on" and silently downgraded to a spoken description. That looked like
        // Kestrel refusing to act for no reason. Say what is actually missing instead.
        guard AXElementScanner.isAvailable else {
            discardCapture()
            TextInjector.requestAccessibilityPermission()
            return finish(with: KestrelError.accessibilityDenied)
        }
        // Pinned now, while the app the user was looking at is still frontmost. By the time a
        // keystroke runs, a confirmation dialog may have made Kestrel frontmost instead.
        let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Acting reaches into the menus: driving a media app means Playback ▸ Next, which is a menu
        // item and not a button on the window.
        let elements = AXElementScanner.scanFrontmostApp(menuDepth: AXElementScanner.deepMenuDepth,
                                                         limit: AXElementScanner.maximumElementsWhenActing)
        guard !elements.isEmpty else {
            // Permission is granted but this screen genuinely has nothing to act on: answer the
            // question instead of guessing at coordinates.
            return runAsk(text, forceAnswer: true)
        }
        DispatchQueue.main.sync { self.scannedElements = elements }

        // A task gets its own folder, so anything it writes has somewhere to land and the CLI has
        // a working directory that cannot wander outside ~/.kestrel.
        let project = ProjectStore.create(for: text)
        let query = Query(text: continuing?.prompt(for: text) ?? text,
                          screenshot: pendingCapture?.url, mode: .agent,
                          elements: elements, skills: SkillLibrary.notes(forBundleID: bundleID),
                          workingDirectory: project)
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
            DispatchQueue.main.async {
                self.begin(plan, elements: elements, bundleID: bundleID, appPID: targetPID,
                           request: text, continuing: continuing)
            }
        } catch is CancellationError {
            discardCapture()
        } catch {
            discardCapture()
            finish(with: error)
        }
    }

    // MARK: - Running

    private func begin(_ plan: ActionPlan, elements: [AXElementScanner.Element], bundleID: String?,
                       appPID: pid_t?, request: String, continuing: ActionContinuation?) {
        // A continued run is already acting; re-entering the state would be a no-op that also
        // resets the overlay the user is watching.
        if machine.state != .acting { apply(.actionsReady) }
        render()
        panel.hideImmediately()

        agentOverlay.model.begin(goal: plan.goal, stepCount: min(plan.actions.count, ActionPlan.maximumActions))
        agentOverlay.show()

        let runner = ActionRunner(performer: actuator) { [weak self] action, app in
            self?.askPermission(for: action, app: app) ?? .no
        }
        // Whatever the user has already said yes to carries into this leg of the run.
        for app in grantedApps { runner.grant(app) }
        activeRun = runner
        escapeWatcher.onEscape = { [weak self] in self?.stopRun() }
        escapeWatcher.start()

        let policy = ActionPolicy.load()
        let byID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        work.async { [weak self] in
            guard let self else { return }
            let result = runner.run(plan, elements: elements, policy: policy, bundleID: bundleID,
                                    appPID: appPID,
                                    onStep: { [weak self] action, index, _ in
                DispatchQueue.main.async {
                    self?.agentOverlay.model.show(action, at: action.element.flatMap { byID[$0]?.frame },
                                                  index: index)
                }
                // A beat between steps: the user has to be able to see what is happening.
                Thread.sleep(forTimeInterval: 0.45)
            })
            DispatchQueue.main.async {
                if let app = result.launchedApp, result.needsReplan {
                    self.replan(after: app, request: request, done: result, continuing: continuing)
                } else {
                    self.finished(result)
                }
            }
        }
    }
}
