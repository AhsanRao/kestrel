import Foundation
import os

/// Two judgements the word lists used to make, put to Jev instead (spec §8.19): is this action
/// worth checking with the user first, and did the user just say yes.
///
/// The lists stay underneath. Jev is asked, and only a clear answer either way is taken; anything
/// in between goes back to the list, so a shaky call can never open a gate the list would have
/// closed. Rules that are not judgements — elevation, the shell allowlist, anything typed into a
/// terminal — never come here at all.
enum ActionJudge {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "judge")

    /// At or above this, an action is checked with the user; at or below `harmless`, it is not;
    /// between, the word list decides.
    static let sensitive = 0.6
    static let harmless = 0.25
    /// A yes has to be clearer than a no: the cost of a misheard no is an email that went.
    static let agreed = 0.75
    static let refused = 0.35

    // MARK: - Is this worth asking about?

    /// Blocking. Nil when Jev is off, failed, or unsure.
    static func isSensitive(_ action: String, in app: String?, config: Config) -> Bool? {
        guard config.jev.isEnabled else { return nil }
        let answers = Jev.ask(sensitivityState(action, in: app), ["risky": sensitivityQuestion],
                              config: config.jev, label: "judge")
        guard let p = answers?.yes("risky") else { return nil }
        log.info("risky \(Int(p * 100))%: \(action.prefix(80), privacy: .public)")
        return sensitivity(p)
    }

    static func sensitivity(_ p: Double) -> Bool? {
        if p >= sensitive { return true }
        if p <= harmless { return false }
        return nil
    }

    static func sensitivityState(_ action: String, in app: String?) -> String {
        var lines = ["An assistant on the user's Mac is about to: \(action)"]
        if let app { lines.append("The app in front is \(app).") }
        return lines.joined(separator: "\n")
    }

    static let sensitivityQuestion: JevQuestion = .yesNo(
        "Would this be hard to undo, or be seen by someone else? It sends, posts, replies, shares, deletes, discards, pays, orders, overwrites, signs out, quits with unsaved work, or changes something outside this Mac. Navigating, opening, selecting, reading, searching, switching tabs and closing a dialog are not this.")

    // MARK: - Was that a yes?

    /// Blocking. Nil when Jev is off, failed, or unsure — and then the word list decides, which
    /// treats anything not clearly a yes as a no.
    static func isYes(_ transcript: String, to what: String, config: Config) -> Bool? {
        guard config.jev.isEnabled, !transcript.isEmpty else { return nil }
        let answers = Jev.ask(consentState(transcript, to: what), ["yes": consentQuestion],
                              config: config.jev, label: "consent")
        guard let p = answers?.yes("yes") else { return nil }
        log.info("agreed \(Int(p * 100))%: \(transcript.prefix(80), privacy: .public)")
        return consent(p)
    }

    static func consent(_ p: Double) -> Bool? {
        if p >= agreed { return true }
        if p <= refused { return false }
        return nil
    }

    static func consentState(_ transcript: String, to what: String) -> String {
        "The assistant asked: \"\(Confirmation.prompt(for: what))\"\nThe user replied: \"\(transcript)\""
    }

    // MARK: - Is it done?

    /// Only this sure is worth telling the model, which is looking at a screenshot this judge
    /// cannot see.
    static let done = 0.85

    /// A screenshot is a thousand-odd tokens a step. When the list of controls says enough — the
    /// next step is "click Send", not "is the page loaded" — Jev has to be this sure to drop it.
    static let wordsSuffice = 0.8

    struct Progress: Equatable {
        var done = false
        var picture = true
        /// How sure Jev is the job is done, for a macro to decide whether to hand over.
        var doneProbability = 0.0
    }

    /// Blocking. Whether the request looks carried out from what the screen says after a step,
    /// and whether the model needs the picture to choose the next one. Nil when Jev is off or
    /// failed: then nothing is claimed and the picture goes.
    static func review(_ progress: String, config: Config) -> Progress? {
        guard config.jev.isEnabled else { return nil }
        let answers = Jev.ask(progress, ["done": doneQuestion, "words": pictureQuestion],
                              config: config.jev, label: "done")
        guard let p = answers?.yes("done") else { return nil }
        let words = answers?.yes("words") ?? 0
        log.info("done \(Int(p * 100))%, words suffice \(Int(words * 100))%")
        return Progress(done: p >= done, picture: words < wordsSuffice, doneProbability: p)
    }

    static let pictureQuestion: JevQuestion = .yesNo(
        "Could the next step be chosen from the list of controls and the text alone, without looking at a picture of the screen? No if a page might still be loading, a result has to be read off the screen, or something may have gone wrong.")

    static let doneQuestion: JevQuestion = .yesNo(
        "Has everything the user asked for now been carried out, judging by the steps taken and what is on screen? Partly done, or done except for a confirmation still showing, is not this.")

    static let consentQuestion: JevQuestion = .yesNo(
        "Is the user telling the assistant to go ahead with exactly that? A yes with a change, a condition, a question back, or a no of any kind is not a go-ahead.")
}
