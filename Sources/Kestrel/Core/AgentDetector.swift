import Foundation

/// Does the user want Kestrel to *do* this, or to explain it?
///
/// The distinction matters more than usual, because one branch answers a question and the other
/// touches their Mac. "How do I archive this?" is a walkthrough. "Archive this" is an action. When
/// it is not clearly an instruction, Kestrel answers instead — the wrong answer costs a sentence,
/// the wrong action costs an email.
enum AgentDetector {
    /// Phrasings that ask for an explanation, whatever verb follows.
    private static let questionOpeners = [
        "how do i", "how do you", "how can i", "how would i", "how to", "what is", "what's",
        "where is", "where do i", "why", "can you explain", "show me how", "what does",
    ]

    /// Verbs that only make sense as instructions.
    private static let imperatives = [
        "open", "launch", "click", "press", "select", "choose", "switch", "close", "quit",
        "type", "write", "fill", "enter", "set", "rename", "create", "add", "insert",
        "send", "reply", "forward", "archive", "delete", "remove", "move", "copy", "paste",
        "scroll", "search for", "go to", "turn on", "turn off", "enable", "disable",
        "save", "export", "print", "share", "start", "stop", "run", "check", "mark",
    ]

    static func wantsAction(_ text: String, config: Config) -> Bool {
        guard config.agentActions else { return false }
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return false }
        // A question is a question even when it contains an imperative verb.
        guard !questionOpeners.contains(where: { lowered.hasPrefix($0) }) else { return false }
        guard !lowered.hasSuffix("?") else { return false }

        // Matched as a leading phrase, so both "open Slack" and "turn on dark mode" count.
        return imperatives.contains { verb in
            lowered == verb || lowered.hasPrefix("\(verb) ")
                || lowered.hasPrefix("please \(verb) ") || lowered.contains(", \(verb) ")
        }
    }
}

/// Reads an `ActionPlan` out of whatever the model returned, on the same defensive terms as the
/// walkthrough parser: fences, prose and missing fields must not reach the actuator.
enum ActionPlanParser {
    static func parse(_ raw: String) -> ActionPlan? {
        guard let json = WalkthroughParser.extractObject(from: raw),
              let data = json.data(using: .utf8),
              var plan = try? JSONDecoder().decode(ActionPlan.self, from: data) else { return nil }
        plan.actions = sanitize(plan.actions)
        plan.goal = plan.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return plan
    }

    /// Drops steps that point at nothing, or that describe nothing the user could judge.
    static func sanitize(_ actions: [Action]) -> [Action] {
        Array(actions.filter { action in
            guard !action.describe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            switch action.kind {
            case .launchApp: return !(action.value ?? "").isEmpty
            case .setValue: return action.element != nil && action.value != nil
            default: return action.element != nil
            }
        }.prefix(ActionPlan.maximumActions))
    }
}
