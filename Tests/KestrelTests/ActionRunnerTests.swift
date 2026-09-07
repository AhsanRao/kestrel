import XCTest
@testable import Kestrel

private final class FakePerformer: ActionPerforming {
    var performed: [Action] = []
    var failOn: Action.Kind?

    var lastPID: pid_t?

    func perform(_ action: Action, on element: AXElementScanner.Element?, in app: pid_t?) throws {
        lastPID = app
        if action.kind == failOn { throw KestrelError.actionFailed("press \(action.describe)") }
        performed.append(action)
    }
}

/// A plan is an ordered thing, so most of these tests are about stopping: a refused step, a failed
/// step and a cancelled run must all leave the rest undone rather than half-applying a sequence.
final class ActionRunnerTests: XCTestCase {
    private let elements = [
        AXElementScanner.Element(id: 1, label: "File", role: "AXMenuBarItem",
                                 frame: CGRect(x: 0, y: 0, width: 40, height: 20)),
        AXElementScanner.Element(id: 2, label: "Export…", role: "AXMenuItem",
                                 frame: CGRect(x: 0, y: 0, width: 120, height: 20)),
    ]

    private func plan(_ actions: [Action]) -> ActionPlan {
        ActionPlan(goal: "Export", actions: actions)
    }

    private var allowSafari: ActionPolicy {
        var policy = ActionPolicy.default
        policy.apps["com.apple.Safari"] = .allow
        return policy
    }

    func testAnAllowedPlanRunsThrough() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in
            XCTFail("nothing here should need confirming"); return .no
        })
        let result = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Open the File menu"),
            Action(kind: .press, element: 2, describe: "Choose Export"),
        ]), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")

        XCTAssertEqual(performer.performed.count, 2)
        XCTAssertTrue(result.completed)
        XCTAssertEqual(result.summary, "Done — 2 steps.")
    }

    func testADeniedAppStopsBeforeDoingAnything() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner.run(plan([Action(kind: .press, element: 1, describe: "Run it")]),
                                elements: elements, policy: .default, bundleID: "com.apple.Terminal")

        XCTAssertTrue(performer.performed.isEmpty)
        XCTAssertTrue(result.stoppedEarly)
        XCTAssertEqual(result.steps.first?.outcome, .denied("not allowed here"))
    }

    func testAnIrreversibleStepIsConfirmedFirst() {
        let performer = FakePerformer()
        var asked: [String] = []
        let runner = ActionRunner(performer: performer, confirm: { action, _ in
            asked.append(action.describe); return .once
        })
        _ = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Open the compose window"),
            Action(kind: .press, element: 2, describe: "Click Send"),
        ]), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")

        XCTAssertEqual(asked, ["Click Send"], "only the irreversible step should be confirmed")
        XCTAssertEqual(performer.performed.count, 2)
    }

    func testDecliningAStepAbandonsTheRest() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .no })
        let result = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Click Send"),
            Action(kind: .press, element: 2, describe: "Click Export"),
        ]), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")

        XCTAssertTrue(performer.performed.isEmpty)
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.steps.first?.outcome, .declined)
        XCTAssertEqual(result.summary, "Stopped, nothing was changed.")
    }

    func testAFailedStepStopsTheSequence() {
        let performer = FakePerformer()
        performer.failOn = .setValue
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Open the field"),
            Action(kind: .setValue, element: 2, value: "hello", describe: "Type the title"),
            Action(kind: .press, element: 1, describe: "Click OK"),
        ]), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")

        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertTrue(result.stoppedEarly)
        XCTAssertEqual(result.performed, 1)
        XCTAssertTrue(result.summary.hasPrefix("Stopped after 1"))
    }

    func testCancellingPartWayThroughStopsTheRest() {
        let performer = FakePerformer()
        var runner: ActionRunner?
        runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner!.run(plan([
            Action(kind: .press, element: 1, describe: "Step one"),
            Action(kind: .press, element: 2, describe: "Step two"),
        ]), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari",
            onStep: { _, index, _ in if index == 0 { runner?.cancel() } })

        XCTAssertEqual(performer.performed.count, 1)
        XCTAssertTrue(result.stoppedEarly)
    }

    func testAPlanIsCappedSoItCannotRunAway() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let many = (1...40).map { Action(kind: .press, element: 1, describe: "Step \($0)") }
        _ = runner.run(plan(many), elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")
        XCTAssertEqual(performer.performed.count, ActionPlan.maximumActions)
    }

    func testAStepPointingAtAnUnknownElementStillReachesThePerformer() {
        // The performer decides it cannot find the control; the runner does not silently skip it.
        let performer = FakePerformer()
        performer.failOn = .press
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner.run(plan([Action(kind: .press, element: 99, describe: "Click ghost")]),
                                elements: elements, policy: allowSafari, bundleID: "com.apple.Safari")
        XCTAssertTrue(result.stoppedEarly)
        if case .failed = result.steps.first?.outcome {} else { XCTFail("expected a failure") }
    }

    func testAnEmptyPlanSaysSo() {
        let runner = ActionRunner(performer: FakePerformer(), confirm: { _, _ in .once })
        let result = runner.run(plan([]), elements: elements, policy: allowSafari, bundleID: "x")
        XCTAssertEqual(result.summary, "Nothing to do.")
        XCTAssertTrue(result.completed)
    }

    // MARK: - Asking once, not every time

    /// The complaint that started this: an app the user has already vouched for asked again on
    /// every single step, which is how a confirmation stops being read.
    func testAnAppIsConfirmedOnceForTheWholeRun() {
        let performer = FakePerformer()
        var asked = 0
        let runner = ActionRunner(performer: performer, confirm: { _, _ in asked += 1; return .once })
        let result = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Click Library"),
            Action(kind: .press, element: 2, describe: "Click Liked Songs"),
            Action(kind: .press, element: 1, describe: "Click Play"),
        ]), elements: elements, policy: .default, bundleID: "com.spotify.client")

        XCTAssertEqual(asked, 1)
        XCTAssertEqual(result.performed, 3)
    }

    /// Saying yes to one irreversible step must never authorise the next one.
    func testADestructiveStepIsAskedEveryTime() {
        let performer = FakePerformer()
        var asked: [String] = []
        let runner = ActionRunner(performer: performer, confirm: { action, _ in
            asked.append(action.describe); return .once
        })
        _ = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Click Send"),
            Action(kind: .press, element: 2, describe: "Click Delete"),
        ]), elements: elements, policy: .default, bundleID: "com.apple.Mail")

        XCTAssertEqual(asked, ["Click Send", "Click Delete"])
    }

    func testAlwaysAllowStopsAskingWithinTheRunToo() {
        let performer = FakePerformer()
        var asked = 0
        let runner = ActionRunner(performer: performer, confirm: { _, _ in asked += 1; return .always })
        _ = runner.run(plan([
            Action(kind: .press, element: 1, describe: "Click Library"),
            Action(kind: .press, element: 2, describe: "Click Play"),
        ]), elements: elements, policy: .default, bundleID: "com.example.notreal")
        XCTAssertEqual(asked, 1)
    }

    func testAnAppGrantedUpFrontIsNotAskedAboutAtAll() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in
            XCTFail("already vouched for"); return .no
        })
        runner.grant("com.spotify.client")
        _ = runner.run(plan([Action(kind: .press, element: 1, describe: "Click Play")]),
                       elements: elements, policy: .default, bundleID: "com.spotify.client")
        XCTAssertEqual(performer.performed.count, 1)
    }

    // MARK: - Launching

    /// Element numbers belong to the scan they came from. Once a different app is in front, every
    /// number still in the plan describes a control that is no longer on screen — so the run stops
    /// there and the rest is planned again. "Opens Spotify but never plays anything" was this.
    func testLaunchingAnAppEndsTheRunAndAsksForAReplan() {
        let performer = FakePerformer()
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner.run(plan([
            Action(kind: .launchApp, value: "com.spotify.client", describe: "Open Spotify"),
            Action(kind: .press, element: 2, describe: "Click Play"),
        ]), elements: elements, policy: .default, bundleID: "com.apple.Safari")

        XCTAssertEqual(result.launchedApp, "com.spotify.client")
        XCTAssertTrue(result.needsReplan)
        XCTAssertFalse(result.stoppedEarly)
        XCTAssertEqual(performer.performed.count, 1, "the stale step must not run")
    }

    func testAFailedRunIsNotMistakenForOneThatNeedsReplanning() {
        let performer = FakePerformer()
        performer.failOn = .press
        let runner = ActionRunner(performer: performer, confirm: { _, _ in .once })
        let result = runner.run(plan([Action(kind: .press, element: 1, describe: "Click Play")]),
                                elements: elements, policy: .default, bundleID: "com.spotify.client")
        XCTAssertFalse(result.needsReplan)
    }

}