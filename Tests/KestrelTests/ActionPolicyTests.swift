import XCTest
@testable import Kestrel

/// The policy is the only thing standing between a spoken sentence and a click on the user's Mac,
/// so it is tested harder than anything else here.
final class ActionPolicyTests: XCTestCase {
    private func press(_ describe: String) -> Action {
        Action(kind: .press, element: 1, describe: describe)
    }

    // MARK: - Defaults

    func testNothingIsAllowedSilentlyByDefault() {
        let decision = ActionPolicy.default.decision(for: press("Click Save"),
                                                     bundleID: "com.apple.TextEdit", elementLabel: "Save")
        XCTAssertEqual(decision, .confirm)
    }

    func testTerminalsAreDeniedOutOfTheBox() {
        for bundleID in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"] {
            XCTAssertEqual(ActionPolicy.default.decision(for: press("Click Run"),
                                                         bundleID: bundleID, elementLabel: "Run"),
                           .deny, bundleID)
        }
    }

    func testAnAllowedAppRunsWithoutAsking() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.TextEdit"] = .allow
        XCTAssertEqual(policy.decision(for: press("Click Bold"), bundleID: "com.apple.TextEdit",
                                       elementLabel: "Bold"), .allow)
    }

    func testADeniedAppIsRefusedEvenForHarmlessActions() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Notes"] = .deny
        XCTAssertEqual(policy.decision(for: press("Click the title field"),
                                       bundleID: "com.apple.Notes", elementLabel: "Title"), .deny)
    }

    // MARK: - Destructive actions

    func testIrreversibleActionsAreConfirmedEvenInAnAllowedApp() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Mail"] = .allow
        for describe in ["Click Send", "Delete the draft", "Press Buy now", "Post the update",
                         "Submit the form", "Archive this thread"] {
            XCTAssertEqual(policy.decision(for: press(describe), bundleID: "com.apple.Mail",
                                           elementLabel: nil), .confirm, describe)
        }
    }

    func testTheControlsOwnLabelCanTriggerConfirmation() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Mail"] = .allow
        XCTAssertEqual(policy.decision(for: press("Click the blue button"),
                                       bundleID: "com.apple.Mail", elementLabel: "Send"), .confirm)
    }

    func testTypedTextCanTriggerConfirmation() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Safari"] = .allow
        let action = Action(kind: .setValue, element: 2, value: "delete everything",
                            describe: "Fill the box")
        XCTAssertEqual(policy.decision(for: action, bundleID: "com.apple.Safari", elementLabel: nil), .confirm)
    }

    func testHarmlessActionsInAnAllowedAppAreNotConfirmed() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Safari"] = .allow
        for describe in ["Click the Reload button", "Open the sidebar", "Scroll down",
                         "Focus the address bar"] {
            XCTAssertEqual(policy.decision(for: press(describe), bundleID: "com.apple.Safari",
                                           elementLabel: nil), .allow, describe)
        }
    }

    func testDenialBeatsDestructiveConfirmation() {
        XCTAssertEqual(ActionPolicy.default.decision(for: press("Send it"),
                                                     bundleID: "com.apple.Terminal",
                                                     elementLabel: nil), .deny)
    }

    func testConfirmationForDestructiveActionsCanBeTurnedOff() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Mail"] = .allow
        policy.confirmDestructive = false
        XCTAssertEqual(policy.decision(for: press("Click Send"), bundleID: "com.apple.Mail",
                                       elementLabel: nil), .allow)
    }

    func testABlockedKindIsNeverPerformed() {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Safari"] = .allow
        policy.blockedKinds = [.setValue]
        let action = Action(kind: .setValue, element: 1, value: "hello", describe: "Type hello")
        XCTAssertEqual(policy.decision(for: action, bundleID: "com.apple.Safari", elementLabel: nil), .deny)
    }

    func testAnUnknownAppFallsBackRatherThanGuessing() {
        var policy = ActionPolicy.default
        policy.fallback = .deny
        XCTAssertEqual(policy.decision(for: press("Click Go"), bundleID: "com.unknown.app",
                                       elementLabel: nil), .deny)
        XCTAssertEqual(policy.decision(for: press("Click Go"), bundleID: nil, elementLabel: nil), .deny)
    }

    // MARK: - Verb detection

    func testVerbsAreMatchedAsWordsNotSubstrings() {
        XCTAssertTrue(DestructiveVerbs.isDestructive("Click Send"))
        XCTAssertTrue(DestructiveVerbs.isDestructive("Deleting the row"))
        XCTAssertTrue(DestructiveVerbs.isDestructive("Sign out of the account"))
        // "sender" and "resend" are not "send"; "cleared" is a form of "clear" and does count.
        XCTAssertFalse(DestructiveVerbs.isDestructive("Open the sender column"))
        XCTAssertFalse(DestructiveVerbs.isDestructive("Scroll to the bottom"))
    }

    // MARK: - Disk

    func testTheShippedPolicyRoundTrips() throws {
        let data = Data(ActionPolicy.defaultJSON.utf8)
        let decoded = try JSONDecoder().decode(ActionPolicy.self, from: data)
        XCTAssertEqual(decoded, ActionPolicy.default)
    }

    func testAPartialPolicyFileKeepsSafeDefaults() throws {
        let decoded = try JSONDecoder().decode(ActionPolicy.self, from: Data(#"{"fallback":"allow"}"#.utf8))
        XCTAssertEqual(decoded.fallback, .allow)
        XCTAssertTrue(decoded.confirmDestructive, "confirmation must survive a partial file")
    }

    func testGarbageInThePolicyFileDoesNotWidenAccess() throws {
        let decoded = try JSONDecoder().decode(ActionPolicy.self, from: Data(#"{"fallback":"whatever"}"#.utf8))
        XCTAssertEqual(decoded.fallback, .confirm)
    }

    // MARK: - Log

    func testAnActionLogLineIsOneJSONObject() throws {
        let entry = ActionLog.Entry(at: Date(), kind: .press, describe: "Click Send",
                                    app: "com.apple.Mail", decision: .confirm, confirmed: true,
                                    succeeded: true, detail: nil)
        let line = try XCTUnwrap(ActionLog.encode(entry))
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(line.contains("\"describe\":\"Click Send\""))
    }
}
