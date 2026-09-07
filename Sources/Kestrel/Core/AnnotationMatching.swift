import Foundation

/// Working out which thing on screen a name refers to.
///
/// Kept apart from the parser because it is the part that decides whether a mark lands on the right
/// thing, and it earned that separation the hard way. The first version took the first target in
/// list order whose label contained the wanted text. The list is offered menu bar first, so that
/// quietly meant "prefer the menu bar": an answer about the pricing table on the page was marked on
/// the Table menu above it, and one about the homepage hero was marked on the Home button, because
/// "home" is a substring of "homepage". Both are the same mistake — a match that is not a match.
extension AnnotationParser {
    /// Case, padding and the trailing ellipsis menu items wear are not part of a name.
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "...", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\"'"))
    }

    /// True when `needle` appears in `haystack` as whole words.
    ///
    /// "home" is a word in "home page" and is not one in "homepage". That distinction is the whole
    /// difference between marking the Home button and marking the section the answer was about.
    static func containsWords(_ haystack: String, _ needle: String) -> Bool {
        let hay = normalize(haystack), pin = normalize(needle)
        guard !pin.isEmpty, !hay.isEmpty else { return false }
        var from = hay.startIndex
        while from < hay.endIndex, let found = hay.range(of: pin, range: from..<hay.endIndex) {
            let openedCleanly = found.lowerBound == hay.startIndex
                || !isWordCharacter(hay[hay.index(before: found.lowerBound)])
            let closedCleanly = found.upperBound == hay.endIndex
                || !isWordCharacter(hay[found.upperBound])
            if openedCleanly, closedCleanly { return true }
            from = hay.index(after: found.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// The target a written name refers to, or nothing.
    ///
    /// Scored, not first-past-the-post: every target that genuinely contains the name is considered
    /// and the *tightest* one wins — the label with the least text around the name. "Sign in" spoken
    /// against a paragraph that happens to mention signing in and a button called Sign in picks the
    /// button, because the button is all name and no padding.
    static func match(_ label: String, in targets: [ScreenTarget]) -> ScreenTarget? {
        let wanted = normalize(label)
        guard wanted.count >= 2 else { return nil }
        if let exact = targets.first(where: { normalize($0.label) == wanted }) { return exact }
        var best: ScreenTarget?
        var bestCost = Int.max
        for target in targets {
            guard let cost = cost(of: wanted, against: target), cost < bestCost else { continue }
            best = target
            bestCost = cost
        }
        return best
    }

    /// How badly a target fits a name. Lower is better; nil means it does not fit at all.
    private static func cost(of wanted: String, against target: ScreenTarget) -> Int? {
        let candidate = normalize(target.label)
        guard candidate.count >= 3 else { return nil }
        // The label carries the name plus some extra: "Export as PDF" for "Export". The extra is
        // the cost, so the shortest label that still contains the name wins.
        if containsWords(candidate, wanted) { return candidate.count - wanted.count }
        // The other way round — the answer wrote "the Save as PDF button" and the control is called
        // "Save as PDF". Legitimate, but always the weaker reading, and never worth doing on a name
        // so short that half the words on screen would qualify.
        if candidate.count >= 4, containsWords(wanted, candidate) {
            return 1_000 + (wanted.count - candidate.count)
        }
        return nil
    }
}
