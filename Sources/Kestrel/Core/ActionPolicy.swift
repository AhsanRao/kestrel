import Foundation

/// What Kestrel is allowed to do, and where. Deny by default.
///
/// HeyClicky runs its computer-use driver with `approval_policy = "never"` and
/// `sandbox_mode = "danger-full-access"`, holding the line in a separate rego policy instead.
/// Kestrel takes the opposite default: nothing is permitted until the user says so, and anything
/// irreversible is confirmed even in an app they have allowed.
struct ActionPolicy: Codable, Equatable {
    enum Decision: String, Codable, Equatable {
        case allow      // do it
        case confirm    // ask first
        case deny       // refuse
    }

    /// Applied when no rule matches. `confirm` is the shipped default: useful, but never silent.
    var fallback: Decision
    /// Per-app rules, keyed by bundle id.
    var apps: [String: Decision]
    /// Kinds of action that are never performed, whatever the app.
    var blockedKinds: [Action.Kind]
    /// Confirm anything whose description reads as irreversible, even in an allowed app.
    var confirmDestructive: Bool

    static let `default` = ActionPolicy(
        fallback: .confirm,
        apps: Dictionary(uniqueKeysWithValues: TextInjector.terminalBundleIDs.map { ($0, Decision.deny) }),
        blockedKinds: [],
        confirmDestructive: true
    )

    /// Terminals are denied out of the box: typing into one is arbitrary command execution, and
    /// no amount of confirmation text makes that a good default.
    static var defaultJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(ActionPolicy.default)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// A decision plus *why*, because the two reasons to confirm are not interchangeable: an app
    /// the user has not vouched for yet is a question they can answer once, and a step that sends
    /// or deletes something is a question that must be asked every single time.
    struct Ruling: Equatable {
        var decision: Decision
        var isDestructive: Bool
    }

    func decision(for action: Action, bundleID: String?, elementLabel: String?) -> Decision {
        ruling(for: action, bundleID: bundleID, elementLabel: elementLabel).decision
    }

    func ruling(for action: Action, bundleID: String?, elementLabel: String?) -> Ruling {
        if blockedKinds.contains(action.kind) { return Ruling(decision: .deny, isDestructive: false) }
        let app = bundleID.flatMap { apps[$0] }
        if app == .deny { return Ruling(decision: .deny, isDestructive: false) }

        if confirmDestructive {
            let text = [action.describe, elementLabel, action.value].compactMap { $0 }.joined(separator: " ")
            // A chord's own meaning, which its description usually understates: "Press Return" is
            // how a message gets sent, and ⌘Q closes the app with the draft still in it.
            if DestructiveVerbs.isDestructive(text)
                || (action.kind == .key && KeyChord.isIrreversible(action.value)) {
                return Ruling(decision: .confirm, isDestructive: true)
            }
        }
        return Ruling(decision: app ?? fallback, isDestructive: false)
    }

    /// Records that the user has vouched for an app, so Kestrel stops asking about every step in it.
    /// Never widens anything else: a denied app stays denied, and destructive steps still confirm.
    static func allow(app bundleID: String) {
        var policy = load()
        guard policy.apps[bundleID] != .deny else { return }
        policy.apps[bundleID] = .allow
        policy.save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Paths.policy, options: .atomic)
    }

    // MARK: - Disk

    static func load() -> ActionPolicy {
        guard let data = try? Data(contentsOf: Paths.policy),
              let policy = try? JSONDecoder().decode(ActionPolicy.self, from: data)
        else { return .default }
        return policy
    }

    /// Writes the shipped policy if the user has none. Never overwrites theirs.
    static func bootstrap() {
        guard !FileManager.default.fileExists(atPath: Paths.policy.path) else { return }
        try? defaultJSON.write(to: Paths.policy, atomically: true, encoding: .utf8)
    }

    // MARK: - Tolerant decoding

    init(fallback: Decision, apps: [String: Decision], blockedKinds: [Action.Kind], confirmDestructive: Bool) {
        self.fallback = fallback
        self.apps = apps
        self.blockedKinds = blockedKinds
        self.confirmDestructive = confirmDestructive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallbackDefault = ActionPolicy.default
        fallback = ((try? container.decodeIfPresent(Decision.self, forKey: .fallback)) ?? nil) ?? fallbackDefault.fallback
        apps = ((try? container.decodeIfPresent([String: Decision].self, forKey: .apps)) ?? nil) ?? [:]
        blockedKinds = ((try? container.decodeIfPresent([Action.Kind].self, forKey: .blockedKinds)) ?? nil) ?? []
        confirmDestructive = ((try? container.decodeIfPresent(Bool.self, forKey: .confirmDestructive)) ?? nil) ?? true
    }
}
