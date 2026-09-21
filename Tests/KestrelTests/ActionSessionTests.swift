import CoreGraphics
import XCTest
@testable import Kestrel

/// The act-observe loop, with the CGEvents and screenshots replaced by closures — so what the
/// session decides (stop here, ask first, count this step) is what is tested.
final class ActionSessionTests: XCTestCase {
    /// A session whose hands record calls instead of touching the Mac.
    private func makeSession(policy: ActionPolicy = .default, steps: Int = 10,
                             confirm: @escaping (String) -> Bool = { _ in true })
        -> (ActionSession, () -> [ToolCall]) {
        var performed: [ToolCall] = []
        let hooks = ActionSession.Hooks(
            confirm: confirm,
            perform: { call, _, _ in performed.append(call); return "did it" },
            observe: { _ in .init(capture: nil, controls: "", frontmost: "TestApp") },
            frontmostBundleID: { nil },
            elementLabel: { _ in nil },
            progress: { _ in },
            capHit: { })
        let session = ActionSession(policy: policy, maximumSteps: steps, initialCapture: nil, hooks: hooks)
        return (session, { performed })
    }

    private func open(_ name: String) -> ToolCall {
        ToolCall(tool: .openApp, arguments: ["name": name])
    }

    func testAnAllowedCallRunsAndReportsBackTheScreen() {
        let (session, performed) = makeSession()
        let result = session.handle(open("Safari"))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(performed().count, 1)
        XCTAssertTrue(result.text.contains("In front now: TestApp"))
        XCTAssertTrue(result.text.contains("9 steps left"))
    }

    func testTheStepCapStopsExecutionAndTellsTheModel() {
        let (session, performed) = makeSession(steps: 2)
        _ = session.handle(open("A"))
        _ = session.handle(open("B"))
        let third = session.handle(open("C"))
        XCTAssertTrue(third.isError)
        XCTAssertTrue(third.text.contains("Step limit"))
        XCTAssertEqual(performed().count, 2, "nothing runs past the cap")
    }

    func testTheCapHookFiresExactlyOnce() {
        var capHits = 0
        let hooks = ActionSession.Hooks(
            confirm: { _ in true }, perform: { _, _, _ in "ok" },
            observe: { _ in .init(capture: nil, controls: "", frontmost: nil) },
            frontmostBundleID: { nil }, elementLabel: { _ in nil }, progress: { _ in },
            capHit: { capHits += 1 })
        let session = ActionSession(policy: .default, maximumSteps: 1, initialCapture: nil, hooks: hooks)
        _ = session.handle(open("A"))
        _ = session.handle(open("B"))
        _ = session.handle(open("C"))
        XCTAssertEqual(capHits, 1)
    }

    func testADeclinedConfirmationDoesNotRunAndTellsTheModelToStop() {
        let (session, performed) = makeSession(confirm: { _ in false })
        let result = session.handle(ToolCall(tool: .runShell, arguments: ["command": "osascript -e 'send it'"]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("declined"))
        XCTAssertEqual(performed().count, 0, "a declined action must not run")
    }

    func testAnApprovedConfirmationRuns() {
        let (session, performed) = makeSession(confirm: { _ in true })
        let result = session.handle(ToolCall(tool: .runShell, arguments: ["command": "osascript -e 'send it'"]))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(performed().count, 1)
    }

    func testADeniedActionNeverReachesTheHands() {
        let (session, performed) = makeSession()
        let result = session.handle(ToolCall(tool: .runShell, arguments: ["command": "sudo rm -rf /"]))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("Refused"))
        XCTAssertEqual(performed().count, 0)
    }

    func testCancellationStopsEverythingAfterIt() {
        let (session, performed) = makeSession()
        session.cancel()
        let result = session.handle(open("Safari"))
        XCTAssertTrue(result.isError)
        XCTAssertEqual(performed().count, 0)
    }

    func testStepsAreCounted() {
        let (session, _) = makeSession()
        _ = session.handle(open("A"))
        _ = session.handle(open("B"))
        XCTAssertEqual(session.steps, 2)
    }
}
