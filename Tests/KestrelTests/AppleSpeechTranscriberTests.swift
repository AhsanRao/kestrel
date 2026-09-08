import XCTest
@testable import Kestrel

final class AppleSpeechTranscriberTests: XCTestCase {
    @available(macOS 26.0, *)
    func testSegmentsConcatenateWithoutDoublingSpaces() {
        XCTAssertEqual(AppleSpeechTranscriber.clean([" What is this", " and where."]),
                       "What is this and where.")
        XCTAssertEqual(AppleSpeechTranscriber.clean([]), "")
        XCTAssertEqual(AppleSpeechTranscriber.clean(["  spaced  ", "  out "]), "spaced out")
    }

    @available(macOS 26.0, *)
    func testVocabularyHintSplitsIntoPhrases() {
        XCTAssertEqual(AppleSpeechTranscriber.vocabulary("Ahsan, Kestrel, theek hai"),
                       ["Ahsan", "Kestrel", "theek hai"])
        XCTAssertEqual(AppleSpeechTranscriber.vocabulary(nil), [])
        XCTAssertEqual(AppleSpeechTranscriber.vocabulary("  ,  , "), [])
    }

    /// Apple's engine is the default, and asking for whisper actually gets whisper.
    func testRoutingHonoursTheConfiguredEngine() {
        let router = RoutingTranscriber()
        var config = Config.defaults
        XCTAssertEqual(config.transcriptionEngine, .apple)
        config.transcriptionEngine = .whisper
        XCTAssertTrue(router.engine(for: config) is WhisperTranscriber)
        config.transcriptionEngine = .apple
        if #available(macOS 26.0, *), AppleSpeechTranscriber.isSupported {
            XCTAssertTrue(router.engine(for: config) is AppleSpeechTranscriber)
        } else {
            XCTAssertTrue(router.engine(for: config) is WhisperTranscriber)
        }
    }
}
