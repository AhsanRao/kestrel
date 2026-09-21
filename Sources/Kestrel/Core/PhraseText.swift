import Foundation

/// The words a request wants typed — "search for barn owls in Chrome" → "barn owls".
///
/// Jev can pick from a list but cannot write one out, so the candidates are cut here from the
/// sentence and Jev picks the exact one. Deliberately generous: a wrong candidate is one Jev
/// will not choose; a missing one costs a model round-trip.
enum PhraseText {
    /// Verbs that introduce the text, longest first so "search for" wins over "search".
    private static let leads = [
        "search for", "look up", "google", "type in", "type", "enter", "write", "search",
        "find", "put in", "say", "send", "fill in", "paste",
    ]
    /// Where the text stops: a trailing "in Chrome", "into the search bar", "and press enter".
    private static let tails = [
        " in the ", " in ", " into the ", " into ", " on the ", " on ", " and press ", " and hit ",
        " then press ", " then hit ", " and submit", " and search", " and go",
    ]

    static func candidates(in phrase: String) -> [String] {
        let lowered = phrase.lowercased()
        var found: [String] = []
        for lead in leads {
            guard let range = lowered.range(of: "\\b\(lead)\\b ", options: .regularExpression) else { continue }
            let rest = String(phrase[range.upperBound...])
            // Both the whole tail and the tail cut at "in Chrome": "the weather in Lahore" is
            // the text, "barn owls in Chrome" is not, and Jev can tell which.
            var versions = [rest]
            let cut = rest.lowercased()
            if let end = tails.compactMap({ cut.range(of: $0)?.lowerBound }).min() {
                versions.append(String(rest[..<rest.index(rest.startIndex, offsetBy: cut.distance(from: cut.startIndex, to: end))]))
            }
            for version in versions {
                let text = version.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\"'“”"))
                if !text.isEmpty, !found.contains(text) { found.append(text) }
            }
        }
        return found
    }
}
