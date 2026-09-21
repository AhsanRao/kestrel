import AppKit
import ApplicationServices
import Foundation

/// A macro (spec §8.19): "press Send", "search for owls" — a request Jev is sure is one or two
/// steps on one listed control, done in a couple of seconds with no model.
///
/// The steps run through the same `ActionSession` as a model's — the policy, the spoken
/// confirmation, the action log, the trail on the island — because the user is owed the same
/// protection whichever decided. What is skipped is only the reasoning, and the screenshot after
/// every step but the last.
extension SessionCoordinator {
    /// Where a search or a URL typed into the address bar goes: a new tab, never over the page
    /// the user has open. ⌘T in each of these leaves the new tab's address bar focused.
    static let browsers: Set<String> = [
        "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// The steps the macro is made of, in order.
    static func steps(for macro: QuestionTriage.Macro, in bundleID: String? = nil) -> [ToolCall] {
        switch macro {
        case .click(let control):
            return [ToolCall(tool: .click, arguments: ["control": control.id])]
        case .type(let control, let text, true) where bundleID.map(browsers.contains) == true
            && control.role == kAXTextFieldRole as String:
            return [ToolCall(tool: .pressKey, arguments: ["key": "t", "modifiers": ["cmd"]]),
                    ToolCall(tool: .typeText, arguments: ["text": text]),
                    ToolCall(tool: .pressKey, arguments: ["key": "return"])]
        case .type(let control, let text, let submit):
            var calls = [ToolCall(tool: .click, arguments: ["control": control.id])]
            // A single-line field — an address bar, a search box — is replaced, not appended to;
            // anything bigger keeps what it has.
            if control.role == kAXTextFieldRole as String {
                calls.append(ToolCall(tool: .pressKey, arguments: ["key": "a", "modifiers": ["cmd"]]))
            }
            calls.append(ToolCall(tool: .typeText, arguments: ["text": text]))
            if submit { calls.append(ToolCall(tool: .pressKey, arguments: ["key": "return"])) }
            return calls
        }
    }

    /// Blocking; call on `work`. Nil when it all went through; otherwise what went wrong, for
    /// the model to pick up from — the session, and its steps so far, stay live.
    func run(_ macro: QuestionTriage.Macro, in session: ActionSession) -> String? {
        let calls = SessionCoordinator.steps(for: macro, in: TextInjector.frontmostBundleID())
        for (index, call) in calls.enumerated() {
            let result = session.handle(call, observe: index == calls.count - 1)
            if result.isError { return result.text }
        }
        // The steps ran; the review of the screen after the last one says whether they were the
        // job. "Go to Wikipedia and search" typed into Google is three steps that did not.
        if let review = session.lastReview, review.doneProbability <= 0.3,
           let again = session.lookAgain(after: 2), again.doneProbability <= 0.3 {
            return "the screen does not show the request done"
        }
        return nil
    }

    /// What the user hears once a macro is done.
    static func describe(_ macro: QuestionTriage.Macro, in bundleID: String? = nil) -> String {
        switch macro {
        case .click(let control): return "Clicked \(spoken(control.label))."
        case .type(_, let text, true) where steps(for: macro, in: bundleID).first?.tool == .pressKey:
            return "Searched for “\(text)” in a new tab."
        case .type(let control, let text, let submit):
            return "Typed “\(text)” into \(spoken(control.label))\(submit ? " and pressed return" : "")."
        }
    }

    /// "Explorer (⇧⌘E)" is said as "Explorer".
    static func spoken(_ label: String) -> String {
        label.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
    }
}
