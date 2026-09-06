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

    func testKeyNamesMatchTheShippedDefaults() {
        XCTAssertEqual(HotkeyBinding.keyName(0), "A")
        XCTAssertEqual(HotkeyBinding.keyName(40), "K")
    }
}
