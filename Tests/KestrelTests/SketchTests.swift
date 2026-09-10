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

    /// The pencil hangs down and to the right of the point it marks, so its own path has to begin
    /// at the top of its frame: that point is where the stroke has got to.
    func testThePencilIsDrawnFromItsPoint() {
        let frame = CGRect(origin: .zero, size: KestrelCursor.size)
        let path = Pencil(part: .body).path(in: frame)
        let tip = firstPoint(of: path)
        XCTAssertEqual(tip?.y ?? .nan, frame.minY, accuracy: 0.01)
        // A barrel's half-width of clearance, so the side that swings left of the point still fits.
        XCTAssertEqual(tip?.x ?? .nan, 3.83, accuracy: 0.5)
        XCTAssertTrue(frame.contains(path.boundingRect), "the pencil has to fit inside its frame")
    }

    /// The nib is the sharpened end of the same silhouette, so it starts where the body starts.
    func testTheNibSharesThePencilsPoint() {
        let frame = CGRect(origin: .zero, size: KestrelCursor.size)
        XCTAssertEqual(firstPoint(of: Pencil(part: .nib).path(in: frame)),
                       firstPoint(of: Pencil(part: .body).path(in: frame)))
    }
}
