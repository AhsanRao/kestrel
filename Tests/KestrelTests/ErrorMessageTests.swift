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
            .quotaExhausted("Claude"),
        ]
        for error in cases {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty)
            let actionable = message.contains("run:") || message.contains("System Settings")
                || message.contains("switch") || message.contains("install")
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
        XCTAssertEqual(message, "claude failed: boom: bad flag")
    }
}
