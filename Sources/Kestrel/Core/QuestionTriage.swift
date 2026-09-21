import Foundation
import os

/// What kind of request this is, decided before any language model is spawned (spec §8.19).
///
/// Four word lists used to make this call — "open …" for a launch, "write"/"reply" for a draft,
/// "what's open" for the desktop survey — and everything else was handed to the model with all
/// six tools attached, whether it needed hands or not. Jev answers the same questions from the
/// sentence itself, in one call, in a few hundred milliseconds. The lists remain as the fallback.
struct QuestionTriage: Equatable {
    enum Kind: String, CaseIterable {
        /// "Open Spotify", "switch to Safari": one verb, no model.
        case openApp = "open_app"
        /// "Reply to this", "close these tabs": needs hands, so the model is offered its tools.
        case act
        /// "What does this button do": eyes only, no tools, shorter prompt.
        case answer
    }

    var kind: Kind
    /// The app named, when it is installed: the whole request when `kind` is `.openApp`, and
    /// the first step of it when `kind` is `.act` and `opensFirst`.
    var app: (bundleID: String, name: String)?
    /// "Open Chrome and search for…": the launch is done here, in a second, and the model gets
    /// the rest with the app already in front — one step and one round-trip fewer.
    var opensFirst = false
    /// The whole request as a step or two on one listed control — "press Send", "search for
    /// owls" — when `kind` is `.act` and Jev is sure of the shape, the control and the words.
    /// Done without a model.
    var macro: Macro?

    enum Macro: Equatable {
        case click(ScreenTarget)
        /// Type into the control, and press return after when `submit`.
        case type(ScreenTarget, String, submit: Bool)

        static let shapes: [String: String] = [
            "click": "A single click on one control — press a button, open a tab, choose a menu item",
            "type_submit": "Type some words into one field and press return — a search, a URL, a message to send",
            "type": "Type some words into one field and leave it there",
            "none": "More than that, or something else entirely",
        ]
    }
    var wantsDraft: Bool
    var needsDesktop: Bool
    /// False drops a warm conversation that this question does not continue.
    var isFollowUp: Bool
    /// Where the decision came from, for the log.
    var source: String

    static func == (lhs: QuestionTriage, rhs: QuestionTriage) -> Bool {
        lhs.kind == rhs.kind && lhs.app?.bundleID == rhs.app?.bundleID && lhs.macro == rhs.macro
            && lhs.opensFirst == rhs.opensFirst
            && lhs.wantsDraft == rhs.wantsDraft && lhs.needsDesktop == rhs.needsDesktop
            && lhs.isFollowUp == rhs.isFollowUp
    }

    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "triage")
    /// Below this, the pick is not trusted over the word lists.
    static let minimumConfidence = 0.6
    /// A macro runs without a model only when Jev is this sure of its shape, and surer still of
    /// the control and the words. A wrong step is one the user has to undo; a missed macro costs a
    /// model round-trip, which is what would have happened anyway. Measured against VS Code and
    /// Chrome: real one-clicks land at 78–86% and 95–99%, "search for cats" at 6% for a click.
    static let shapeCertainty = 0.6
    static let controlCertainty = 0.8
    /// The words, judged on the pick's own probability rather than the calibrated confidence,
    /// which sits low whenever the list is short. Measured: "peregrine falcon" from "google
    /// peregrine falcon" is p=0.71 at 42% confidence. A wrong pick is typed into a field in
    /// plain view, not sent.
    static let textCertainty = 0.55
    /// A choice's escape hatch when no listed app or control is meant.
    static let noApp = "none"

    /// Blocking; call on `work`. Jev when it is on and sure, the lists otherwise.
    /// - Parameter controls: what is clickable on screen, for the one-click shortcut.
    static func decide(_ text: String, frontmostApp: String?, previous: Conversation.Exchange?,
                       controls: [ScreenTarget] = [], config: Config) -> QuestionTriage {
        let fallback = heuristic(text, config: config)
        guard config.jev.isEnabled else { return fallback }
        let apps = AppLauncher.installedNames()
        let clickable = config.agentTools ? controls.filter { $0.kind == .control } : []
        let words = PhraseText.candidates(in: text)
        guard let answers = Jev.ask(state(text, frontmostApp: frontmostApp, previous: previous),
                                    questions(apps: apps, hasHistory: previous != nil, controls: clickable, words: words),
                                    config: config.jev, label: "triage") else { return fallback }
        return parse(answers, fallback: fallback, hasHistory: previous != nil, controls: clickable, words: words) ?? fallback
    }

    /// What Kestrel decided before Jev, exactly.
    static func heuristic(_ text: String, config: Config) -> QuestionTriage {
        let app = AppLauncher.requestedApp(in: text)
        let launch = app != nil && !(config.agentTools && AppLauncher.asksForMore(text))
        return QuestionTriage(kind: launch ? .openApp : .act, app: launch ? app : nil,
                              wantsDraft: AskIntent.wantsDraft(text),
                              needsDesktop: DesktopContextDetector.needsDesktopContext(text),
                              isFollowUp: true, source: "lists")
    }

    // MARK: - The ask

    static func state(_ text: String, frontmostApp: String?, previous: Conversation.Exchange?) -> String {
        var lines = ["The user said: \"\(text)\""]
        if let frontmostApp { lines.append("App in front: \(frontmostApp)") }
        if let previous {
            lines.append("A moment ago they asked: \"\(previous.question)\"")
            lines.append("and were told: \"\(previous.answer.prefix(300))\"")
        }
        return lines.joined(separator: "\n")
    }

    static func questions(apps: [String], hasHistory: Bool,
                          controls: [ScreenTarget] = [], words: [String] = []) -> [String: JevQuestion] {
        var q: [String: JevQuestion] = [
            "kind": .oneOf([
                Kind.openApp.rawValue: "Only open, launch or switch to an application, nothing more",
                Kind.act.rawValue: "Do something on the computer: click, type, send, close, search, change a setting, or open an app and then do something in it",
                Kind.answer.rawValue: "Explain, describe, read, translate, summarise or advise about what is on screen; no action taken",
            ], "What is the user asking for?"),
            "draft": .yesNo("Does the user want text written in their voice to send, post or paste somewhere — a reply, an email, a message, a caption, a rewrite? A summary or explanation for their own reading is not this."),
            "desktop": .yesNo("Is the question about which apps or windows are open on the computer, rather than about the one in front?"),
        ]
        if !apps.isEmpty {
            var options = Dictionary(uniqueKeysWithValues: apps.map { ($0, "The application \($0)") })
            options[noApp] = "No installed application is named or clearly meant"
            q["app"] = .oneOf(options, "Which installed application does the user want opened or switched to, first or at all?")
            q["opens_first"] = .yesNo("Does the request begin by opening, launching or switching to a named application, and then go on to do something in it?")
        }
        if hasHistory {
            q["follow_up"] = .yesNo("Is this a follow-up to the earlier question, referring to it or to its answer?")
        }
        if !controls.isEmpty {
            q["shape"] = .oneOf(Macro.shapes, "Which of these is the whole of what the user wants done, on the screen as it is now?")
            q["more"] = .yesNo("Does the request name a second destination or task beyond the one action — a site, page or app to go to first, or something further to do after? Typing a search and pressing return is one action.")
            var options = Dictionary(controls.map { (String($0.id), "\($0.label) (\(AXElementScanner.friendlyRole($0.role)))") },
                                     uniquingKeysWith: { first, _ in first })
            options[noApp] = "None of these controls is the one meant"
            q["control"] = .oneOf(options, "Which control on screen does the user want clicked, or typed into?")
            if !words.isEmpty {
                var texts = Dictionary(uniqueKeysWithValues: words.enumerated().map { (String($0.offset), "“\($0.element)”") })
                texts[noApp] = "None of these is exactly the text to type"
                q["text"] = .oneOf(texts, "Which is exactly the text the user wants typed — no more, no less?")
            }
        }
        return q
    }

    static func parse(_ answers: JevAnswers, fallback: QuestionTriage, hasHistory: Bool,
                      controls: [ScreenTarget] = [], words: [String] = []) -> QuestionTriage? {
        guard let picked = answers.choice("kind"), let kind = Kind(rawValue: picked.option) else { return nil }
        var triage = fallback
        triage.source = "jev"
        triage.kind = picked.confidence >= minimumConfidence ? kind : fallback.kind
        if let draft = answers.yes("draft") { triage.wantsDraft = draft >= 0.5 }
        if let desktop = answers.yes("desktop") { triage.needsDesktop = desktop >= 0.5 }
        if hasHistory, let follow = answers.yes("follow_up") { triage.isFollowUp = follow >= 0.3 }
        let named: (bundleID: String, name: String)? = {
            guard let app = answers.choice("app"), app.option != noApp, app.confidence >= minimumConfidence
            else { return nil }
            return AppLauncher.installedApp(named: app.option)
        }()
        switch triage.kind {
        case .openApp:
            if let named {
                triage.app = named
            } else if fallback.app == nil {
                // Sure it is a launch, unsure of which app: let the model sort it out.
                triage.kind = .act
            }
        case .act:
            let first = answers.yes("opens_first") ?? 0
            triage.opensFirst = first >= 0.7 && named != nil
            triage.app = triage.opensFirst ? named : nil
        case .answer:
            triage.app = nil
        }
        if let shape = answers.choice("shape"), let pick = answers.choice("control") {
            let text = answers.choice("text").map { "\($0.option) p=\(Int((answers.answers["text"]?.probabilities?[$0.option] ?? 0) * 100))%" } ?? "-"
            let more = Int((answers.yes("more") ?? 0) * 100)
            log.info("shape \(shape.option, privacy: .public) \(Int(shape.confidence * 100))%, control \(pick.option, privacy: .public) \(Int(pick.confidence * 100))%, text \(text, privacy: .public), more \(more)%")
        }
        if triage.kind == .act, let shape = answers.choice("shape"), shape.confidence >= shapeCertainty,
           (answers.yes("more") ?? 0) < 0.5,
           let pick = answers.choice("control"), pick.confidence >= controlCertainty,
           let id = Int(pick.option), let control = controls.first(where: { $0.id == id }) {
            let text = answers.choice("text").flatMap { pick -> Int? in
                let p = answers.answers["text"]?.probabilities?[pick.option] ?? pick.confidence
                return p >= textCertainty ? Int(pick.option) : nil
            }.flatMap { words.indices.contains($0) ? words[$0] : nil }
            switch shape.option {
            case "click": triage.macro = .click(control)
            case "type_submit": triage.macro = text.map { .type(control, $0, submit: true) }
            case "type": triage.macro = text.map { .type(control, $0, submit: false) }
            default: break
            }
        }
        return triage
    }
}
