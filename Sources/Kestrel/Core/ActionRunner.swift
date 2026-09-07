import Foundation

/// Runs a plan step by step: policy first, then the user if the policy says ask, then the action,
/// then the log. Sequential and abortive by design — a plan is an ordered thing, so a step that is
/// refused or that fails stops the rest rather than carrying on into a half-done state.
final class ActionRunner {
    /// What the user said when asked.
    enum Consent: Equatable {
        /// Go ahead with this step, and with the rest of this run in the same app.
        case once
        /// Go ahead, and stop asking about this app altogether.
        case always
        /// Stop the run.
        case no
    }

    enum Outcome: Equatable {
        case performed
        case denied(String)
        case declined
        case failed(String)
    }

    struct Step: Equatable {
        var action: Action
        var outcome: Outcome
    }

    struct Result: Equatable {
        var steps: [Step]
        var stoppedEarly: Bool
        /// Set when the run launched an app. Everything planned after that points at controls in
        /// the app the user *was* in, so the rest of the plan is thrown away and asked for again
        /// against the app that is now in front.
        var launchedApp: String?

        var performed: Int { steps.filter { $0.outcome == .performed }.count }
        var completed: Bool { !stoppedEarly && steps.allSatisfy { $0.outcome == .performed } }
        /// True when the run stopped only because the ground moved under it.
        var needsReplan: Bool { launchedApp != nil && !stoppedEarly }

        /// What the panel says afterwards.
        var summary: String {
            guard let last = steps.last else { return "Nothing to do." }
            switch last.outcome {
            case .performed:
                if let app = launchedApp { return "Opened \(app)." }
                return performed == 1 ? "Done." : "Done — \(performed) steps."
            case .denied(let why): return "Stopped: \(why)"
            case .declined: return "Stopped, nothing was changed."
            case .failed(let why): return "Stopped after \(performed): \(why)"
            }
        }
    }

    private let performer: ActionPerforming
    private let confirm: (Action, String?) -> Consent
    private var cancelled = false
    /// Apps the user has vouched for, for the length of this run.
    private var granted: Set<String> = []

    /// - Parameter confirm: asked when the policy says `confirm` and the step is not destructive.
    init(performer: ActionPerforming, confirm: @escaping (Action, String?) -> Consent) {
        self.performer = performer
        self.confirm = confirm
    }

    /// Apps already vouched for when the run starts — how a re-plan carries the answer the user
    /// gave a moment ago instead of asking for it again.
    func grant(_ bundleID: String?) {
        guard let bundleID else { return }
        granted.insert(bundleID)
    }

    func cancel() { cancelled = true }

    func run(_ plan: ActionPlan, elements: [AXElementScanner.Element], policy: ActionPolicy,
             bundleID: String?, appPID: pid_t? = nil,
             onStep: ((Action, Int, Int) -> Void)? = nil) -> Result {
        cancelled = false
        let byID = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let actions = Array(plan.actions.prefix(ActionPlan.maximumActions))
        var steps: [Step] = []

        for (index, action) in actions.enumerated() {
            if cancelled {
                return Result(steps: steps, stoppedEarly: true)
            }
            let element = action.element.flatMap { byID[$0] }
            let ruling = policy.ruling(for: action, bundleID: bundleID, elementLabel: element?.label)

            switch ruling.decision {
            case .deny:
                steps.append(Step(action: action, outcome: .denied("not allowed here")))
                return Result(steps: steps, stoppedEarly: true)
            case .confirm:
                // Asking again about an app the user has already vouched for in this run is how a
                // four-step task turned into four alerts. A destructive step still asks, every time.
                if ruling.isDestructive || !isGranted(bundleID) {
                    switch confirm(action, bundleID) {
                    case .always:
                        // Persisting it is the caller's business; the runner only remembers it for
                        // as long as this run lasts, and never writes to disk from a test.
                        grant(bundleID)
                    case .once:
                        // Only a plain "not vouched for yet" question grants the rest of the run.
                        // Saying yes to sending one message must not authorise sending the next.
                        if !ruling.isDestructive { grant(bundleID) }
                    case .no:
                        steps.append(Step(action: action, outcome: .declined))
                        return Result(steps: steps, stoppedEarly: true)
                    }
                }
            case .allow:
                break
            }

            onStep?(action, index, actions.count)
            do {
                try performer.perform(action, on: element, in: appPID)
                steps.append(Step(action: action, outcome: .performed))
                log(action, bundleID: bundleID, decision: ruling.decision,
                    confirmed: ruling.decision == .confirm, succeeded: true, detail: nil)
                // The app in front is now a different app, so every element number still in the
                // plan describes a control that is no longer on screen. Stop and ask again.
                if action.kind == .launchApp {
                    return Result(steps: steps, stoppedEarly: false, launchedApp: action.value)
                }
            } catch {
                let message = (error as? KestrelError)?.errorDescription ?? error.localizedDescription
                steps.append(Step(action: action, outcome: .failed(message)))
                log(action, bundleID: bundleID, decision: ruling.decision,
                    confirmed: ruling.decision == .confirm, succeeded: false, detail: message)
                return Result(steps: steps, stoppedEarly: true)
            }
        }
        return Result(steps: steps, stoppedEarly: false)
    }

    private func isGranted(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return granted.contains(bundleID)
    }

    private func log(_ action: Action, bundleID: String?, decision: ActionPolicy.Decision,
                     confirmed: Bool, succeeded: Bool, detail: String?) {
        ActionLog.record(ActionLog.Entry(at: Date(), kind: action.kind, describe: action.describe,
                                         app: bundleID, decision: decision, confirmed: confirmed,
                                         succeeded: succeeded, detail: detail))
    }
}
