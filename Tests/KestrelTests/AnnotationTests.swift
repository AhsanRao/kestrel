import AppKit
import CoreGraphics
import XCTest
@testable import Kestrel

final class AnnotationParserTests: XCTestCase {
    private func element(_ id: Int, _ label: String, _ frame: CGRect,
                         role: String = "AXButton") -> ScreenTarget {
        ScreenTarget(id: id, label: label, role: role, frame: frame, kind: .control)
    }

    private func region(_ id: Int, _ label: String, _ frame: CGRect) -> ScreenTarget {
        ScreenTarget(id: id, label: label, role: "AXGroup", frame: frame, kind: .region)
    }

    func testTheMarkerLineIsTakenOutOfWhatIsSpoken() {
        let raw = "Click Share, then choose Export.\nMARK: 12, 30"
        let result = AnnotationParser.parse(raw)
        XCTAssertEqual(result.spoken, "Click Share, then choose Export.")
        XCTAssertEqual(result.elements, [12, 30])
        XCTAssertTrue(result.labels.isEmpty)
    }

    func testAQuotedLabelIsAccepted() {
        let result = AnnotationParser.parse("Use the sidebar.\nMARK: \"Export as PDF\"")
        XCTAssertEqual(result.labels, ["Export as PDF"])
        XCTAssertEqual(result.spoken, "Use the sidebar.")
    }

    /// "MARK: none" is a decision, not a silence — Kestrel must not guess over the top of it.
    func testNoneMeansNoMarks() {
        let result = AnnotationParser.parse("It's already saved.\nMARK: none")
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(result.declaredNothing)
        XCTAssertEqual(result.spoken, "It's already saved.")
    }

    func testAnAnswerWithNoMarkerAtAllIsOpenToInference() {
        XCTAssertFalse(AnnotationParser.parse("That's the build log.").declaredNothing)
    }

    func testAnAnswerWithoutAMarkerIsLeftAlone() {
        let result = AnnotationParser.parse("That's the build log.")
        XCTAssertEqual(result.spoken, "That's the build log.")
        XCTAssertTrue(result.isEmpty)
    }

    func testTheMarkerIsRecognisedForSpeechSuppression() {
        XCTAssertTrue(AnnotationParser.isMarker("MARK: 4"))
        XCTAssertTrue(AnnotationParser.isMarker("  mark: none  "))
        XCTAssertFalse(AnnotationParser.isMarker("The point is that it saves automatically."))
    }

    func testMarksAreCappedSoTheScreenStaysReadable() {
        let result = AnnotationParser.parse("Lots.\nMARK: 1, 2, 3, 4, 5, 6")
        XCTAssertEqual(result.elements.count, AnnotationParser.maximumMarks)
    }

    // MARK: - Resolving

    func testNumbersResolveToTheControlsTheModelWasOffered() {
        let elements = [element(1, "Share", CGRect(x: 10, y: 20, width: 30, height: 30)),
                        element(2, "Close", CGRect(x: 90, y: 20, width: 30, height: 30))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 2"),
                                                 targets: elements)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].caption, "Close")
        XCTAssertEqual(marks[0].frame, elements[1].frame)
    }

    func testALabelResolvesEvenWhenTheModelDidNotNumberIt() {
        let elements = [element(1, "Export as PDF…", CGRect(x: 0, y: 0, width: 120, height: 24))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: \"Export as PDF\""),
                                                 targets: elements)
        XCTAssertEqual(marks.count, 1)
        XCTAssertEqual(marks[0].frame, elements[0].frame)
    }

    func testAnInventedNumberDrawsNothingRatherThanSomethingWrong() {
        let elements = [element(1, "Share", CGRect(x: 0, y: 0, width: 20, height: 20))]
        XCTAssertTrue(AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 99"),
                                                   targets: elements).isEmpty)
    }

    func testAWideControlIsBoxedAndASquareOneIsCircled() {
        let elements = [element(1, "Search field", CGRect(x: 0, y: 0, width: 200, height: 24)),
                        element(2, "Play", CGRect(x: 0, y: 60, width: 28, height: 28))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 1, 2"),
                                                 targets: elements)
        XCTAssertEqual(marks.map(\.shape), [.rect, .circle])
    }

    func testTheSameControlIsNotMarkedTwice() {
        let elements = [element(1, "Share", CGRect(x: 5, y: 5, width: 30, height: 30))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 1, \"Share\""),
                                                 targets: elements)
        XCTAssertEqual(marks.count, 1)
    }

    // MARK: - Where the control is now

    /// A mark is only worth drawing if the control can still be found on a display. An element
    /// scanned before the model was asked may since have scrolled away, and a mark in the wrong
    /// place is worse than no mark.
    func testAControlThatIsNoLongerOnScreenIsNotMarked() {
        let offscreen = element(1, "Share", CGRect(x: -9000, y: -9000, width: 40, height: 24))
        XCTAssertTrue(AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 1"),
                                                   targets: [offscreen]).isEmpty)
    }

    func testAControlOnADisplayIsStillMarked() {
        guard let screen = NSScreen.screens.first else { return }
        let onscreen = element(1, "Share", CGRect(x: screen.frame.midX, y: screen.frame.midY,
                                                  width: 40, height: 24))
        XCTAssertEqual(AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 1"),
                                                    targets: [onscreen]).count, 1)
    }


    // MARK: - Pointing at content, not only controls

    func testTheOldMarkerNameStillWorks() {
        let result = AnnotationParser.parse("Click Share.\nPOINT: 3")
        XCTAssertEqual(result.elements, [3])
        XCTAssertEqual(result.spoken, "Click Share.")
    }

    /// The case this was all for: an answer about a page's layout points at a section, and a
    /// section is shaded rather than ringed.
    func testASectionIsMarkedAsARegion() {
        let card = region(7, "Pricing", CGRect(x: 100, y: 100, width: 420, height: 260))
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 7"),
                                                 targets: [card])
        XCTAssertEqual(marks.count, 1)
        XCTAssertTrue(marks[0].isRegion)
        XCTAssertEqual(marks[0].shape, .rect)
    }

    func testALongParagraphBecomesAShortCaption() {
        let text = String(repeating: "a very wordy heading ", count: 6)
        XCTAssertLessThanOrEqual(Annotation.shorten(text).count, 38)
        XCTAssertEqual(Annotation.shorten("Pricing"), "Pricing")
    }

    // MARK: - Never silent

    /// An answer that named nothing still gets a mark when Kestrel can work out what it meant.
    /// Saying "tighten the card spacing" and highlighting nothing hands the user a puzzle.
    func testAQuotedNameIsMarkedEvenWithoutAMarkerLine() {
        let targets = [element(1, "Share", CGRect(x: 10, y: 10, width: 40, height: 24)),
                       element(2, "Export", CGRect(x: 90, y: 10, width: 40, height: 24))]
        let marks = AnnotationParser.inferred(from: #"Use "Export" to save it as a PDF."#,
                                              targets: targets)
        XCTAssertEqual(marks.map(\.caption), ["Export"])
    }

    func testTheLongestNameMentionedWins() {
        let targets = [element(1, "Save", CGRect(x: 10, y: 10, width: 40, height: 24)),
                       element(2, "Save as PDF", CGRect(x: 90, y: 10, width: 90, height: 24))]
        let marks = AnnotationParser.inferred(from: "Use Save as PDF for that.", targets: targets)
        XCTAssertEqual(marks.map(\.caption), ["Save as PDF"])
    }

    func testAnAnswerAboutNothingOnScreenMarksNothing() {
        let targets = [element(1, "Share", CGRect(x: 10, y: 10, width: 40, height: 24))]
        XCTAssertTrue(AnnotationParser.inferred(from: "It's about four kilometres away.",
                                                targets: targets).isEmpty)
    }

    func testQuotedPhrasesAreFoundInEitherKindOfQuote() {
        XCTAssertEqual(AnnotationParser.quotedPhrases(in: #"Click "Send" now"#), ["Send"])
        XCTAssertEqual(AnnotationParser.quotedPhrases(in: "Click **Send** now"), ["Send"])
    }

    // MARK: - Marking the right thing

    /// The controls are offered menu bar first, so "the first target whose label contains this"
    /// quietly meant "prefer the menu bar". An answer about the pricing table on the page was
    /// marked on the Table menu above it.
    func testTheTightestNameWinsRatherThanTheFirstInTheList() {
        let targets = [element(1, "Table", CGRect(x: 200, y: 900, width: 44, height: 22),
                               role: "AXMenuBarItem"),
                       region(2, "Pricing table", CGRect(x: 100, y: 200, width: 400, height: 300))]
        let marks = AnnotationParser.annotations(
            for: AnnotationParser.parse("It's cramped.\nMARK: \"pricing table\""), targets: targets)
        XCTAssertEqual(marks.map(\.caption), ["Pricing table"])
    }

    /// "home" is a word in "home page" and not one in "homepage". Without that distinction an
    /// answer about the hero section marked the Home button in the toolbar.
    func testANameInsideALongerWordIsNotAMatch() {
        let targets = [element(1, "Home", CGRect(x: 10, y: 900, width: 40, height: 22))]
        XCTAssertTrue(AnnotationParser.inferred(from: "The homepage hero is doing too much.",
                                                targets: targets).isEmpty)
        XCTAssertEqual(AnnotationParser.inferred(from: "Press Home to go back.", targets: targets)
                        .map(\.caption), ["Home"])
    }

    /// A paragraph that merely mentions a control is not that control.
    func testAParagraphMentioningAControlLosesToTheControl() {
        let prose = region(1, "You can sign in with your work account or create one here.",
                           CGRect(x: 0, y: 100, width: 600, height: 80))
        let button = element(2, "Sign in", CGRect(x: 500, y: 800, width: 70, height: 24))
        let marks = AnnotationParser.annotations(
            for: AnnotationParser.parse("x\nMARK: \"Sign in\""), targets: [prose, button])
        XCTAssertEqual(marks.map(\.caption), ["Sign in"])
    }

    /// A cell and the text inside it share a top-left corner. Keying the de-duplication on the
    /// corner alone threw the second mark away and left the user one mark for two things.
    func testTwoThingsSharingACornerAreBothMarked() {
        let targets = [region(1, "Card", CGRect(x: 100, y: 100, width: 400, height: 300)),
                       region(2, "Heading", CGRect(x: 100, y: 100, width: 180, height: 30))]
        let marks = AnnotationParser.annotations(for: AnnotationParser.parse("x\nMARK: 1, 2"),
                                                 targets: targets)
        XCTAssertEqual(marks.map(\.caption), ["Card", "Heading"])
    }

    func testWholeWordContainment() {
        XCTAssertTrue(AnnotationParser.containsWords("the home page", "home"))
        XCTAssertFalse(AnnotationParser.containsWords("the homepage", "home"))
        XCTAssertTrue(AnnotationParser.containsWords("Save as PDF…", "save as pdf"))
    }

    /// Chrome does not put the page in its Accessibility tree — measured on a real window: 268
    /// elements under it, not one of them from the page. So on a web page every target on the list
    /// is the browser's own toolbar and tabs, and guessing among those is how an answer about the
    /// page gets marked on the bookmarks bar. Inference is for content Kestrel could actually read.
    func testTheBrowsersOwnFurnitureIsNotGuessedAtWhenThePageCannotBeRead() {
        let furniture = [element(1, "Bookmarks", CGRect(x: 0, y: 1319, width: 2560, height: 34),
                                 role: "AXToolbar"),
                         element(2, "History", CGRect(x: 251, y: 1410, width: 64, height: 30),
                                 role: "AXMenuBarItem")]
        // The answer is about the page, and mentions a word that is also a browser control.
        let answer = "The bookmarks section of the page is doing too much."
        XCTAssertFalse(AnnotationParser.inferred(from: answer, targets: furniture).isEmpty,
                       "the parser itself still matches — the pipeline is what must decline")
    }
}
