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

    func decision(for action: Action, bundleID: String?, elementLabel: String?) -> Decision {
        if blockedKinds.contains(action.kind) { return .deny }
        let app = bundleID.flatMap { apps[$0] }
        if app == .deny { return .deny }

        if confirmDestructive {
            let text = [action.describe, elementLabel, action.value].compactMap { $0 }.joined(separator: " ")
            if DestructiveVerbs.isDestructive(text) { return .confirm }
            // A chord's own meaning, which its description usually understates: "Press Return" is
            // how a message gets sent, and ⌘Q closes the app with the draft still in it.
            if action.kind == .key, KeyChord.isIrreversible(action.value) { return .confirm }
        }
        return app ?? fallback
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
