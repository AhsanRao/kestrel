import XCTest
@testable import Kestrel

/// The island's window frame is integrated by hand, a frame at a time, so the integration itself is
/// code that can be checked — and the properties that matter are exactly the ones a fixed-duration
/// animation could not give us.
final class PanelSpringTests: XCTestCase {
    /// One display frame at 60 Hz, and the slowest step the animator will ever integrate.
    private let frame = 1.0 / 60
    private let slowestFrame = 1.0 / 30

    private func run(_ spring: inout Spring, seconds: Double, dt: Double) {
        for _ in 0..<Int(seconds / dt) { spring.step(dt) }
    }

    func testItArrivesAtTheTarget() {
        var spring = Spring(value: 100, target: 400)
        run(&spring, seconds: 2, dt: frame)
        XCTAssertEqual(spring.value, 400, accuracy: 0.5)
        XCTAssertTrue(spring.isSettled)
    }

    /// A response of 0.38 s is a promise about how quickly the island opens. Well short of settled
    /// at a tenth of a second would read as lag; already there would read as a jump.
    func testMostOfTheDistanceIsCoveredWithinTheResponse() {
        var spring = Spring(value: 0, target: 100)
        run(&spring, seconds: Spring.response, dt: frame)
        XCTAssertGreaterThan(spring.value, 70)
        XCTAssertLessThan(spring.value, 101)
    }

    /// Damping just under 1 is deliberate — the island settles rather than bounces. Anything the
    /// eye could read as a wobble on a black shape hanging off the notch is wrong.
    func testItBarelyOvershoots() {
        var spring = Spring(value: 0, target: 100)
        var peak = 0.0
        for _ in 0..<240 {
            spring.step(frame)
            peak = max(peak, spring.value)
        }
        XCTAssertLessThan(peak, 102, "overshot to \(peak)")
    }

    /// The whole reason for a spring rather than a curve: a sentence arriving mid-movement changes
    /// where the window is going without taking away the speed it already had.
    func testRetargetingKeepsTheSpeedItAlreadyHad() {
        var spring = Spring(value: 0, target: 100)
        run(&spring, seconds: 0.1, dt: frame)
        let speed = spring.velocity
        XCTAssertGreaterThan(speed, 0, "should be moving a tenth of a second in")

        spring.target = 200
        XCTAssertEqual(spring.velocity, speed, "retargeting must not discard velocity")
        XCTAssertFalse(spring.isSettled)

        run(&spring, seconds: 2, dt: frame)
        XCTAssertEqual(spring.value, 200, accuracy: 0.5)
    }

    /// Four sentences landing closer together than the spring's own response — the case the
    /// animator exists for. It has to end up at the last size asked for, not somewhere between.
    func testRepeatedRetargetsEndAtTheLastOne() {
        var spring = Spring(value: 140, target: 140)
        for target in [190.0, 240, 290, 340] {
            spring.target = target
            run(&spring, seconds: 0.12, dt: frame)
        }
        run(&spring, seconds: 2, dt: frame)
        XCTAssertEqual(spring.value, 340, accuracy: 0.5)
    }

    /// A frame dropped behind a modal, or a wake from sleep, arrives as a long step. The animator
    /// clamps it, and at the clamp the integration still has to converge rather than fly apart.
    func testItStaysStableAtTheLongestStepTheAnimatorAllows() {
        var spring = Spring(value: 0, target: 100)
        run(&spring, seconds: 3, dt: slowestFrame)
        XCTAssertEqual(spring.value, 100, accuracy: 0.5)
        XCTAssertTrue(spring.value.isFinite)
    }

    func testSettlingSnapsExactlyToTheTarget() {
        var spring = Spring(value: 99.9, target: 100)
        spring.velocity = 0.1
        XCTAssertTrue(spring.isSettled)
        spring.settle()
        XCTAssertEqual(spring.value, 100)
        XCTAssertEqual(spring.velocity, 0)
    }
}
