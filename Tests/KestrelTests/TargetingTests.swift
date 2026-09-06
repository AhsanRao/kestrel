import XCTest
@testable import Kestrel

/// Where a walkthrough step actually points. Accessibility frames are exact; the model's
/// coordinates are a fallback and are treated as such.
final class WalkthroughResolverTests: XCTestCase {
    private let capture = ScreenCapture(
        url: URL(fileURLWithPath: "/tmp/shot.png"),
        captureFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        pixelSize: CGSize(width: 2048, height: 1330))

    private let elements = [
        AXElementScanner.Element(id: 1, label: "File", role: "AXMenuBarItem",
                                 frame: CGRect(x: 60, y: 958, width: 40, height: 22)),
        AXElementScanner.Element(id: 2, label: "Export…", role: "AXMenuItem",
                                 frame: CGRect(x: 80, y: 700, width: 160, height: 24)),
    ]

    func testAChosenElementUsesTheFrameMacOSReported() {
        let walkthrough = Walkthrough(goal: "Export", steps: [
            WalkthroughStep(n: 1, instruction: "Click File", element: 1),
            WalkthroughStep(n: 2, instruction: "Choose Export", element: 2),
        ])
        let resolved = WalkthroughResolver.resolve(walkthrough, elements: elements, capture: capture)
        XCTAssertEqual(resolved.map(\.frame), elements.map(\.frame))
        XCTAssertTrue(resolved.allSatisfy(\.isExact))
    }

    func testAnElementNumberThatDoesNotExistFallsBackToCoordinates() {
        let walkthrough = Walkthrough(goal: "Export", steps: [
            WalkthroughStep(n: 1, instruction: "Click File", element: 99,
                            target: .init(x: 100, y: 100, w: 60, h: 30)),
        ], image: .init(w: 1000, h: 1000))
        let resolved = WalkthroughResolver.resolve(walkthrough, elements: elements, capture: capture)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].isExact)
    }

    func testAStepPointingAtNothingUsableIsDropped() {
        let walkthrough = Walkthrough(goal: "Export", steps: [
            WalkthroughStep(n: 1, instruction: "Click something", element: 99),
            WalkthroughStep(n: 2, instruction: "Click elsewhere", target: .init(x: 5000, y: 5000, w: 10, h: 10)),
        ], image: .init(w: 1000, h: 1000))
        XCTAssertTrue(WalkthroughResolver.resolve(walkthrough, elements: elements, capture: capture).isEmpty)
    }

    func testWithNoAccessibilityListEverythingFallsBackToCoordinates() {
        let walkthrough = Walkthrough(goal: "Export", steps: [
            WalkthroughStep(n: 1, instruction: "Click File", target: .init(x: 100, y: 100, w: 60, h: 30)),
        ], image: .init(w: 1000, h: 1000))
        let resolved = WalkthroughResolver.resolve(walkthrough, elements: [], capture: capture)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].isExact)
    }

    func testElementModeStepsSurviveSanitising() {
        let steps = [WalkthroughStep(n: 7, instruction: "Click File", element: 1)]
        XCTAssertEqual(WalkthroughParser.sanitize(steps).count, 1)
        XCTAssertEqual(WalkthroughParser.sanitize(steps)[0].n, 1)
    }

    func testElementJSONParses() throws {
        let json = #"{"goal":"Export","steps":[{"n":1,"element":4,"instruction":"Click File"}]}"#
        let walkthrough = try XCTUnwrap(WalkthroughParser.parse(json))
        XCTAssertEqual(walkthrough.steps[0].element, 4)
        XCTAssertNil(walkthrough.steps[0].target)
    }
}

/// Circling a region while holding the hotkey (spec §8.16).
final class DragTrackerTests: XCTestCase {
    func testATrailBecomesItsBoundingBox() {
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 140),
                      CGPoint(x: 180, y: 220), CGPoint(x: 90, y: 190)]
        let box = try? XCTUnwrap(DragTracker.boundingBox(of: points, padding: 0))
        XCTAssertEqual(box?.minX, 90)
        XCTAssertEqual(box?.maxX, 200)
        XCTAssertEqual(box?.minY, 100)
        XCTAssertEqual(box?.maxY, 220)
    }

    func testTheBoxIsPaddedSoTheCircledThingIsInside() {
        let points = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100),
                      CGPoint(x: 200, y: 200), CGPoint(x: 100, y: 200)]
        let box = DragTracker.boundingBox(of: points, padding: 12)
        XCTAssertEqual(box?.width, 124)
    }

    func testATwitchIsNotAGesture() {
        XCTAssertNil(DragTracker.boundingBox(of: [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 11),
                                                  CGPoint(x: 13, y: 12), CGPoint(x: 14, y: 13)]))
        XCTAssertNil(DragTracker.boundingBox(of: [CGPoint(x: 10, y: 10)]))
        XCTAssertNil(DragTracker.boundingBox(of: []))
    }

    func testALongThinUnderlineStillCounts() {
        let points = (0..<20).map { CGPoint(x: 100 + Double($0) * 10, y: 300) }
        XCTAssertNotNil(DragTracker.boundingBox(of: points))
    }
}

/// Cutting the circled region out of the screenshot.
final class CropGeometryTests: XCTestCase {
    private let capture = ScreenCapture(
        url: URL(fileURLWithPath: "/tmp/shot.png"),
        captureFrame: CGRect(x: 0, y: 0, width: 1000, height: 500),
        pixelSize: CGSize(width: 2000, height: 1000))

    func testTopLeftOfTheScreenIsTopLeftOfThePng() {
        let rect = try? XCTUnwrap(capture.pixelRect(forScreenRect:
            CGRect(x: 0, y: 400, width: 100, height: 100)))
        XCTAssertEqual(rect?.minX, 0)
        XCTAssertEqual(rect?.minY, 0)      // PNG rows count down from the top
        XCTAssertEqual(rect?.width, 200)   // 2x backing scale
    }

    func testARegionOffTheCaptureIsClipped() {
        let rect = capture.pixelRect(forScreenRect: CGRect(x: 900, y: 0, width: 400, height: 200))
        XCTAssertEqual(rect?.width, 200)
    }

    func testARegionCompletelyOutsideIsRefused() {
        XCTAssertNil(capture.pixelRect(forScreenRect: CGRect(x: 5000, y: 5000, width: 50, height: 50)))
    }

    func testASliverIsRefused() {
        XCTAssertNil(capture.pixelRect(forScreenRect: CGRect(x: 10, y: 10, width: 4, height: 40)))
    }
}
