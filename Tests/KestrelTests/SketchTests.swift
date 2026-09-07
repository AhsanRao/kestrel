import CoreGraphics
import SwiftUI
import XCTest
@testable import Kestrel

/// The marks are drawn by a cursor that rides the end of the stroke, so where a stroke *begins*
/// is not a cosmetic choice: it is where the cursor has to already be.
final class SketchShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 120, height: 60)

    private func firstPoint(of path: Path) -> CGPoint? {
        var found: CGPoint?
        path.forEach { element in
            guard found == nil else { return }
            if case .move(let point) = element { found = point }
        }
        return found
    }

    func testARectStrokeBeginsOnTheSideItIsToldTo() {
        XCTAssertEqual(firstPoint(of: SketchRect(start: .top).path(in: rect))?.y, rect.minY)
        XCTAssertEqual(firstPoint(of: SketchRect(start: .bottom).path(in: rect))?.y, rect.maxY)
        XCTAssertEqual(firstPoint(of: SketchRect(start: .leading).path(in: rect))?.x, rect.minX)
        XCTAssertEqual(firstPoint(of: SketchRect(start: .trailing).path(in: rect))?.x, rect.maxX)
    }

    func testARectStrokeStaysInsideItsRectWhicheverSideItStartsOn() {
        for start in [SketchStart.top, .bottom, .leading, .trailing] {
            let bounds = SketchRect(start: start).path(in: rect).boundingRect
            XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5, "\(start)")
            XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5, "\(start)")
            XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5, "\(start)")
            XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5, "\(start)")
        }
    }

    func testACircleStrokeBeginsOnTheSideItIsToldTo() {
        let top = firstPoint(of: SketchEllipse(start: .top).path(in: rect))
        let bottom = firstPoint(of: SketchEllipse(start: .bottom).path(in: rect))
        XCTAssertLessThan(top?.y ?? .infinity, rect.midY)
        XCTAssertGreaterThan(bottom?.y ?? 0, rect.midY)
    }

    /// The loop closes past its own start, which is what stops it looking machine-drawn.
    func testACircleCarriesPastWhereItStarted() {
        let plain = SketchEllipse(overshoot: 0).path(in: rect)
        let carried = SketchEllipse(overshoot: 40).path(in: rect)
        XCTAssertNotEqual(plain.currentPoint, carried.currentPoint)
    }

    func testDurationsStayInsideAReadableRange() {
        XCTAssertEqual(Sketch.duration(forSpan: 10), 0.32, accuracy: 0.001)
        XCTAssertEqual(Sketch.duration(forSpan: 100000), 0.75, accuracy: 0.001)
    }

    /// The cursor hangs down and to the right of the point it marks, like the real one, so its own
    /// path must start at the origin of its frame.
    func testTheCursorGlyphIsDrawnFromItsTip() {
        let arrow = CursorArrow().path(in: CGRect(x: 0, y: 0, width: 15, height: 22))
        XCTAssertEqual(firstPoint(of: arrow), .zero)
        XCTAssertEqual(arrow.boundingRect.width, 15, accuracy: 1.5)
    }
}

/// One gesture, one hand: the arrow has to finish before the loop starts, and the loop has to begin
/// where the arrow's tip landed.
final class MarkPlanTests: XCTestCase {
    private let bounds = CGSize(width: 1440, height: 900)

    func testTheLoopStartsWhenTheArrowFinishes() {
        let plan = MarkPlan(target: CGRect(x: 600, y: 300, width: 90, height: 28),
                            bounds: bounds, captionWidth: 300)
        XCTAssertEqual(plan.ringDelay, Sketch.leadIn + plan.arrowDuration, accuracy: 0.001)
    }

    func testTheLoopStartsOnTheSideTheArrowArrivesAt() {
        let roomBelow = MarkPlan(target: CGRect(x: 600, y: 200, width: 90, height: 28),
                                 bounds: bounds, captionWidth: 300)
        XCTAssertFalse(roomBelow.isBelow)
        XCTAssertEqual(roomBelow.ringStart, .top)
        XCTAssertEqual(roomBelow.arrow.to.y, roomBelow.target.minY - 13, accuracy: 0.5)

        let nearBottom = MarkPlan(target: CGRect(x: 600, y: 840, width: 90, height: 28),
                                  bounds: bounds, captionWidth: 300)
        XCTAssertTrue(nearBottom.isBelow)
        XCTAssertEqual(nearBottom.ringStart, .bottom)
        XCTAssertEqual(nearBottom.arrow.to.y, nearBottom.target.maxY + 13, accuracy: 0.5)
    }

    func testTheCaptionIsKeptOnScreen() {
        let plan = MarkPlan(target: CGRect(x: 1430, y: 40, width: 20, height: 20),
                            bounds: bounds, captionWidth: 300)
        XCTAssertGreaterThanOrEqual(plan.captionOrigin.x, 12)
        XCTAssertLessThanOrEqual(plan.captionOrigin.x + 300, bounds.width)
    }
}
