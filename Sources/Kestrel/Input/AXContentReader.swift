import AppKit
import ApplicationServices
import os

/// Reads what is *on* the screen, rather than what can be clicked on it.
///
/// The Accessibility tree of a browser or a document app carries the content as well as the
/// controls: headings, paragraphs, cards, images, table rows, each with the rectangle it occupies.
/// That is what lets Kestrel answer "how could this page look better" and point at the thing it
/// means, instead of describing a location in words.
///
/// Only what is visible is read. Content below the fold has frames that are off-screen or clipped,
/// and a mark cannot be drawn on something the user cannot see — so the answer is about the screen
/// in front of them, and says so.
enum AXContentReader {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "content")

    /// Structure worth pointing at.
    static let regionRoles: Set<String> = [
        "AXHeading", "AXWebArea", "AXGroup", "AXList", "AXTable", "AXOutline", "AXRow", "AXCell",
        "AXImage", "AXStaticText", "AXTextArea", "AXScrollArea", "AXTabGroup", "AXToolbar",
        "AXLink", "AXArticle", "AXLandmarkMain", "AXSection",
    ]

    /// Regions smaller than this are punctuation, not sections.
    static let minimumSize = CGSize(width: 44, height: 18)
    static let maximumRegions = 90
    static let maximumDepth = 18
    /// Text handed to the model, in characters. Enough for a page of prose, short of a novel.
    static let maximumText = 3500

    struct Screen {
        var regions: [ScreenTarget]
        /// What the screen says, in reading order.
        var text: String
        /// The page's address, when the front window is showing one.
        var url: String?
        /// The open document's path, when there is one.
        var document: String?
    }

    /// Everything readable about the frontmost app's front window.
    static func read(startingAt firstID: Int = 1) -> Screen {
        guard AXElementScanner.isAvailable,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return Screen(regions: [], text: "", url: nil, document: nil)
        }
        let application = AXUIElementCreateApplication(pid)
        // A browser that has not been asked returns its own toolbar and none of the page.
        AXElementScanner.enableWebContent(for: application)
        guard let window = AXElementScanner.child(of: application,
                                                  attribute: kAXFocusedWindowAttribute as CFString)
                ?? AXElementScanner.children(of: application,
                                             attribute: kAXWindowsAttribute as CFString).first else {
            return Screen(regions: [], text: "", url: nil, document: nil)
        }

        var found: [Candidate] = []
        var seen = Set<String>()
        walk(window, depth: maximumDepth, into: &found, seen: &seen)

        let ordered = rank(found)
        var regions: [ScreenTarget] = []
        for (offset, candidate) in ordered.enumerated() {
            regions.append(ScreenTarget(id: firstID + offset, label: candidate.label,
                                        role: candidate.role, frame: candidate.frame,
                                        kind: .region, ref: candidate.ref))
        }
        let place = location(url: AXElementScanner.string(window, "AXURL")
                                ?? found.compactMap { $0.url }.first,
                             document: AXElementScanner.string(window, kAXDocumentAttribute))
        let screen = Screen(regions: regions, text: readingOrderText(found),
                            url: place.url, document: place.document)
        log.debug("read \(regions.count) regions, \(screen.text.count) characters")
        return screen
    }

    /// Splits what the window reports into the page it is showing and the document it has open.
    ///
    /// Chrome sets no `AXURL` on its window and puts the page address on `AXDocument` instead, so
    /// the model was told "the open document is dashboard" — the last path component of a URL —
    /// rather than where the user actually was. A document that is a web address is a page.
    static func location(url: String?, document: String?) -> (url: String?, document: String?) {
        let isPage = document?.hasPrefix("http") == true
        return (url ?? (isPage ? document : nil), isPage ? nil : document)
    }

    // MARK: - Walking

    struct Candidate {
        var label: String
        var role: String
        var frame: CGRect
        var ref: AXUIElement?
        var url: String?
        var depth: Int
    }

    private static func walk(_ element: AXUIElement, depth: Int,
                             into found: inout [Candidate], seen: inout Set<String>) {
        guard depth > 0, found.count < maximumRegions * 4 else { return }
        if let candidate = describe(element, depth: maximumDepth - depth) {
            let key = "\(candidate.role)|\(candidate.label.prefix(40))|"
                + "\(Int(candidate.frame.minX)),\(Int(candidate.frame.minY))"
            if seen.insert(key).inserted { found.append(candidate) }
        }
        for child in AXElementScanner.children(of: element, attribute: kAXChildrenAttribute as CFString) {
            walk(child, depth: depth - 1, into: &found, seen: &seen)
        }
    }

    private static func describe(_ element: AXUIElement, depth: Int) -> Candidate? {
        guard let role = AXElementScanner.string(element, kAXRoleAttribute),
              regionRoles.contains(role) else { return nil }
        guard let frame = AXElementScanner.frame(of: element),
              frame.width >= minimumSize.width, frame.height >= minimumSize.height,
              AXElementScanner.isOnScreen(frame) else { return nil }

        let label = [AXElementScanner.string(element, kAXValueAttribute),
                     AXElementScanner.string(element, kAXTitleAttribute),
                     AXElementScanner.string(element, kAXDescriptionAttribute)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        return Candidate(label: String(label.prefix(120)), role: role, frame: frame, ref: element,
                         url: AXElementScanner.string(element, "AXURL"), depth: depth)
    }

    /// Which regions are worth offering, and in what order.
    ///
    /// Reading order, not tree order: the model is looking at a picture of this, and a list that
    /// jumps around the screen is a list it will mis-read. Unlabelled containers are kept — a card
    /// with no accessible name is still a card, and "tighten this" has to be able to point at it.
    static func rank(_ candidates: [Candidate]) -> [Candidate] {
        // The page itself is not a section of the page. A browser nests the web area, the body, the
        // main and the section as four unnamed rectangles of almost exactly the same size, and
        // offering four numbers for one block is how a mark ends up on the wrong one — or shaded
        // over most of the screen, which reads as a bug rather than as pointing.
        let largest = candidates.map { $0.frame.width * $0.frame.height }.max() ?? 0
        let ordered = candidates
            .filter { candidate in
                let area = candidate.frame.width * candidate.frame.height
                guard candidate.label.isEmpty else { return true }
                return area > 12000 && area < largest * 0.8
            }
            .sorted { first, second in
                // Top of the screen first; AppKit measures up, so that is descending y.
                if abs(first.frame.maxY - second.frame.maxY) > 12 {
                    return first.frame.maxY > second.frame.maxY
                }
                return first.frame.minX < second.frame.minX
            }

        // What is left still repeats: a group wrapping a single card is that card. An unnamed
        // rectangle within a few points of one already kept is the same thing seen again.
        var kept: [Candidate] = []
        for candidate in ordered where kept.count < maximumRegions {
            if candidate.label.isEmpty,
               kept.contains(where: { isEffectivelyTheSame($0.frame, candidate.frame) }) { continue }
            kept.append(candidate)
        }
        return kept
    }

    /// Two rectangles a user could not tell apart, and so could not choose between.
    static func isEffectivelyTheSame(_ first: CGRect, _ second: CGRect, tolerance: CGFloat = 8) -> Bool {
        abs(first.minX - second.minX) <= tolerance && abs(first.minY - second.minY) <= tolerance
            && abs(first.maxX - second.maxX) <= tolerance && abs(first.maxY - second.maxY) <= tolerance
    }

    /// The words on screen, in the order a person would read them.
    private static func readingOrderText(_ candidates: [Candidate]) -> String {
        let lines = candidates
            .filter { $0.role == "AXStaticText" || $0.role == "AXHeading" || $0.role == "AXTextArea" }
            .sorted { first, second in
                if abs(first.frame.maxY - second.frame.maxY) > 8 {
                    return first.frame.maxY > second.frame.maxY
                }
                return first.frame.minX < second.frame.minX
            }
            .map(\.label)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var text = ""
        for line in lines where seen.insert(line).inserted {
            if text.count + line.count > maximumText { break }
            text += line + "\n"
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
