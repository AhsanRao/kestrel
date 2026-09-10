import Foundation

/// Everything read off the screen for one question: the controls, the content regions, and the
/// text. Taken as a unit, on a background queue, while the transcript and the screenshot are still
/// being produced — all three depend on the same moment and on nothing from each other.
struct ScreenSnapshot {
    var elements: [AXElementScanner.Element]
    var targets: [ScreenTarget]
    var text: String
    var url: String?
    var document: String?
    var bundleID: String?

    /// True when nothing but the app's own chrome came back — the browser case, where the page is
    /// absent from the Accessibility tree and marking anything would mark the toolbar.
    var readContent: Bool { !text.isEmpty }

    static func read(bundleID: String?) -> ScreenSnapshot {
        let elements = AXElementScanner.scanFrontmostApp()
        var targets = Array(elements.prefix(SessionCoordinator.maximumPointableControls))
            .map(\.asTarget)
        let screen = AXContentReader.read(startingAt: targets.count + 1)
        targets += screen.regions
        return ScreenSnapshot(elements: elements, targets: targets,
                              text: ScreenSnapshot.trimmed(screen.text),
                              url: screen.url, document: screen.document, bundleID: bundleID)
    }

    /// The prompt pays for every character of this, and a dense page can run to tens of thousands.
    /// Reading order puts the top of the screen first, which is also what the question is usually
    /// about, so the cut is from the end.
    static let maximumTextCharacters = 6_000

    static func trimmed(_ text: String) -> String {
        guard text.count > maximumTextCharacters else { return text }
        let cut = text.prefix(maximumTextCharacters)
        // On a line boundary, so the model is not handed half a sentence.
        let end = cut.lastIndex(of: "\n").map { cut[..<$0] } ?? cut
        return String(end) + "\n…(more further down the page)"
    }
}
