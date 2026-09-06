import AppKit
import XCTest
@testable import Kestrel

final class GridAnnotatorTests: XCTestCase {
    private var source: URL!

    override func setUpWithError() throws {
        try Paths.bootstrap()
        source = Paths.temporaryFile(ext: "png")
        let size = CGSize(width: 400, height: 250)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: source)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: source)
    }

    func testAnnotationAddsAMarginForTheLabels() throws {
        let annotated = try XCTUnwrap(GridAnnotator.annotate(source))
        defer { try? FileManager.default.removeItem(at: annotated) }
        let size = ScreenGrabber.pixelSize(of: annotated)
        // Labels live outside the screenshot so nothing in the interface is painted over.
        XCTAssertGreaterThan(size.width, 400)
        XCTAssertGreaterThan(size.height, 250)
        XCTAssertLessThan(size.width, 400 * 1.2)
    }

    func testAMissingFileIsNotAnError() {
        XCTAssertNil(GridAnnotator.annotate(URL(fileURLWithPath: "/tmp/not-here-\(UUID()).png")))
    }

    func testTheOriginalIsLeftAlone() throws {
        let before = try Data(contentsOf: source)
        let annotated = try XCTUnwrap(GridAnnotator.annotate(source))
        defer { try? FileManager.default.removeItem(at: annotated) }
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertNotEqual(annotated, source)
    }
}
