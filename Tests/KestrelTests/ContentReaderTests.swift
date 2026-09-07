import CoreGraphics
import XCTest
@testable import Kestrel

/// What the model is offered to point at. A browser's Accessibility tree is mostly scaffolding —
/// the same rectangle wrapped four times with no name on any of it — and every one of those is a
/// number the model can pick, so the list has to be pruned before it is offered rather than after
/// a mark has landed somewhere strange.
final class ContentReaderRankingTests: XCTestCase {
    private func candidate(_ label: String, _ frame: CGRect,
                           role: String = "AXGroup") -> AXContentReader.Candidate {
        AXContentReader.Candidate(label: label, role: role, frame: frame, ref: nil, url: nil, depth: 0)
    }

    /// The page is not a section of the page: shading nearly the whole window reads as a bug.
    func testTheWholePageIsNotOfferedAsASection() {
        let page = candidate("", CGRect(x: 0, y: 0, width: 1400, height: 900), role: "AXWebArea")
        let card = candidate("", CGRect(x: 100, y: 500, width: 400, height: 260))
        let ranked = AXContentReader.rank([page, card])
        XCTAssertEqual(ranked.map(\.frame), [card.frame])
    }

    /// A name does not make something a section. Measured on a real dashboard, the window group and
    /// the web area inside it were the same rectangle, both carrying the page title, and marking
    /// either one shaded the whole screen.
    func testAnythingFillingTheWindowIsNotASection() {
        let window = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let windowGroup = candidate("Dashboard — Chrome", window)
        let webArea = candidate("Dashboard", window.insetBy(dx: 0, dy: 40), role: "AXWebArea")
        let card = candidate("Quick Actions", CGRect(x: 100, y: 500, width: 400, height: 260))
        XCTAssertEqual(AXContentReader.rank([windowGroup, webArea, card], within: window)
                        .map(\.label), ["Quick Actions"])
    }

    /// A named section well inside the window is exactly what the list is for.
    func testANamedSectionInsideTheWindowIsKept() {
        let window = CGRect(x: 0, y: 0, width: 1400, height: 900)
        let sidebar = candidate("Navigation", CGRect(x: 0, y: 100, width: 240, height: 700))
        XCTAssertEqual(AXContentReader.rank([sidebar], within: window).map(\.label), ["Navigation"])
    }

    /// The web area, the body, the main and the section are one block seen four times.
    func testNestedUnnamedContainersCollapseToOne() {
        let outer = candidate("", CGRect(x: 100, y: 400, width: 600, height: 300))
        let inner = candidate("", CGRect(x: 103, y: 402, width: 596, height: 297), role: "AXSection")
        let bigger = candidate("", CGRect(x: 0, y: 0, width: 1400, height: 900), role: "AXWebArea")
        XCTAssertEqual(AXContentReader.rank([bigger, outer, inner]).count, 1)
    }

    /// Reading order, so the numbered list runs down the screen the way the picture does.
    func testRegionsComeBackInReadingOrder() {
        let top = candidate("Header", CGRect(x: 0, y: 800, width: 400, height: 60))
        let leftRow = candidate("Left", CGRect(x: 0, y: 400, width: 200, height: 60))
        let rightRow = candidate("Right", CGRect(x: 300, y: 400, width: 200, height: 60))
        XCTAssertEqual(AXContentReader.rank([rightRow, leftRow, top]).map(\.label),
                       ["Header", "Left", "Right"])
    }

    func testRectanglesAUserCouldNotTellApart() {
        let base = CGRect(x: 10, y: 10, width: 200, height: 100)
        XCTAssertTrue(AXContentReader.isEffectivelyTheSame(base, base.insetBy(dx: 3, dy: 3)))
        XCTAssertFalse(AXContentReader.isEffectivelyTheSame(base, base.insetBy(dx: 30, dy: 30)))
    }

    /// Chrome sets no AXURL and puts the page address on AXDocument, which reached the model as
    /// "the open document is dashboard" — the last path component of a URL.
    func testAWebAddressReportedAsADocumentIsAPage() {
        let place = AXContentReader.location(url: nil, document: "https://portal.example.om/dashboard")
        XCTAssertEqual(place.url, "https://portal.example.om/dashboard")
        XCTAssertNil(place.document)
    }

    func testARealDocumentStaysADocument() {
        let place = AXContentReader.location(url: nil, document: "file:///Users/x/Report.pages")
        XCTAssertNil(place.url)
        XCTAssertEqual(place.document, "file:///Users/x/Report.pages")
    }

    /// An explicit AXURL is the better source and is never overruled.
    func testAnExplicitAddressWins() {
        let place = AXContentReader.location(url: "https://a.example", document: "https://b.example")
        XCTAssertEqual(place.url, "https://a.example")
    }
}
