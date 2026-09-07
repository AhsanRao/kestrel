import Foundation

/// A piece of writing the user asked for, pulled out of a spoken answer.
///
/// "Write me a reply to this" is a different kind of question from "what is this button". The reply
/// is not something to say out loud and it is not something to point at — it is something to *use*,
/// and the only thing the user wants to do with it is put it somewhere else. So it is kept out of
/// the spoken answer entirely, shown as text, and given a button that copies it.
struct Draft: Equatable {
    /// A subject line, when the draft is an email and one makes sense.
    var subject: String?
    /// The draft itself, ready to paste. Never spoken.
    var body: String

    /// What goes on the clipboard: the subject is part of the email, so it travels with it.
    var forClipboard: String {
        guard let subject, !subject.isEmpty else { return body }
        return "Subject: \(subject)\n\n\(body)"
    }
}

enum DraftParser {
    static let marker = "DRAFT:"
    private static let fence = "---"

    struct Result: Equatable {
        /// The answer with the draft taken out — the one line that is spoken.
        var spoken: String
        var draft: Draft?
    }

    /// Splits a spoken line from the draft beneath it.
    ///
    /// The shape is a `DRAFT:` line carrying an optional subject, then the body between two `---`
    /// fences. A model that half-remembers the convention and writes the marker without fences
    /// still gets its draft recognised: everything after the marker becomes the body, because
    /// losing a paragraph the user asked for is far worse than showing one with a ragged edge.
    static func parse(_ raw: String) -> Result {
        let lines = raw.components(separatedBy: .newlines)
        guard let markerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix(marker)
        }) else { return Result(spoken: raw, draft: nil) }

        let spoken = lines[..<markerIndex].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = String(lines[markerIndex].trimmingCharacters(in: .whitespaces)
            .dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)

        let after = Array(lines[(markerIndex + 1)...])
        let body = between(fences: after).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return Result(spoken: raw, draft: nil) }
        return Result(spoken: spoken,
                      draft: Draft(subject: subject.isEmpty ? nil : subject, body: body))
    }

    /// The text between the first pair of `---` fences, or everything there is if they are missing.
    private static func between(fences lines: [String]) -> String {
        let isFence = { (line: String) in line.trimmingCharacters(in: .whitespaces) == fence }
        guard let opening = lines.firstIndex(where: isFence) else {
            return lines.joined(separator: "\n")
        }
        let rest = lines[(opening + 1)...]
        guard let closing = rest.firstIndex(where: isFence) else {
            return rest.joined(separator: "\n")
        }
        return rest[..<closing].joined(separator: "\n")
    }

    /// A reply the model wrote into its own sentence instead of into a draft block.
    ///
    /// Asked "what should I reply to this", a model that has not taken the `DRAFT:` convention to
    /// heart answers: `Say "chal phir so ja, baat kal krty" — matches his sleepy vibe.` The words
    /// in quotes *are* the message; everything around them is commentary about it. Spoken, that is
    /// a fine answer. On screen it is the one thing this feature exists to prevent — a reply the
    /// user can read and cannot copy, which leaves them retyping it into the app it came from.
    ///
    /// So when the question asked for something to send and the answer put something in quotes,
    /// the quoted part is lifted out and given the copy button it should have had. The spoken line
    /// is left as it was: it has already been said by the time this runs, and rewriting what the
    /// user just heard would be worse than repeating it.
    static func suggestion(forQuestion question: String, in answer: String) -> Draft? {
        guard asksForSomethingToSend(question), let phrase = quoted(in: answer) else { return nil }
        return Draft(subject: nil, body: phrase)
    }

    /// Questions whose answer is words the user is going to send somewhere.
    static func asksForSomethingToSend(_ question: String) -> Bool {
        let text = question.lowercased()
        let patterns = [
            "what (should|do|can|would) i (reply|say|send|write|respond|answer)",
            "how (should|do|would) i (reply|respond|answer|word)",
            "(reply|respond|answer) to (this|that|him|her|them|it)",
            "(write|draft|give) (me )?(a |an |some )?(reply|response|message|answer|text)",
            "help me (reply|respond|answer|word)",
            "(a|any) good (reply|response|answer)",
        ]
        return patterns.contains { text.range(of: $0, options: [.regularExpression]) != nil }
    }

    /// The longest quoted run in an answer, when it is long enough to be a message rather than the
    /// name of something. Straight and curly quotes both: a model uses whichever it feels like.
    static func quoted(in answer: String) -> String? {
        var best: String?
        let straight = "\"([^\"]{4,400})\""
        let curly = "\u{201C}([^\u{201D}]{4,400})\u{201D}"
        for pattern in [straight, curly] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(answer.startIndex..., in: answer)
            for match in regex.matches(in: answer, range: range) {
                guard match.numberOfRanges > 1, let found = Range(match.range(at: 1), in: answer)
                else { continue }
                let phrase = String(answer[found]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Two words at least: one quoted word is a term being named, not a message being
                // suggested.
                guard phrase.split(separator: " ").count >= 2 else { continue }
                if phrase.count > (best?.count ?? 0) { best = phrase }
            }
        }
        return best
    }

    /// True for a streamed line that belongs to a draft, so it is never read out loud.
    ///
    /// Speech streams sentence by sentence as the answer arrives, which means the decision about
    /// whether to speak a line has to be made before the whole answer exists. Once the marker has
    /// gone past, nothing after it is spoken.
    static func isDraftBoundary(_ sentence: String) -> Bool {
        let head = sentence.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return head.hasPrefix(marker)
    }
}
