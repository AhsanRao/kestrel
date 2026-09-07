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

    /// A named section is kept however big it is — a name is the model's evidence that it is a
    /// thing rather than scaffolding.
    func testANamedSectionSurvivesEvenWhenItIsHuge() {
        let page = candidate("", CGRect(x: 0, y: 0, width: 1400, height: 900), role: "AXWebArea")
        let named = candidate("Pricing", CGRect(x: 0, y: 0, width: 1390, height: 890))
        XCTAssertTrue(AXContentReader.rank([page, named]).contains { $0.label == "Pricing" })
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
