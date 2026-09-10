import AppKit
import CoreGraphics
import XCTest
@testable import Kestrel

final class NotchMetricsTests: XCTestCase {
    func testADisplayWithoutANotchStillReservesABar() {
        let metrics = NotchMetrics(notchSize: .zero, screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(metrics.hasNotch)
        XCTAssertEqual(metrics.barHeight, 30)
    }

    /// Taller than the housing, never shorter: a bar that stops short of the housing leaves its
    /// bottom edge showing, which is the one thing the shape exists to hide.
    func testTheBarCoversTheHousingWhenThereIsOne() {
        let metrics = NotchMetrics(notchSize: CGSize(width: 179, height: 32),
                                   screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        XCTAssertTrue(metrics.hasNotch)
        XCTAssertGreaterThan(metrics.barHeight, metrics.notchSize.height)
        XCTAssertEqual(metrics.barHeight, 36)
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

    /// The width floor exists for one reason: the longest state label has to fit beside the
    /// housing. It was once 30 points narrower and "Transcribing" came out as "Transcribin…", so
    /// this measures every label at the font the row actually draws it in rather than trusting the
    /// arithmetic in the comment.
    func testEveryStateLabelFitsTheShoulderItIsGiven() {
        let model = PanelModel()
        model.notch = NotchMetrics(notchSize: CGSize(width: 179, height: 32),
                                   screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        // A shoulder is half of what the housing leaves, less the inset and the indicator column
        // — `PanelIndicator` at 16 points plus the 8-point gap in `PanelView.notchRow`.
        let indicatorColumn: CGFloat = 24
        let budget = (model.width - model.notch.notchSize.width) / 2
            - PanelView.inset - indicatorColumn
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let states: [SessionState] = [
            .idle, .listening, .dictating, .transcribing(.ask), .transcribing(.dictation),
            .thinking, .answering, .injecting, .error("whisper-cli not found"),
        ]
        for state in states {
            model.state = state
            let label = model.headline
            let width = NSAttributedString(string: label, attributes: [.font: font]).size().width
            XCTAssertLessThanOrEqual(width, budget,
                                     "\"\(label)\" needs \(width) points and the shoulder gives \(budget)")
        }
    }
}

/// The island shares a notch-tall strip with the camera housing, so anything long enough to run
/// across the housing belongs in the opened half instead.
final class PanelHeadlineTests: XCTestCase {
    func testAnErrorIsNamedShortInTheStripAndSpeltOutBelow() {
        let model = PanelModel()
        model.state = .error("whisper-cli not found — run: brew install whisper-cpp")
        XCTAssertEqual(model.headline, "Kestrel")
        XCTAssertEqual(model.detail, "whisper-cli not found — run: brew install whisper-cpp")
        XCTAssertTrue(model.isExpanded)
    }

    func testAnOrdinaryStateUsesItsOwnLabelAndHasNoDetail() {
        let model = PanelModel()
        model.state = .thinking
        XCTAssertEqual(model.headline, "Thinking")
        XCTAssertNil(model.detail)
    }
}

