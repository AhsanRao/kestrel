import XCTest
@testable import Kestrel

final class ConfigTests: XCTestCase {
    private func decode(_ json: String) throws -> Config {
        try XCTUnwrap(ConfigStore.decode(Data(json.utf8)))
    }

    func testEmptyObjectYieldsDefaults() throws {
        let config = try decode("{}")
        XCTAssertEqual(config, .defaults)
    }

    func testPartialFileKeepsDefaultsForMissingKeys() throws {
        let config = try decode(#"{"backend":"codex","speakAnswers":false}"#)
        XCTAssertEqual(config.backend, .codex)
        XCTAssertFalse(config.speakAnswers)
        XCTAssertEqual(config.voiceRate, Config.defaults.voiceRate)
        XCTAssertEqual(config.hotkeys, .defaults)
    }

    func testUnknownKeysAreIgnored() throws {
        let config = try decode(#"{"backend":"claude","somethingNew":42}"#)
        XCTAssertEqual(config.backend, .claude)
    }

    func testWrongTypesFallBackInsteadOfFailing() throws {
        let config = try decode(#"{"speakAnswers":"yes","panelAutoHideSeconds":"soon"}"#)
        XCTAssertEqual(config.speakAnswers, Config.defaults.speakAnswers)
        XCTAssertEqual(config.panelAutoHideSeconds, Config.defaults.panelAutoHideSeconds)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let config = try decode(#"{"voiceRate":9.5,"screenshotMaxEdge":99999,"panelAutoHideSeconds":0}"#)
        XCTAssertEqual(config.voiceRate, 0.7)
        XCTAssertEqual(config.screenshotMaxEdge, 4096)
        XCTAssertEqual(config.panelAutoHideSeconds, 2)
    }

    func testRoundTripsThroughJSON() throws {
        var original = Config.defaults
        original.backend = .codex
        original.claudeModel = "sonnet"
        original.hotkeys.dictate = HotkeyBinding(keyCode: 8, modifiers: ["control", "shift"])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try XCTUnwrap(ConfigStore.decode(data)), original)
    }

    func testTildePathsAreExpanded() throws {
        let config = try decode(#"{"whisperModel":"~/.kestrel/models/ggml-small.bin"}"#)
        XCTAssertFalse(config.whisperModelURL.path.hasPrefix("~"))
        XCTAssertTrue(config.whisperModelURL.path.hasSuffix("/.kestrel/models/ggml-small.bin"))
    }

    func testHotkeyDisplayAndModifierMask() {
        XCTAssertEqual(Config.Hotkeys.defaults.ask.display, "⌃⌘A")
        XCTAssertEqual(Config.Hotkeys.defaults.dictate.display, "⌃⌘K")
        XCTAssertTrue(Config.Hotkeys.defaults.ask.isValid)
        XCTAssertFalse(HotkeyBinding(keyCode: 49, modifiers: []).isValid)
    }
}
