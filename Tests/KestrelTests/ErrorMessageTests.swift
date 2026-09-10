import XCTest
@testable import Kestrel

/// Errors are the only text a user sees when something breaks, so they are tested like UI.
final class ErrorMessageTests: XCTestCase {
    func testEveryErrorNamesItsFix() {
        let cases: [KestrelError] = [
            .whisperBinaryMissing("/opt/homebrew/bin/whisper-cli"),
            .whisperModelMissing("~/.kestrel/models/ggml-base.en.bin"),
            .backendMissing("claude"),
            .backendMissing("codex"),
            .microphoneDenied,
            .screenRecordingDenied,
            .accessibilityDenied,
            .quotaExhausted("Claude", resets: nil),
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty)
            let hint = message.lowercased()
            let actionable = hint.contains("run:") || hint.contains("system settings")
                || hint.contains("switch") || hint.contains("install")
            XCTAssertTrue(actionable, "not actionable: \(message)")
        }
    }

    func testPermissionErrorsDeepLinkToTheRightPane() {
        XCTAssertTrue(KestrelError.microphoneDenied.settingsURL?.absoluteString.contains("Privacy_Microphone") == true)
        XCTAssertTrue(KestrelError.screenRecordingDenied.settingsURL?.absoluteString.contains("Privacy_ScreenCapture") == true)
        XCTAssertTrue(KestrelError.accessibilityDenied.settingsURL?.absoluteString.contains("Privacy_Accessibility") == true)
        XCTAssertNil(KestrelError.emptyTranscript.settingsURL)
    }

    func testBackendFailureIncludesStderr() {
        let message = KestrelError.backendFailed(name: "claude", stderr: "boom: bad flag").errorDescription
        XCTAssertEqual(message, "claude stopped short — boom: bad flag")
    }

    /// A CLI that refuses on quota names the hour it will work again, and that hour is the whole
    /// point of the message: without it the user cannot tell a twenty-minute wait from a two-day one.
    func testQuotaErrorNamesTheResetTime() {
        let resets = Date().addingTimeInterval(90 * 60)
        let message = KestrelError.quotaExhausted("Claude", resets: resets).errorDescription ?? ""
        XCTAssertTrue(message.contains("until"), message)
        XCTAssertTrue(message.contains(KestrelError.clockTime(resets)), message)

        let vague = KestrelError.quotaExhausted("Claude", resets: nil).errorDescription ?? ""
        XCTAssertTrue(vague.contains("for now"), vague)
    }
}
