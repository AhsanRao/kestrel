import XCTest
@testable import Kestrel

final class WhisperOutputParsingTests: XCTestCase {
    func testPlainOutput() {
        XCTAssertEqual(WhisperTranscriber.parse(" What app is this?\n"), "What app is this?")
    }

    func testMultilineIsJoined() {
        let stdout = "What is on my screen\nand what should I do next?\n"
        XCTAssertEqual(WhisperTranscriber.parse(stdout), "What is on my screen and what should I do next?")
    }

    func testTimestampsAreStripped() {
        let stdout = """
        [00:00:00.000 --> 00:00:02.480]   Open the export dialog
        [00:00:02.480 --> 00:00:04.000]   and pick PDF.
        """
        XCTAssertEqual(WhisperTranscriber.parse(stdout), "Open the export dialog and pick PDF.")
    }

    func testBlankAudioMarkersAreDropped() {
        XCTAssertEqual(WhisperTranscriber.parse("[BLANK_AUDIO]\n"), "")
        XCTAssertEqual(WhisperTranscriber.parse("(blank_audio)\n"), "")
        XCTAssertEqual(WhisperTranscriber.parse("[MUSIC]\nHello there friend\n"), "Hello there friend")
    }

    func testWhisperLogLinesAreDropped() {
        let stdout = """
        whisper_init_from_file_with_params_no_state: loading model
        main: processing 'x.wav'
        Close the terminal window
        """
        XCTAssertEqual(WhisperTranscriber.parse(stdout), "Close the terminal window")
    }

    func testHallucinatedFillerOnSilenceIsRejected() {
        for noise in ["Thank you.", " you ", "Thanks for watching!", "Bye.", "uh", "..."] {
            XCTAssertEqual(WhisperTranscriber.parse(noise), "", "expected \(noise) to be rejected")
        }
        XCTAssertFalse(WhisperTranscriber.isNoise("Thank you for the summary of this page"))
    }

    func testEnglishOnlyModelForcesEnglish() {
        var config = Config.defaults
        config.language = "auto"
        config.whisperModel = "/tmp/ggml-base.en.bin"
        XCTAssertEqual(WhisperTranscriber.language(config: config), "en")

        config.whisperModel = "/tmp/ggml-small.bin"
        XCTAssertEqual(WhisperTranscriber.language(config: config), "auto")
        config.language = "ur"
        XCTAssertEqual(WhisperTranscriber.language(config: config), "ur")
    }
}
