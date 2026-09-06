import CoreGraphics
import XCTest
@testable import Kestrel

final class NotchMetricsTests: XCTestCase {
    func testADisplayWithoutANotchStillReservesABar() {
        let metrics = NotchMetrics(notchSize: .zero, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.barHeight, 26)
    }

    func testTheBarMatchesTheHousingWhenThereIsOne() {
        let metrics = NotchMetrics(notchSize: CGSize(width: 179, height: 32),
                                   screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertEqual(metrics.barHeight, 32)
    }
}

final class NotchShapeTests: XCTestCase {
    /// The panel hangs off the top edge, so the shape must reach both top corners exactly — any
    /// inset there shows as a seam between the panel and the screen edge.
    func testTheShapeFillsItsRectAtTheTopAndIsRoundedAtTheBottom() {
        let rect = CGRect(x: 0, y: 0, width: 440, height: 120)
        let bounds = NotchShape().path(in: rect).boundingRect
        XCTAssertEqual(bounds.minY, rect.minY, accuracy: 0.5)
        XCTAssertEqual(bounds.minX, rect.minX, accuracy: 0.5)
        XCTAssertEqual(bounds.maxX, rect.maxX, accuracy: 0.5)
        XCTAssertEqual(bounds.maxY, rect.maxY, accuracy: 0.5)
        // The bottom corners are cut, so the very corner point is outside the filled shape.
        XCTAssertFalse(NotchShape().path(in: rect).contains(CGPoint(x: rect.maxX - 1, y: rect.maxY - 1)))
    }

    func testARadiusLargerThanTheShapeDoesNotInvertIt() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 20)
        let bounds = NotchShape(bottomRadius: 400, shoulder: 400).path(in: rect).boundingRect
        XCTAssertEqual(bounds.width, rect.width, accuracy: 0.5)
        XCTAssertLessThanOrEqual(bounds.height, rect.height + 0.5)
    }
}

final class PanelSizingTests: XCTestCase {
    func testThePanelOpensOnlyWhenThereIsSomethingToRead() {
        let model = PanelModel()
        model.state = .listening
        XCTAssertFalse(model.isExpanded)
        model.answer = "That's the build log."
        XCTAssertTrue(model.isExpanded)
    }

    func testCollapsedTheBarIsAlwaysWiderThanTheHousing() {
        let model = PanelModel()
        model.notch = NotchMetrics(notchSize: CGSize(width: 179, height: 32),
                                   screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        XCTAssertGreaterThan(model.width, model.notch.notchSize.width + 100)
    }
}
