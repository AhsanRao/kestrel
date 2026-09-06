import Foundation

/// One thing Kestrel can do to the Mac on the user's behalf.
///
/// Deliberately small. Everything here is expressible through Accessibility, which means it can be
/// delivered to the target app in the background — without moving the real cursor or stealing
/// focus — and which is the property that makes acting tolerable to sit next to.
struct Action: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case press          // click a button, menu item, checkbox
        case rightClick     // open a control's context menu
        case setValue       // type into a field, replacing what is there
        case typeText       // type into what has focus, keeping what is there
        case key            // a keystroke or chord: "return", "cmd+s", "cmd+shift+p"
        case focus          // bring a control's window forward and select it
        case scroll
        case launchApp
    }

    var kind: Kind
    /// Index into the element list the model was given. Absent for `launchApp` and `key`, and
    /// optional for `typeText`, which otherwise types into whatever already has focus.
    var element: Int?
    /// Text for `setValue` and `typeText`, a chord for `key`, a bundle id for `launchApp`,
    /// a direction ("up", "down", "page up", "page down") for `scroll`.
    var value: String?
    /// What the user will be told is about to happen.
    var describe: String

    init(kind: Kind, element: Int? = nil, value: String? = nil, describe: String) {
        self.kind = kind
        self.element = element
        self.value = value
        self.describe = describe
    }
}

/// A model-proposed sequence, with the goal it is meant to achieve.
struct ActionPlan: Codable, Equatable {
    var goal: String
    var actions: [Action]
    var needs_more: Bool?

    /// At most this many steps run without the user asking again.
    static let maximumActions = 12

    init(goal: String, actions: [Action], needs_more: Bool? = nil) {
        self.goal = goal
        self.actions = actions
        self.needs_more = needs_more
    }
}

/// Words that mean an action cannot be quietly undone. Anything matching is confirmed with the
/// user first, whatever the policy says about the app.
enum DestructiveVerbs {
    static let words = [
        "send", "delete", "remove", "discard", "trash", "erase", "wipe", "clear",
        "buy", "purchase", "pay", "checkout", "order", "subscribe", "transfer",
        "post", "publish", "tweet", "submit", "reply", "share", "invite",
        "archive", "overwrite", "replace", "merge", "deploy", "release",
        "sign out", "log out", "quit", "shut down", "restart", "format", "reset",
        "confirm", "accept", "approve", "decline", "cancel subscription", "unsubscribe",
    ]

    /// True when the description, or the control's own label, reads as irreversible.
    ///
    /// Matched on whole words and their ordinary inflections, never on substrings: "Deleting the
    /// row" must count and "the sender column" must not.
    static func isDestructive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = words.filter { $0.contains(" ") }
        if phrases.contains(where: lowered.contains) { return true }

        let tokens = Set(lowered.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return words.filter { !$0.contains(" ") }.contains { verb in
            !tokens.isDisjoint(with: inflections(of: verb))
        }
    }

    /// "delete" also appears as deletes, deleted, deleting — but never as "deleteed".
    static func inflections(of verb: String) -> Set<String> {
        var forms: Set<String> = [verb, verb + "s"]
        let stem = verb.hasSuffix("e") ? String(verb.dropLast()) : verb
        forms.insert(stem + "ed")
        forms.insert(stem + "ing")
        forms.insert(verb + "ed")
        forms.insert(verb + "ing")
        return forms
    }
}
