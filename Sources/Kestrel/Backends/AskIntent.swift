import Foundation

/// What kind of question this is, so the prompt can carry only the rules that apply to it.
///
/// The framing used to be one 90-line block sent for every question, a quarter of it about writing
/// drafts. Every token of that is read before the first word of the answer, on a question that is
/// usually "what does this button do".
enum AskIntent {
    /// Words the user is going to put somewhere else. Deliberately generous: a missed draft is
    /// worse than a few hundred extra tokens on a question that turned out not to need them.
    static func wantsDraft(_ question: String) -> Bool {
        let text = question.lowercased()
        if phrases.contains(where: text.contains) { return true }
        return verbs.contains { text.range(of: "\\b\($0)\\b", options: .regularExpression) != nil }
    }

    private static let verbs = [
        "write", "draft", "reply", "replying", "respond", "response", "compose", "reword",
        "rephrase", "rewrite", "email", "dm", "caption", "summarise", "summarize",
    ]

    private static let phrases = [
        "what should i say", "what do i say", "what should i write", "how should i respond",
        "how do i reply", "give me something to send", "something to send", "message back",
        "say back", "answer this", "answer that", "put together",
    ]
}
