import Foundation

/// What runs, what is checked with the user first, and what is refused outright.
///
/// The model is trusted to *try* things; it is not trusted to decide what is irreversible. Anything
/// that reads as deleting, sending or paying is spoken back to the user before it happens, and
/// nothing is ever run with elevated privileges — there is no confirmation for that, only a no.
struct ActionPolicy: Equatable {
    enum Verdict: Equatable {
        case allow
        case confirm(String)    // what the user is asked to approve
        case deny(String)       // what they are told instead
    }

    /// Words and phrases that make an action worth a second look. Whole words with their ordinary
    /// inflections, so "deleting the row" counts and "the sender column" does not; phrases match
    /// anywhere.
    var sensitivePatterns: [String]
    /// Executables `run_shell` may start. Each pipeline segment is checked against it.
    var shellAllowlist: [String]

    static let defaultSensitivePatterns = [
        "send", "delete", "remove", "discard", "trash", "erase", "wipe", "clear", "empty trash",
        "buy", "purchase", "pay", "checkout", "order", "subscribe", "transfer",
        "post", "publish", "tweet", "submit", "reply", "share", "invite",
        "archive", "overwrite", "replace", "merge", "deploy", "release",
        "sign out", "log out", "quit", "shut down", "restart", "reboot", "format", "reset",
        "unsubscribe", "cancel subscription", "unsend",
        "rm", "rmdir", "mv", "kill", "killall", "diskutil", "git push", "git reset", "drop table",
    ]

    static let defaultShellAllowlist = [
        "ls", "cat", "head", "tail", "grep", "find", "wc", "date", "pwd", "echo", "which", "file",
        "open", "mdfind", "mdls", "pbcopy", "pbpaste", "sw_vers", "uptime", "df", "du", "ps",
        "sort", "uniq", "cut", "tr", "basename", "dirname", "stat",
    ]

    /// Ways an allowlisted command can be made to run something else.
    static let escapeHatches = ["-exec", "-execdir", "-delete", "-ok", "-okdir"]

    /// Never allowed, whatever the allowlist says.
    static let elevation = ["sudo", "su", "doas"]

    static let `default` = ActionPolicy(sensitivePatterns: defaultSensitivePatterns,
                                        shellAllowlist: defaultShellAllowlist)

    /// - Parameter target: what the action lands on — the label of the control under a click, or
    ///   the app the keystrokes go to — when known.
    func verdict(for call: ToolCall, frontmostBundleID: String? = nil, target: String? = nil) -> Verdict {
        let terminal = frontmostBundleID.map(TextInjector.terminalBundleIDs.contains) ?? false
        switch call.tool {
        case .openApp:
            return .allow

        case .runShell:
            let command = call.string("command") ?? ""
            if let reason = ActionPolicy.shellRefusal(command, allowlist: shellAllowlist) { return .deny(reason) }
            return isSensitive(command) ? .confirm(call.describe) : .allow

        case .runAppleScript:
            let script = (call.string("script") ?? "").lowercased()
            if script.contains("with administrator privileges") {
                return .deny("I never run anything with administrator privileges")
            }
            if script.contains("do shell script") || isSensitive(script) { return .confirm(call.describe) }
            return .allow

        case .click:
            guard let target, isSensitive(target) else { return .allow }
            return .confirm("click “\(target)”")

        case .typeText:
            let text = call.string("text") ?? ""
            if terminal { return .confirm("type \(ToolCall.excerpt(text)) into the terminal") }
            return isSensitive(text) ? .confirm(call.describe) : .allow

        case .pressKey:
            // The key names themselves ("delete", "return") are not intent; only where they land is.
            return terminal ? .confirm("\(call.describe) in the terminal") : .allow
        }
    }

    func isSensitive(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let phrases = sensitivePatterns.filter { $0.contains(" ") }.map { $0.lowercased() }
        if phrases.contains(where: lowered.contains) { return true }
        let tokens = Set(lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return sensitivePatterns.filter { !$0.contains(" ") }.contains { word in
            !tokens.isDisjoint(with: ActionPolicy.inflections(of: word.lowercased()))
        }
    }

    /// "delete" also appears as deletes, deleted, deleting — but never as "deleteed".
    static func inflections(of verb: String) -> Set<String> {
        var forms: Set<String> = [verb, verb + "s"]
        let stem = verb.hasSuffix("e") ? String(verb.dropLast()) : verb
        for suffix in ["ed", "ing"] { forms.insert(stem + suffix); forms.insert(verb + suffix) }
        return forms
    }

    /// Why a shell command may not run, or nil when it may.
    ///
    /// The allowlist is checked per pipeline segment, because `ls; rm -rf ~` starts with `ls`.
    /// Substitution and redirection are refused outright: `$(…)` hides a command from the check,
    /// and `>` turns a read-only command into a write.
    static func shellRefusal(_ command: String, allowlist: [String]) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "there was no command to run" }
        for forbidden in ["$(", "`", ">", "<"] where trimmed.contains(forbidden) {
            return "I don't run commands with \(forbidden == "`" ? "backticks" : forbidden) in them"
        }
        if trimmed.lowercased().contains("with administrator privileges") {
            return "I never run anything with elevated privileges"
        }
        for hatch in escapeHatches where trimmed.split(separator: " ").contains(Substring(hatch)) {
            return "I don't run commands with \(hatch) in them"
        }
        let segments = trimmed.replacingOccurrences(of: "&&", with: ";")
            .replacingOccurrences(of: "||", with: ";")
            .replacingOccurrences(of: "|", with: ";")
            .split(whereSeparator: { $0 == ";" || $0 == "\n" })
        for segment in segments {
            let words = segment.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            // `FOO=bar cmd` — skip the assignments to find the command.
            guard let executable = words.first(where: { !$0.contains("=") })?
                .split(separator: "/").last.map(String.init) else { return "there was no command to run" }
            if elevation.contains(executable) { return "I never run anything with elevated privileges" }
            guard allowlist.contains(executable) else {
                return "`\(executable)` isn't on the shell allowlist (shellAllowlist in ~/.kestrel/config.json)"
            }
        }
        return nil
    }
}
