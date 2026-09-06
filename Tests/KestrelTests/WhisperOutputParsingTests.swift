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
        let english = URL(fileURLWithPath: "/tmp/ggml-base.en.bin")
        let multilingual = URL(fileURLWithPath: "/tmp/ggml-small.bin")

        XCTAssertEqual(WhisperTranscriber.language(forModel: english, config: config), "en")
        XCTAssertEqual(WhisperTranscriber.language(forModel: multilingual, config: config), "auto")
        config.language = "ur"
        XCTAssertEqual(WhisperTranscriber.language(forModel: multilingual, config: config), "ur")
        // An .en model cannot do Urdu whatever the config says.
        XCTAssertEqual(WhisperTranscriber.language(forModel: english, config: config), "en")
    }

    func testAMissingConfiguredModelFallsBackToWhatIsInstalled() {
        var config = Config.defaults
        config.whisperModel = "/tmp/definitely-not-here-\(UUID()).bin"
        // Resolves to whatever is in ~/.kestrel/models, or nil on a machine with none.
        let resolved = WhisperTranscriber.resolveModel(config: config)
        XCTAssertNotEqual(resolved?.path, config.whisperModel)
    }
}
