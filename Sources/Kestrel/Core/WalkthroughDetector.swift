import Foundation

/// Decides whether a spoken question wants to be *shown* rather than answered.
///
/// Kestrel has no second hotkey for this: "how do I export as PDF?" should draw on the screen,
/// "what is this window?" should not. The test is deliberately conservative — a false negative
/// costs the user a normal answer, a false positive costs them an overlay they have to dismiss.
enum WalkthroughDetector {
    private static let openers = [
        "how do i", "how do you", "how can i", "how would i", "how to",
        "show me how", "show me where", "walk me through", "guide me",
        "where do i", "where can i", "where is the", "teach me how",
    ]

    /// Phrases that look like an opener but are asking about state, not about a route.
    private static let exclusions = [
        "how do i look", "how do you feel", "how do i sound",
    ]

    static func wantsWalkthrough(_ text: String, config: Config) -> Bool {
        guard config.walkthroughs else { return false }
        let normalized = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
        guard !exclusions.contains(where: normalized.contains) else { return false }
        return openers.contains { normalized.hasPrefix($0) || normalized.contains(" \($0)") }
    }
}
