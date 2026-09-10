import AppKit
import XCTest
@testable import Kestrel

/// Registers the shipped defaults for real. Carbon refuses a combination it cannot take, so this
/// catches a bad key code or a modifier mask that does not survive `RegisterEventHotKey`.
final class HotkeyRegistrationTests: XCTestCase {
    func testTheShippedDefaultsRegister() {
        let service = HotkeyService()
        var failures: [String] = []
        service.registrationFailure = { failures.append($0) }
        defer { service.stop() }

        service.start(with: .defaults)
        XCTAssertEqual(failures, [], "Carbon refused: \(failures)")
    }

    func testAnInvalidBindingIsReportedRatherThanSilentlyDropped() {
        let service = HotkeyService()
        var failures: [String] = []
        service.registrationFailure = { failures.append($0) }
        defer { service.stop() }

        // No modifiers at all would hijack a bare keypress system-wide.
        service.start(with: Config.Hotkeys(
            ask: HotkeyBinding(keyCode: 0, modifiers: []),
            dictate: HotkeyBinding(keyCode: 40, modifiers: ["control", "command"])))
        XCTAssertEqual(failures.count, 1)
    }

    /// The dictation toggle acts on presses alone, so a press must never depend on having seen the
    /// release of the one before it — Carbon drops that release whenever the modifiers come up
    /// first, which used to leave dictation stuck on with no way to end it.
    func testASecondPressCountsEvenWhenTheReleaseWasNeverDelivered() {
        var filter = HotkeyPressFilter()
        let start = Date()
        XCTAssertTrue(filter.allows(.dictate, .pressed, at: start))
        // No .released here: that is the event Carbon threw away.
        XCTAssertTrue(filter.allows(.dictate, .pressed, at: start.addingTimeInterval(5)))
    }

    func testKeyRepeatIsSwallowed() {
        var filter = HotkeyPressFilter()
        let start = Date()
        XCTAssertTrue(filter.allows(.ask, .pressed, at: start))
        XCTAssertFalse(filter.allows(.ask, .pressed, at: start.addingTimeInterval(0.05)))
        XCTAssertTrue(filter.allows(.ask, .pressed, at: start.addingTimeInterval(0.4)))
    }

    /// Push-to-talk still needs the pairing: a release with nothing behind it must not end a
    /// session Kestrel never started.
    func testAReleaseWithoutAPressIsIgnored() {
        var filter = HotkeyPressFilter()
        XCTAssertFalse(filter.allows(.ask, .released))
        XCTAssertTrue(filter.allows(.ask, .pressed))
        XCTAssertTrue(filter.allows(.ask, .released))
        XCTAssertFalse(filter.allows(.ask, .released))
    }

    func testKeyNamesMatchTheShippedDefaults() {
        XCTAssertEqual(HotkeyBinding.keyName(0), "A")
        XCTAssertEqual(HotkeyBinding.keyName(40), "K")
    }
}
