import Foundation

/// Keeps the last exchange alive briefly so the next question can be a follow-up.
///
/// Every press used to be a fresh `claude -p`, which meant "no, the other one" had nothing to
/// refer to. A conversation stays warm for a short window and only while the user is still in the
/// same app — switch to Slack and the thread is about Slack, not whatever was on screen before.
struct Conversation: Equatable {
    struct Exchange: Equatable {
        var question: String
        var answer: String
        var askedAt: Date
        /// Bundle id of the app that was frontmost when it was asked.
        var appBundleID: String?
    }

    /// At most this many earlier turns are carried; beyond that the prompt costs more than it helps.
    static let maximumTurns = 3

    private(set) var turns: [Exchange] = []

    /// True when a new question should be treated as continuing the last one.
    func isWarm(now: Date, window: TimeInterval, frontmostBundleID: String?) -> Bool {
        guard let last = turns.last else { return false }
        guard now.timeIntervalSince(last.askedAt) <= window else { return false }
        // A different app is a different subject.
        guard last.appBundleID == frontmostBundleID else { return false }
        return true
    }

    /// The turns worth sending, oldest first, or nothing when the thread has gone cold.
    func context(now: Date, window: TimeInterval, frontmostBundleID: String?) -> [Exchange] {
        guard isWarm(now: now, window: window, frontmostBundleID: frontmostBundleID) else { return [] }
        return Array(turns.suffix(Conversation.maximumTurns))
    }

    mutating func record(question: String, answer: String, at date: Date, appBundleID: String?) {
        guard !question.isEmpty, !answer.isEmpty else { return }
        turns.append(Exchange(question: question, answer: answer, askedAt: date, appBundleID: appBundleID))
        if turns.count > Conversation.maximumTurns { turns.removeFirst(turns.count - Conversation.maximumTurns) }
    }

    mutating func clear() {
        turns.removeAll()
    }

    /// Renders the carried turns for the prompt. Kept short: the model needs the thread, not a
    /// transcript.
    static func brief(_ turns: [Exchange]) -> String? {
        guard !turns.isEmpty else { return nil }
        let lines = turns.map { "You were asked: \($0.question)\nYou answered: \($0.answer)" }
        return "Earlier in this conversation:\n\n" + lines.joined(separator: "\n\n")
            + "\n\nThe next question continues it. Resolve \"it\", \"that one\" and \"the other\" "
            + "against what is above and what is on screen now."
    }
}
