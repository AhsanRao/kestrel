import AppKit
import ApplicationServices

/// Runs the actuator against a real application, once, on demand.
///
/// Unit tests cover the policy, the parsing and the sequencing, but nothing they can do proves that
/// a keystroke actually reaches another app's document while the user stays where they are. That
/// property is the whole design, so it gets checked against TextEdit rather than asserted.
///
/// Gated on `KESTREL_PROBE_ACTIONS`, and it must run from the app bundle — Accessibility is granted
/// to Kestrel, not to whatever shell launched it:
///
///     open -n Kestrel.app --env KESTREL_PROBE_ACTIONS=1 --stdout /tmp/probe.txt
enum ActionProbe {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PROBE_ACTIONS"] != nil
    }

    static let scratch = Paths.tmp.appendingPathComponent("action-probe.txt")

    static func run() {
        DispatchQueue.global(qos: .userInitiated).async {
            report(steps())
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func steps() -> [String] {
        var out: [String] = ["trusted: \(AXIsProcessTrusted())"]
        guard AXIsProcessTrusted() else {
            // Ad-hoc signing means every rebuild is a new binary as far as TCC is concerned, so the
            // grant has to be given again. Put the system prompt on screen rather than just saying so.
            TextInjector.requestAccessibilityPermission()
            return out + ["grant Kestrel Accessibility in System Settings, then run this again"]
        }

        try? FileManager.default.createDirectory(at: Paths.tmp, withIntermediateDirectories: true)
        try? "".write(to: scratch, atomically: true, encoding: .utf8)
        NSWorkspace.shared.open(scratch)
        Thread.sleep(forTimeInterval: 2.5)

        guard let textEdit = app("com.apple.TextEdit") else { return out + ["TextEdit did not open"] }

        // Move the user somewhere else first. If background delivery works, the typing still lands
        // in TextEdit and this app stays in front.
        app("com.apple.finder")?.activate()
        Thread.sleep(forTimeInterval: 1.0)
        let before = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        out.append("frontmost before: \(before)")

        let marker = "kestrel probe \(Int(Date().timeIntervalSince1970))"
        let plan = ActionPlan(goal: "probe", actions: [
            Action(kind: .typeText, value: marker, describe: "Type the marker"),
            Action(kind: .key, value: "cmd+s", describe: "Save the file"),
        ])
        let policy = ActionPolicy(fallback: .allow, apps: [:], blockedKinds: [], confirmDestructive: false)
        let runner = ActionRunner(performer: Actuator()) { action, _ in
            out.append("unexpectedly asked about: \(action.describe)")
            return false
        }
        let result = runner.run(plan, elements: [], policy: policy, bundleID: "com.apple.TextEdit",
                                appPID: textEdit.processIdentifier)
        for step in result.steps { out.append("\(step.action.kind.rawValue): \(step.outcome)") }
        Thread.sleep(forTimeInterval: 1.5)

        out.append("frontmost after: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        let saved = (try? String(contentsOf: scratch, encoding: .utf8)) ?? ""
        out.append("file contains marker: \(saved.contains(marker)) — \(saved.trimmingCharacters(in: .whitespacesAndNewlines))")
        return out
    }

    private static func app(_ bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }

    private static func report(_ lines: [String]) {
        for line in lines { print("probe: \(line)") }
        fflush(stdout)
    }
}
