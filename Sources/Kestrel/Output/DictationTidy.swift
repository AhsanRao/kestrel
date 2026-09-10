import Foundation

/// Punctuation, capitals and spoken commands, fixed here rather than by a model.
///
/// Cleanup used to be a whole `claude -p` round trip on every dictation — a process launch plus a
/// model call to put a full stop on "send it over when you get a chance". These rules run in
/// microseconds and cover the common case; anything long enough for the model to earn its keep
/// still goes to it.
enum DictationTidy {
    /// Above this many words the model is worth waiting for: long dictation is where real
    /// speech-to-text errors and run-on sentences appear, and the user has just spent twenty
    /// seconds talking, so a moment more is not what they notice.
    static let wordsWorthAModel = 18

    static func needsModel(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).count > wordsWorthAModel
    }

    static func clean(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }
        result = spokenPunctuation(in: result)
        result = withoutFillers(result)
        result = collapsingSpaces(result)
        result = capitalisingSentences(result)
        return terminated(result)
    }

    /// "comma", "full stop", "new line" — said out loud, meant as punctuation.
    private static let spoken: [(String, String)] = [
        ("(?i)\\s+comma\\b", ","),
        ("(?i)\\s+(full stop|period)\\b", "."),
        ("(?i)\\s+question mark\\b", "?"),
        ("(?i)\\s+exclamation (mark|point)\\b", "!"),
        ("(?i)\\s+colon\\b", ":"),
        ("(?i)\\s+semicolon\\b", ";"),
        ("(?i)\\s*\\b(new line|newline)\\b\\s*", "\n"),
        ("(?i)\\s*\\b(new paragraph)\\b\\s*", "\n\n"),
    ]

    private static func spokenPunctuation(in text: String) -> String {
        spoken.reduce(text) { partial, rule in
            partial.replacingOccurrences(of: rule.0, with: rule.1, options: .regularExpression)
        }
    }

    /// Only the ones that are never content. "Like" and "you know" are left alone — they carry
    /// meaning often enough that cutting them would change what the user said.
    private static let fillers = "(?i)\\b(um+|uh+|er+|erm+|hmm+)\\b[,]?\\s*"

    private static func withoutFillers(_ text: String) -> String {
        text.replacingOccurrences(of: fillers, with: "", options: .regularExpression)
    }

    private static func collapsingSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// The first letter, and every one after a sentence ends.
    private static func capitalisingSentences(_ text: String) -> String {
        var result = ""
        var startOfSentence = true
        for character in text {
            if startOfSentence, character.isLetter {
                result.append(Character(character.uppercased()))
                startOfSentence = false
            } else {
                result.append(character)
                if ".!?\n".contains(character) { startOfSentence = true }
            }
        }
        return result
    }

    /// A dictated line that ends mid-air reads as truncated wherever it lands.
    private static func terminated(_ text: String) -> String {
        guard let last = text.last, !".!?,:;-–—\"')]}".contains(last) else { return text }
        return text + "."
    }
}
