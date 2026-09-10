import Foundation

/// The half-second of "yes, I heard you" that goes out while the model is still thinking.
///
/// Written here rather than asked of the model: a first line that costs a round trip is not an
/// acknowledgement, it is the start of the answer arriving late. These are short on purpose —
/// long enough to land, short enough that the real answer is next.
enum Acknowledgement {
    /// Only said if the answer has not started within this. A fast reply needs no filler, and two
    /// voices stacking up is worse than a moment of quiet.
    static let delay: TimeInterval = 0.45

    private static var last: String?

    /// Keyed off what was actually asked, so it sounds like it was listening rather than like a
    /// spinner with a voice.
    static func line(for question: String) -> String {
        let text = question.lowercased()
        let pool: [String]
        switch true {
        case text.contains("write"), text.contains("draft"), text.contains("reply"),
             text.contains("respond"), text.contains("what should i say"),
             text.contains("what do i say"):
            pool = ["Right, let me write that.", "On it — drafting now.", "Give me a second."]
        case text.contains("wrong"), text.contains("error"), text.contains("broken"),
             text.contains("failing"), text.contains("why is"), text.contains("not working"):
            pool = ["Let's see what's up.", "Hmm, let me look.", "Right, checking."]
        case text.contains("how do i"), text.contains("how can i"), text.contains("where is"),
             text.contains("where do i"):
            pool = ["One sec, I'll find it.", "Let me check.", "Looking now."]
        case text.contains("this") || text.contains("here") || text.contains("screen"):
            pool = ["Let me have a look.", "Right, one moment.", "Taking a look."]
        default:
            pool = ["On it.", "Got it — one sec.", "Sure, one moment."]
        }
        // Never the same line twice running: the repeat is what makes a canned phrase sound canned.
        let choice = pool.filter { $0 != last }.randomElement() ?? pool[0]
        last = choice
        return choice
    }
}
