import XCTest
@testable import Kestrel

/// The menu bar is the only always-visible part of Kestrel, so what it does in each state is worth
/// pinning down even though the animation itself is AppKit's.
final class StatusItemAnimatorTests: XCTestCase {
    func testRecordingBreathesQuickly() {
        for state in [SessionState.listening, .dictating] {
            guard case .breathing(let period, _) = StatusItemAnimator.Pace.forState(state) else {
                return XCTFail("\(state) should breathe")
            }
            XCTAssertLessThan(period, 1.0, "recording should feel immediate")
        }
    }

    func testWorkingBreathesMoreSlowly() {
        guard case .breathing(let thinking, _) = StatusItemAnimator.Pace.forState(.thinking),
              case .breathing(let listening, _) = StatusItemAnimator.Pace.forState(.listening)
        else { return XCTFail("both should breathe") }
        XCTAssertGreaterThan(thinking, listening)
    }

    func testActingAndInjectingCountAsWorking() {
        for state in [SessionState.injecting, .transcribing(.ask), .thinking] {
            guard case .breathing = StatusItemAnimator.Pace.forState(state) else {
                return XCTFail("\(state) should breathe")
            }
        }
    }

    func testIdleAnsweringAndErrorsAreStill() {
        for state in [SessionState.idle, .answering, .guiding, .error("x")] {
            XCTAssertEqual(StatusItemAnimator.Pace.forState(state), .still, "\(state)")
        }
    }

    func testTheIconNeverGoesFullyInvisible() {
        for state in [SessionState.listening, .thinking] {
            guard case .breathing(_, let floor) = StatusItemAnimator.Pace.forState(state) else { continue }
            XCTAssertGreaterThan(floor, 0.3, "a menu bar icon that vanishes reads as a bug")
        }
    }
}
