import Foundation

/// What a spoken yes or no sounds like once transcribed.
///
/// A tap on the hotkey with nothing said is a yes — that is the gesture the confirmation asks for.
/// A hold with words in it is read here, and anything that is not clearly a yes is a no: the cost
/// of a misheard "no" is an email that went, and the cost of a misheard "yes" is being asked again.
enum Confirmation {
    static let yes = ["yes", "yeah", "yep", "yup", "sure", "ok", "okay", "go ahead", "do it",
                      "go on", "confirm", "confirmed", "please do", "fine", "absolutely", "correct"]
    static let no = ["no", "nope", "don't", "dont", "do not", "stop", "cancel", "never mind",
                     "nevermind", "leave it", "wait", "hold on", "not that", "abort", "skip"]

    static func isYes(_ transcript: String) -> Bool {
        let lowered = transcript.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        // A hold with nothing said is a tap that lasted longer.
        guard !lowered.isEmpty else { return true }
        let words = lowered.split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        if no.contains(where: { padded.contains(" \($0) ") }) { return false }
        return yes.contains(where: { padded.contains(" \($0) ") })
    }

    /// What Kestrel says before it waits.
    static func prompt(for what: String) -> String {
        "About to \(what). Tap the hotkey to go ahead, or hold it and say no."
    }
}
