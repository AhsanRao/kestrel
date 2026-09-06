import AppKit
import XCTest
@testable import Kestrel

/// The bare ⌃⌘ chord shares its opening with every ⌃⌘-letter shortcut in macOS, so most of these
/// tests are about *not* firing.
final class ModifierChordTests: XCTestCase {
    private let chord: Set<String> = ["control", "command"]
    private let controlCommand: NSEvent.ModifierFlags = [.control, .command]

    private func detector() -> ModifierChordDetector {
        ModifierChordDetector(required: chord)
    }

    func testHoldingTheChordArmsThenFiresAfterTheDwell() {
        var subject = detector()
        XCTAssertEqual(subject.apply(.flagsChanged(controlCommand)), .arm)
        XCTAssertEqual(subject.apply(.dwellElapsed), .fire)
        XCTAssertTrue(subject.isActive)
        XCTAssertEqual(subject.apply(.flagsChanged([])), .release)
        XCTAssertFalse(subject.isActive)
    }

    func testLettingGoBeforeTheDwellNeverFires() {
        var subject = detector()
        XCTAssertEqual(subject.apply(.flagsChanged(controlCommand)), .arm)
        XCTAssertEqual(subject.apply(.flagsChanged([])), .disarm)
        XCTAssertNil(subject.apply(.dwellElapsed))
    }

    /// ⌃⌘K must reach the app, not start a recording.
    func testAKeyPressedDuringTheDwellCancels() {
        var subject = detector()
        subject.apply(.flagsChanged(controlCommand))
        XCTAssertEqual(subject.apply(.keyPressed), .disarm)
        XCTAssertNil(subject.apply(.dwellElapsed))
    }

    /// Held a beat too long before pressing K: the recording has to be thrown away.
    func testAKeyPressedAfterFiringAborts() {
        var subject = detector()
        subject.apply(.flagsChanged(controlCommand))
        subject.apply(.dwellElapsed)
        XCTAssertEqual(subject.apply(.keyPressed), .abort)
        XCTAssertFalse(subject.isActive)
    }

    func testAnotherModifierIsADifferentChord() {
        var subject = detector()
        XCTAssertNil(subject.apply(.flagsChanged([.control, .command, .option])))
        XCTAssertNil(subject.apply(.flagsChanged([.command])))
        XCTAssertNil(subject.apply(.flagsChanged([.control, .shift])))
    }

    func testWideningTheChordMidHoldReleasesIt() {
        var subject = detector()
        subject.apply(.flagsChanged(controlCommand))
        subject.apply(.dwellElapsed)
        XCTAssertEqual(subject.apply(.flagsChanged([.control, .command, .shift])), .release)
    }

    func testCapsLockIsIgnored() {
        var subject = detector()
        XCTAssertEqual(subject.apply(.flagsChanged([.control, .command, .capsLock])), .arm)
    }

    func testRepeatedFlagEventsWhileHeldDoNotRearm() {
        var subject = detector()
        XCTAssertEqual(subject.apply(.flagsChanged(controlCommand)), .arm)
        XCTAssertNil(subject.apply(.flagsChanged(controlCommand)))
    }

    // MARK: - Bindings

    func testABareChordBindingDisplaysOnlyItsModifiers() {
        let binding = HotkeyBinding(keyCode: nil, modifiers: ["control", "command"])
        XCTAssertEqual(binding.display, "⌃⌘")
        XCTAssertTrue(binding.isModifierOnly)
        XCTAssertTrue(binding.isValid)
    }

    func testASingleModifierIsNotAValidChord() {
        XCTAssertFalse(HotkeyBinding(keyCode: nil, modifiers: ["command"]).isValid)
    }

    func testModifierNamesAreNormalised() {
        XCTAssertEqual(HotkeyBinding(keyCode: nil, modifiers: ["cmd", "ctrl"]).normalizedModifiers,
                       ["command", "control"])
        XCTAssertEqual(HotkeyBinding(keyCode: nil, modifiers: ["cmd", "ctrl"]).display, "⌃⌘")
    }

    func testTheShippedDefaultsAreAChordForAskAndAFreeKeyForDictate() {
        XCTAssertEqual(Config.Hotkeys.defaults.ask.display, "⌥⌘")
        XCTAssertTrue(Config.Hotkeys.defaults.ask.isModifierOnly)
        // ⌃⌘K, chosen because macOS already owns ⌃⌘Space, ⌃⌘D, ⌃⌘F and ⌃⌘Q.
        XCTAssertEqual(Config.Hotkeys.defaults.dictate.display, "⌃⌘K")
        XCTAssertFalse(Config.Hotkeys.defaults.dictate.isModifierOnly)
    }

    func testAConfigFileCanOmitTheKeyCodeEntirely() throws {
        let json = #"{"hotkeys":{"ask":{"modifiers":["control","command"]},"dictate":{"keyCode":40,"modifiers":["control","command"]}}}"#
        let config = try XCTUnwrap(ConfigStore.decode(Data(json.utf8)))
        XCTAssertTrue(config.hotkeys.ask.isModifierOnly)
        XCTAssertEqual(config.hotkeys.dictate.keyCode, 40)
    }
}
