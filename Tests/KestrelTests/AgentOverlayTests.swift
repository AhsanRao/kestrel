import XCTest
@testable import Kestrel

/// The overlay is how an agent run stays legible, so its bookkeeping is worth pinning down.
@MainActor
final class AgentOverlayTests: XCTestCase {
    private func model() -> AgentOverlayModel {
        let model = AgentOverlayModel()
        model.origin = CGPoint(x: 0, y: 0)
        model.size = CGSize(width: 1440, height: 900)
        return model
    }

    func testASingleStepRunShowsNoCounter() {
        let subject = model()
        subject.begin(goal: "Export the file", stepCount: 1)
        XCTAssertEqual(subject.progress, "")
    }

    func testAMultiStepRunCountsFromOne() {
        let subject = model()
        subject.begin(goal: "Export the file", stepCount: 3)
        XCTAssertEqual(subject.progress, "Step 1 of 3")
        subject.show(Action(kind: .press, describe: "Choose Export"), at: nil, index: 1)
        XCTAssertEqual(subject.progress, "Step 2 of 3")
    }

    func testTheCounterCannotRunPastTheEnd() {
        let subject = model()
        subject.begin(goal: "x", stepCount: 2)
        subject.show(Action(kind: .press, describe: "y"), at: nil, index: 9)
        XCTAssertEqual(subject.progress, "Step 2 of 2")
    }

    func testTheTargetIsFlippedIntoTheOverlaysDrawingSpace() {
        let subject = model()
        // A control at the very top of the screen in AppKit points…
        subject.show(Action(kind: .press, describe: "Click File"),
                     at: CGRect(x: 60, y: 880, width: 40, height: 20), index: 0)
        // …is at the very top in SwiftUI's top-left space.
        XCTAssertEqual(subject.targetInView?.minY, 0)
        XCTAssertEqual(subject.targetInView?.minX, 60)
    }

    func testASecondDisplayOffsetIsRemoved() {
        let subject = model()
        subject.origin = CGPoint(x: 1440, y: 0)
        subject.show(Action(kind: .press, describe: "x"),
                     at: CGRect(x: 1500, y: 880, width: 40, height: 20), index: 0)
        XCTAssertEqual(subject.targetInView?.minX, 60)
    }

    func testNoTargetMeansNothingIsDrawn() {
        let subject = model()
        subject.show(Action(kind: .launchApp, value: "com.apple.Safari", describe: "Open Safari"),
                     at: nil, index: 0)
        XCTAssertNil(subject.targetInView)
        XCTAssertEqual(subject.describe, "Open Safari")
    }

    func testResettingClearsEverything() {
        let subject = model()
        subject.begin(goal: "x", stepCount: 3)
        subject.show(Action(kind: .press, describe: "y"), at: .zero, index: 1)
        subject.reset()
        XCTAssertEqual(subject.goal, "")
        XCTAssertEqual(subject.stepCount, 0)
        XCTAssertNil(subject.target)
    }
}
