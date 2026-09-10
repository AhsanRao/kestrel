import AppKit
import XCTest
@testable import Kestrel

/// The island stops long text at a line count and has to say so. Whether it says so correctly is
/// entirely a question of whether these counts match what SwiftUI drew.
final class TextFitTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 13)

    private func lines(_ text: String, width: CGFloat = 400) -> Int {
        TextFit.lineCount(text, font: font, lineSpacing: 2.5, width: width)
    }

    func testNothingToLayOutIsNoLines() {
        XCTAssertEqual(lines(""), 0)
        XCTAssertEqual(lines("a word", width: 0), 0)
    }

    func testAShortStringIsOneLine() {
        XCTAssertEqual(lines("Short."), 1)
    }

    func testTextWrapsAtTheWidthItIsGiven() {
        let sentence = String(repeating: "wrapping text ", count: 20)
        XCTAssertGreaterThan(lines(sentence, width: 200), lines(sentence, width: 600))
    }

    /// A draft is mostly hard line breaks, and they have to count as lines or an email would look
    /// like it fits when it does not.
    func testHardBreaksAreLines() {
        XCTAssertEqual(lines("one\ntwo\nthree"), 3)
    }

    func testOverflowIsZeroWhenItAllFits() {
        XCTAssertEqual(
            TextFit.overflow("Short.", font: font, lineSpacing: 2.5, width: 400, limit: 14), 0)
    }

    func testOverflowCountsOnlyWhatDidNotFit() {
        let text = (1...20).map { "Line \($0)" }.joined(separator: "\n")
        XCTAssertEqual(
            TextFit.overflow(text, font: font, lineSpacing: 2.5, width: 400, limit: 14), 6)
    }

    /// The measurement has to follow the font it is given, or a monospaced draft is counted with
    /// the proportional metrics of an answer.
    ///
    /// The width is picked deliberately: two fonts that wrap differently still tie at plenty of
    /// widths, and at 300 these two both land on 8 lines, which says nothing either way. At 340
    /// the same string is 6 proportional lines and 8 monospaced ones.
    func testItMeasuresWithTheFontItIsGiven() {
        let text = String(repeating: "measured ", count: 30)
        let proportional = TextFit.lineCount(text, font: font, lineSpacing: 3, width: 340)
        let monospaced = TextFit.lineCount(
            text, font: .monospacedSystemFont(ofSize: 13, weight: .regular),
            lineSpacing: 3, width: 340)
        XCTAssertNotEqual(proportional, monospaced)
    }
}
