import CoreGraphics
import XCTest
@testable import Kestrel

/// The circled-region crop is only as good as this arithmetic: the user draws a loop in global
/// AppKit points, measured up from the bottom of the desktop, and the crop has to come out of a PNG
/// that counts down from its own top-left and is very often a different size than the screen.
final class ScreenCaptureTests: XCTestCase {
    /// A Retina laptop: 1440×982 points captured into a 2880×1964 pixel PNG.
    private let laptop = ScreenCapture(url: URL(fileURLWithPath: "/tmp/x.png"),
                                       captureFrame: CGRect(x: 0, y: 0, width: 1440, height: 982),
                                       pixelSize: CGSize(width: 2880, height: 1964))

    func testTheTopLeftOfTheScreenIsTheTopLeftOfThePng() {
        let rect = CGRect(x: 0, y: 882, width: 100, height: 100)   // 100pt tall, at the very top
        let pixels = laptop.pixelRect(forScreenRect: rect)
        XCTAssertEqual(pixels?.minX ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(pixels?.minY ?? .nan, 0, accuracy: 0.01)
    }

    /// Two pixels to the point on this display, so every measurement doubles.
    func testPointsAreScaledToPixels() {
        let pixels = laptop.pixelRect(forScreenRect: CGRect(x: 100, y: 100, width: 200, height: 50))
        XCTAssertEqual(pixels?.width ?? .nan, 400, accuracy: 0.01)
        XCTAssertEqual(pixels?.height ?? .nan, 100, accuracy: 0.01)
        XCTAssertEqual(pixels?.minX ?? .nan, 200, accuracy: 0.01)
    }

    /// AppKit counts up from the bottom and the PNG counts down from the top, so a rect near the
    /// bottom of the screen must land near the bottom of the image — not the top.
    func testTheVerticalAxisIsFlipped() {
        let low = laptop.pixelRect(forScreenRect: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertEqual(low?.maxY ?? .nan, 1964, accuracy: 0.01)
    }

    /// A loop drawn partly off the edge of the capture is clipped to what was actually captured,
    /// rather than producing a crop rectangle outside the image.
    func testARegionOverhangingTheEdgeIsClipped() {
        let pixels = laptop.pixelRect(forScreenRect: CGRect(x: -200, y: 100, width: 400, height: 100))
        XCTAssertEqual(pixels?.minX ?? .nan, 0, accuracy: 0.01)
        XCTAssertEqual(pixels?.width ?? .nan, 400, accuracy: 0.01)
    }

    /// Too small to be a deliberate gesture, or entirely off the capture: no crop at all, so the
    /// full screenshot is used instead of a sliver of nothing.
    func testATinyOrAbsentRegionProducesNoCrop() {
        XCTAssertNil(laptop.pixelRect(forScreenRect: CGRect(x: 10, y: 10, width: 4, height: 4)))
        XCTAssertNil(laptop.pixelRect(forScreenRect: CGRect(x: 5000, y: 5000, width: 100, height: 100)))
    }

    func testACaptureWithNoSizeCannotBeCroppedInto() {
        let empty = ScreenCapture(url: URL(fileURLWithPath: "/tmp/x.png"),
                                  captureFrame: .zero, pixelSize: .zero)
        XCTAssertNil(empty.pixelRect(forScreenRect: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    /// A window capture is offset from the desktop origin, and the crop is relative to the window.
    func testASecondaryDisplayOffsetIsSubtracted() {
        let secondary = ScreenCapture(url: URL(fileURLWithPath: "/tmp/x.png"),
                                      captureFrame: CGRect(x: 1440, y: 0, width: 1440, height: 982),
                                      pixelSize: CGSize(width: 1440, height: 982))
        let pixels = secondary.pixelRect(forScreenRect: CGRect(x: 1540, y: 100, width: 200, height: 50))
        XCTAssertEqual(pixels?.minX ?? .nan, 100, accuracy: 0.01)
    }
}
