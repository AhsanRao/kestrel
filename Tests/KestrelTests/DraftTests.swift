import XCTest
@testable import Kestrel

/// "Write me a reply to this" is a different kind of question. The reply is not something to say
/// out loud and not something to point at — it is something to take away, so it has to come out of
/// the spoken answer cleanly and arrive somewhere it can be copied.
final class DraftParserTests: XCTestCase {
    func testTheDraftIsSplitFromTheSpokenLine() {
        let raw = """
        Here's a reply that stays warm but says no.
        DRAFT: Re: Thursday's workshop
        ---
        Hi Sam,

        Thanks for thinking of me — I can't make Thursday.

        Ahsan
        ---
        """
        let result = DraftParser.parse(raw)
        XCTAssertEqual(result.spoken, "Here's a reply that stays warm but says no.")
        XCTAssertEqual(result.draft?.subject, "Re: Thursday's workshop")
        XCTAssertTrue(result.draft?.body.hasPrefix("Hi Sam,") == true)
        XCTAssertTrue(result.draft?.body.hasSuffix("Ahsan") == true)
    }

    /// The subject belongs to the email, so it travels with it onto the clipboard.
    func testTheSubjectIsCopiedWithTheBody() {
        let draft = Draft(subject: "Re: Invoice", body: "Paid this morning.")
        XCTAssertEqual(draft.forClipboard, "Subject: Re: Invoice\n\nPaid this morning.")
        XCTAssertEqual(Draft(subject: nil, body: "Just this.").forClipboard, "Just this.")
    }

    func testAMessageWithNoSubjectIsStillADraft() {
        let result = DraftParser.parse("Here you go.\nDRAFT:\n---\nOn my way, ten minutes.\n---")
        XCTAssertNil(result.draft?.subject)
        XCTAssertEqual(result.draft?.body, "On my way, ten minutes.")
    }

    /// A model that half-remembers the convention still gets its draft shown: losing a paragraph
    /// the user asked for is far worse than showing one with a ragged edge.
    func testAMissingFenceDoesNotThrowTheDraftAway() {
        let result = DraftParser.parse("Here's one.\nDRAFT: Hello\nThe body, unfenced.")
        XCTAssertEqual(result.draft?.body, "The body, unfenced.")
        XCTAssertEqual(result.spoken, "Here's one.")
    }

    func testAnOrdinaryAnswerIsUntouched() {
        let result = DraftParser.parse("That's the build log.")
        XCTAssertNil(result.draft)
        XCTAssertEqual(result.spoken, "That's the build log.")
    }

    /// An empty draft is not a draft; the answer is left exactly as it was.
    func testAnEmptyDraftIsIgnored() {
        XCTAssertNil(DraftParser.parse("Nothing to write.\nDRAFT:\n---\n---").draft)
    }

    /// Speech streams sentence by sentence, so the decision not to read the email out has to be
    /// made the moment the marker goes past.
    func testTheDraftMarkerStopsSpeech() {
        XCTAssertTrue(DraftParser.isDraftBoundary("DRAFT: Re: Thursday"))
        XCTAssertTrue(DraftParser.isDraftBoundary("  draft:  "))
        XCTAssertFalse(DraftParser.isDraftBoundary("I drafted a reply for you."))
    }
}
