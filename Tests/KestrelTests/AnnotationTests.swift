import AppKit
import CoreGraphics
import XCTest
@testable import Kestrel

final class AnnotationParserTests: XCTestCase {
    private func element(_ id: Int, _ label: String, _ frame: CGRect,
                         role: String = "AXButton") -> AXElementScanner.Element {
        AXElementScanner.Element(id: id, label: label, role: role, frame: frame)
    }

    func testTheMarkerLineIsTakenOutOfWhatIsSpoken() {
        let raw = "Click Share, then choose Export.\nPOINT: 12, 30"
        let result = AnnotationParser.parse(raw)
        XCTAssertEqual(result.spoken, "Click Share, then choose Export.")
        XCTAssertEqual(result.elements, [12, 30])
        XCTAssertTrue(result.labels.isEmpty)
    }

    func testAQuotedLabelIsAccepted() {
        let result = AnnotationParser.parse("Use the sidebar.\nPOINT: \"Export as PDF\"")
        XCTAssertEqual(result.labels, ["Export as PDF"])
        XCTAssertEqual(result.spoken, "Use the sidebar.")
    }

    func testNoneMeansNoMarks() {
        let result = AnnotationParser.parse("It's already saved.\nPOINT: none")
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.spoken, "It's already saved.")
    }

    func testAnAnswerWithoutAMarkerIsLeftAlone() {
        let result = AnnotationParser.parse("That's the build log.")
        XCTAssertEqual(result.spoken, "That's the build log.")
        XCTAssertTrue(result.isEmpty)
    }

    func testTheMarkerIsRecognisedForSpeechSuppression() {
        XCTAssertTrue(AnnotationParser.isMarker("POINT: 4"))
        XCTAssertTrue(AnnotationParser.isMarker("  point: none  "))
        XCTAssertFalse(AnnotationParser.isMarker("The point is that it saves automatically."))
    }

    func testMarksAreCappedSoTheScreenStaysReadable() {
        let result = AnnotationParser.parse("Lots.\nPOINT: 1, 2, 3, 4, 5, 6")
        XCTAssertEqual(result.elements.count, AnnotationParser.maximumMarks)
    }

    // MARK: - Resolving

    func testNumbersResolveToTheControlsTheModelWasOffered() {
        let elements = [element(1, "Share", CGRect(x: 10, y: 20, width: 30, height: 30)),
                        element(2, "Close", CGRect(x: 90, y: 20, width: 30, height: 30))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 2"),
                                                 elements: elements)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].caption, "Close")
        XCTAssertEqual(marks[0].frame, elements[1].frame)
    }

    func testALabelResolvesEvenWhenTheModelDidNotNumberIt() {
        let elements = [element(1, "Export as PDF…", CGRect(x: 0, y: 0, width: 120, height: 24))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: \"Export as PDF\""),
                                                 elements: elements)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].frame, elements[0].frame)
    }

    func testAnInventedNumberDrawsNothingRatherThanSomethingWrong() {
        let elements = [element(1, "Share", CGRect(x: 0, y: 0, width: 20, height: 20))]
        XCTAssertTrue(AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 99"),
                                                   elements: elements).isEmpty)
    }

    func testAWideControlIsBoxedAndASquareOneIsCircled() {
        let elements = [element(1, "Search field", CGRect(x: 0, y: 0, width: 200, height: 24)),
                        element(2, "Play", CGRect(x: 0, y: 60, width: 28, height: 28))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 1, 2"),
                                                 elements: elements)
        XCTAssertEqual(marks.map(\.shape), [.rect, .circle])
    }

    func testTheSameControlIsNotMarkedTwice() {
        let elements = [element(1, "Share", CGRect(x: 5, y: 5, width: 30, height: 30))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 1, \"Share\""),
                                                 elements: elements)
        XCTAssertEqual(marks.count, 1)
    }

    // MARK: - Where the control is now

    /// A mark is only worth drawing if the control can still be found on a display. An element
    /// scanned before the model was asked may since have scrolled away, and a mark in the wrong
    /// place is worse than no mark.
    func testAControlThatIsNoLongerOnScreenIsNotMarked() {
        let offscreen = element(1, "Share", CGRect(x: -9000, y: -9000, width: 40, height: 24))
        XCTAssertTrue(AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 1"),
                                                   elements: [offscreen]).isEmpty)
    }

    func testAControlOnADisplayIsStillMarked() {
        guard let screen = NSScreen.screens.first else { return }
        let onscreen = element(1, "Share", CGRect(x: screen.frame.midX, y: screen.frame.midY,
                                                  width: 40, height: 24))
        XCTAssertEqual(AnnotationParser.annotations(for: AnnotationParser.parse("x\nPOINT: 1"),
                                                    elements: [onscreen]).count, 1)
    }

}