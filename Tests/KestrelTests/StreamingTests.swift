import XCTest
@testable import Kestrel

/// Streaming is what makes Kestrel answer while the model is still writing, so the parser is held
/// to the exact event shapes `claude -p --output-format stream-json` emits.
final class StreamParserTests: XCTestCase {
    private let deltaLine = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}}"#

    func testTextDeltasAccumulate() {
        var parser = StreamParser()
        XCTAssertEqual(parser.consume(deltaLine), "Hello")
        XCTAssertEqual(parser.consume(deltaLine.replacingOccurrences(of: "Hello", with: " there")), " there")
        XCTAssertEqual(parser.text, "Hello there")
    }

    func testNonDeltaEventsAreIgnored() {
        var parser = StreamParser()
        for line in [#"{"type":"system","subtype":"init"}"#,
                     #"{"type":"stream_event","event":{"type":"message_start"}}"#,
                     #"{"type":"stream_event","event":{"type":"content_block_stop"}}"#,
                     #"{"type":"rate_limit_event"}"#,
                     #"{"type":"assistant","message":{}}"#] {
            XCTAssertNil(parser.consume(line), line)
        }
        XCTAssertEqual(parser.text, "")
    }

    func testGarbageLinesDoNotCrashTheStream() {
        var parser = StreamParser()
        for line in ["", "   ", "not json", "{broken", "[1,2,3]"] {
            XCTAssertNil(parser.consume(line))
        }
    }

    func testTheFinalEnvelopeWins() {
        var parser = StreamParser()
        _ = parser.consume(deltaLine)
        _ = parser.consume(#"{"type":"result","is_error":false,"result":"Hello there, tidied up."}"#)
        XCTAssertEqual(parser.answer, "Hello there, tidied up.")
        XCTAssertFalse(parser.isError)
    }

    func testWithoutAResultTheStreamedTextIsUsed() {
        var parser = StreamParser()
        _ = parser.consume(deltaLine)
        XCTAssertEqual(parser.answer, "Hello")
    }

    func testAnErrorResultIsFlagged() {
        var parser = StreamParser()
        _ = parser.consume(#"{"type":"result","is_error":true,"result":"boom"}"#)
        XCTAssertTrue(parser.isError)
    }
}

/// Speech is queued a sentence at a time. Cutting mid-clause sounds broken, so the splitter is
/// conservative about what counts as an ending.
final class SentenceAccumulatorTests: XCTestCase {
    func testWholeSentencesComeOutAsTheyComplete() {
        var accumulator = SentenceAccumulator()
        XCTAssertEqual(accumulator.push("That's the build "), [])
        XCTAssertEqual(accumulator.push("settings tab. "), ["That's the build settings tab."])
        XCTAssertEqual(accumulator.push("The search box filters them. "),
                       ["The search box filters them."])
    }

    func testADecimalPointIsNotASentenceEnd() {
        var accumulator = SentenceAccumulator()
        XCTAssertEqual(accumulator.push("The file is 3.5 megabytes and it is fine. "),
                       ["The file is 3.5 megabytes and it is fine."])
    }

    func testQuestionsAndExclamationsCount() {
        var accumulator = SentenceAccumulator()
        XCTAssertEqual(accumulator.push("Do you mean the toolbar? "), ["Do you mean the toolbar?"])
        XCTAssertEqual(accumulator.push("That worked nicely! "), ["That worked nicely!"])
    }

    func testAVeryShortFragmentWaitsForMore() {
        var accumulator = SentenceAccumulator()
        // "Yes." on its own is too short to be worth an utterance of its own.
        XCTAssertEqual(accumulator.push("Yes. "), [])
        XCTAssertEqual(accumulator.push("It is the export button. "),
                       ["Yes. It is the export button."])
    }

    func testFlushReturnsWhateverIsLeft() {
        var accumulator = SentenceAccumulator()
        _ = accumulator.push("No trailing punctuation here")
        XCTAssertEqual(accumulator.flush(), "No trailing punctuation here")
        XCTAssertNil(accumulator.flush())
    }

    func testMultipleSentencesInOneChunkAllComeOut() {
        var accumulator = SentenceAccumulator()
        let out = accumulator.push("Open the File menu. Then choose Export. Pick PDF from the list. ")
        XCTAssertEqual(out, ["Open the File menu.", "Then choose Export.", "Pick PDF from the list."])
    }

    /// A short closing sentence is held back rather than spoken as its own clipped utterance; the
    /// flush at the end of the stream carries it.
    func testAShortTrailingSentenceIsHeldForTheFlush() {
        var accumulator = SentenceAccumulator()
        XCTAssertEqual(accumulator.push("Open the File menu. Pick PDF. "), ["Open the File menu."])
        XCTAssertEqual(accumulator.flush(), "Pick PDF.")
    }
}
