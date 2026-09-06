import XCTest
@testable import Kestrel

/// The walkthrough overlay is only as good as this arithmetic: the model answers in a grid it
/// declares for itself, top-left origin, and the window server wants points from the bottom-left.
final class ScreenCaptureTests: XCTestCase {
    /// A 1512x982-point Retina display, captured and downscaled to 2048 px on the long edge.
    private let laptop = ScreenCapture(
        url: URL(fileURLWithPath: "/tmp/shot.png"),
        captureFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        pixelSize: CGSize(width: 2048, height: 1330))

    /// What a model actually reports for that screenshot: its own, much smaller view of it.
    private let modelGrid = Walkthrough.ImageSize(w: 320, h: 208)

    func testScaleComesFromTheDeclaredGridNotThePng() {
        XCTAssertEqual(laptop.pointsPerUnitX(in: modelGrid), 1512.0 / 320.0, accuracy: 0.0001)
        XCTAssertEqual(laptop.pointsPerUnitY(in: modelGrid), 982.0 / 208.0, accuracy: 0.0001)
    }

    func testTopLeftMapsToTheTopLeftOfTheDisplay() {
        let rect = laptop.screenRect(for: .init(x: 0, y: 0, w: 32, h: 20), in: modelGrid)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 982, accuracy: 0.001)   // AppKit y grows upwards
    }

    func testBottomOfTheGridMapsToTheBottomOfTheDisplay() {
        let rect = laptop.screenRect(for: .init(x: 0, y: 198, w: 10, h: 10), in: modelGrid)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.01)
    }

    func testAFullSpanTargetCoversTheDisplay() {
        let rect = laptop.screenRect(for: .init(x: 0, y: 0, w: 320, h: 208), in: modelGrid)
        XCTAssertEqual(rect.width, 1512, accuracy: 0.01)
        XCTAssertEqual(rect.height, 982, accuracy: 0.01)
    }

    /// The real failure this design exists to fix: a toolbar button reported as {104,22,30,14} in
    /// a 320x208 view has to land a third of the way across the real screen, not near its edge.
    func testAButtonReportedInTheModelsGridLandsWhereItReallyIs() {
        let rect = laptop.screenRect(for: .init(x: 104, y: 22, w: 30, h: 14), in: modelGrid)
        XCTAssertEqual(rect.midX / 1512, (104 + 15) / 320.0, accuracy: 0.005)
        XCTAssertEqual((982 - rect.midY) / 982, (22 + 7) / 208.0, accuracy: 0.005)
    }

    func testAMissingGridIsTreatedAsPerMille() {
        let walkthrough = Walkthrough(goal: "x", steps: [])
        XCTAssertEqual(walkthrough.space, .perMille)
        let rect = laptop.screenRect(for: .init(x: 500, y: 0, w: 100, h: 100), in: walkthrough.space)
        XCTAssertEqual(rect.minX, 1512 * 0.5, accuracy: 0.01)
    }

    func testANonsenseGridIsTreatedAsPerMille() {
        let walkthrough = Walkthrough(goal: "x", steps: [], image: .init(w: 0, h: 0))
        XCTAssertEqual(walkthrough.space, .perMille)
    }

    func testSecondaryDisplayOffsetIsApplied() {
        let external = ScreenCapture(
            url: URL(fileURLWithPath: "/tmp/shot.png"),
            captureFrame: CGRect(x: 1512, y: 200, width: 2560, height: 1440),
            pixelSize: CGSize(width: 2048, height: 1152))
        let rect = external.screenRect(for: .init(x: 0, y: 0, w: 32, h: 20), in: modelGrid)
        XCTAssertEqual(rect.minX, 1512, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 200 + 1440, accuracy: 0.001)
        XCTAssertEqual(rect.width, 2560 * (32.0 / 320.0), accuracy: 0.01)
    }

    func testTheSameTargetLandsProportionallyOnAnyDisplaySize() {
        let small = ScreenCapture(url: URL(fileURLWithPath: "/tmp/a.png"),
                                  captureFrame: CGRect(x: 0, y: 0, width: 1280, height: 800),
                                  pixelSize: CGSize(width: 1280, height: 800))
        let target = WalkthroughStep.Target(x: 160, y: 104, w: 32, h: 20)
        XCTAssertEqual(laptop.screenRect(for: target, in: modelGrid).midX / 1512,
                       small.screenRect(for: target, in: modelGrid).midX / 1280, accuracy: 0.0001)
    }

    func testViewRectStaysInTopLeftSpaceForSwiftUI() {
        let rect = laptop.viewRect(for: .init(x: 0, y: 0, w: 32, h: 20), in: modelGrid)
        XCTAssertEqual(rect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)

        let lower = laptop.viewRect(for: .init(x: 0, y: 208, w: 4, h: 4), in: modelGrid)
        XCTAssertEqual(lower.minY, 982, accuracy: 0.01)
    }

    // MARK: - Plausibility

    func testTargetsOffTheDeclaredGridAreRejected() {
        XCTAssertFalse(ScreenCapture.isPlausible(.init(x: 900, y: 20, w: 40, h: 20), in: modelGrid))
        XCTAssertFalse(ScreenCapture.isPlausible(.init(x: 10, y: -400, w: 40, h: 20), in: modelGrid))
        XCTAssertTrue(ScreenCapture.isPlausible(.init(x: 104, y: 22, w: 30, h: 14), in: modelGrid))
    }

    func testDegenerateTargetsAreRejected() {
        XCTAssertFalse(ScreenCapture.isPlausible(.init(x: 10, y: 10, w: 0, h: 20), in: modelGrid))
        XCTAssertFalse(ScreenCapture.isPlausible(.init(x: 10, y: 10, w: 20, h: 0), in: modelGrid))
    }

    func testAWholeScreenTargetIsNotATarget() {
        XCTAssertFalse(ScreenCapture.isPlausible(.init(x: 0, y: 0, w: 320, h: 208), in: modelGrid))
        // A full-width toolbar is still a legitimate target.
        XCTAssertTrue(ScreenCapture.isPlausible(.init(x: 0, y: 0, w: 320, h: 14), in: modelGrid))
    }
}
