import Foundation

/// Runs a plan step by step: policy first, then the user if the policy says ask, then the action,
/// then the log. Sequential and abortive by design — a plan is an ordered thing, so a step that is
/// refused or that fails stops the rest rather than carrying on into a half-done state.
final class ActionRunner {
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

        var performed: Int { steps.filter { $0.outcome == .performed }.count }
        var completed: Bool { !stoppedEarly && steps.allSatisfy { $0.outcome == .performed } }

        /// What the panel says afterwards.
        var summary: String {
            guard let last = steps.last else { return "Nothing to do." }
            switch last.outcome {
            case .performed:
                return performed == 1 ? "Done." : "Done — \(performed) steps."
            case .denied(let why): return "Stopped: \(why)"
            case .declined: return "Stopped, nothing was changed."
            case .failed(let why): return "Stopped after \(performed): \(why)"
            }
        }
    }

    private let performer: ActionPerforming
    private let confirm: (Action, String?) -> Bool
    private var cancelled = false

    /// - Parameter confirm: asked when the policy says `confirm`. Returns true to go ahead.
    init(performer: ActionPerforming, confirm: @escaping (Action, String?) -> Bool) {
        self.performer = performer
        self.confirm = confirm
    }

    func cancel() { cancelled = true }

    func run(_ plan: ActionPlan, elements: [AXElementScanner.Element], policy: ActionPolicy,
             bundleID: String?, appPID: pid_t? = nil,
             onStep: ((Action, Int, Int) -> Void)? = nil) -> Result {
        cancelled = false
        let byID = Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0) })
        let actions = Array(plan.actions.prefix(ActionPlan.maximumActions))
        var steps: [Step] = []

        for (index, action) in actions.enumerated() {
            if cancelled {
                return Result(steps: steps, stoppedEarly: true)
            }
            let element = action.element.flatMap { byID[$0] }
            let decision = policy.decision(for: action, bundleID: bundleID, elementLabel: element?.label)

            switch decision {
            case .deny:
                steps.append(Step(action: action, outcome: .denied("not allowed here")))
                return Result(steps: steps, stoppedEarly: true)
            case .confirm:
                guard confirm(action, bundleID) else {
                    steps.append(Step(action: action, outcome: .declined))
                    return Result(steps: steps, stoppedEarly: true)
                }
            case .allow:
                break
            }

            onStep?(action, index, actions.count)
            do {
                try performer.perform(action, on: element, in: appPID)
                steps.append(Step(action: action, outcome: .performed))
                log(action, bundleID: bundleID, decision: decision, confirmed: decision == .confirm,
                    succeeded: true, detail: nil)
            } catch {
                let message = (error as? KestrelError)?.errorDescription ?? error.localizedDescription
                steps.append(Step(action: action, outcome: .failed(message)))
                log(action, bundleID: bundleID, decision: decision, confirmed: decision == .confirm,
                    succeeded: false, detail: message)
                return Result(steps: steps, stoppedEarly: true)
            }
        }
        return Result(steps: steps, stoppedEarly: false)
    }

    private func log(_ action: Action, bundleID: String?, decision: ActionPolicy.Decision,
                     confirmed: Bool, succeeded: Bool, detail: String?) {
        ActionLog.record(ActionLog.Entry(at: Date(), kind: action.kind, describe: action.describe,
                                         app: bundleID, decision: decision, confirmed: confirmed,
                                         succeeded: succeeded, detail: detail))
    }
}
