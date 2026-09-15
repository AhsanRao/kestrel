import CoreGraphics
import XCTest
@testable import Kestrel

/// The tool call model, the coordinate maths a click depends on, and the flags that offer the tools.
final class ActuationTests: XCTestCase {
    // MARK: - ToolCall

    func testDescribeReadsLikeASentence() {
        XCTAssertEqual(ToolCall(tool: .openApp, arguments: ["name": "Safari"]).describe, "open Safari")
        XCTAssertEqual(ToolCall(tool: .pressKey, arguments: ["key": "tab", "modifiers": ["cmd"]]).describe,
                       "press cmd+tab")
    }

    func testNumbersDecodeWhetherIntOrDouble() {
        XCTAssertEqual(ToolCall(tool: .click, arguments: ["x": 5]).number("x"), 5)
        XCTAssertEqual(ToolCall(tool: .click, arguments: ["x": 5.5]).number("x"), 5.5)
    }

    func testEverySchemaIsAWellFormedObject() {
        for tool in ActionTool.allCases {
            XCTAssertEqual(tool.inputSchema["type"] as? String, "object", tool.rawValue)
            XCTAssertNotNil(tool.inputSchema["properties"], tool.rawValue)
        }
    }

    // MARK: - Click coordinates

    /// A 2× capture of a window 100pt up and 200pt in from the primary's bottom-left, on a 1000pt
    /// tall primary display. The model only ever sees the PNG, so its coordinates are the PNG's.
    private let capture = ScreenCapture(url: URL(fileURLWithPath: "/tmp/x.png"),
                                        captureFrame: CGRect(x: 100, y: 200, width: 800, height: 600),
                                        pixelSize: CGSize(width: 1600, height: 1200))

    func testCentrePixelMapsToCentreOfTheWindowInScreenSpace() {
        // Middle of the PNG → middle of the window, in CoreGraphics coordinates (down from top).
        let point = capture.screenPoint(forPixel: CGPoint(x: 800, y: 600), primaryHeight: 1000)
        XCTAssertEqual(point?.x ?? 0, 500, accuracy: 0.5)   // 100 + 400pt across
        XCTAssertEqual(point?.y ?? 0, 500, accuracy: 0.5)   // window spans AppKit y 200…800 → CG 200…800
    }

    func testTopLeftPixelIsTheTopLeftOfTheWindow() {
        let point = capture.screenPoint(forPixel: CGPoint(x: 0, y: 0), primaryHeight: 1000)
        XCTAssertEqual(point?.x ?? 0, 100, accuracy: 0.5)
        XCTAssertEqual(point?.y ?? 0, 200, accuracy: 0.5)   // AppKit y 800 → CG y 1000-800 = 200
    }

    func testAScreenPointMapsBackToItsPixelForListing() {
        // A control at the AppKit centre of the window lists at the centre pixel.
        let pixel = capture.pixel(forScreenPoint: CGPoint(x: 500, y: 500))
        XCTAssertEqual(pixel?.x ?? 0, 800, accuracy: 0.5)
        XCTAssertEqual(pixel?.y ?? 0, 600, accuracy: 0.5)
    }

    func testAZeroSizedCaptureMapsNothing() {
        let empty = ScreenCapture(url: URL(fileURLWithPath: "/tmp/x.png"),
                                  captureFrame: .zero, pixelSize: .zero)
        XCTAssertNil(empty.screenPoint(forPixel: CGPoint(x: 1, y: 1)))
    }

    // MARK: - Claude arguments

    func testToolsAreOfferedOnlyWhenTheQueryWantsThem() {
        let without = ClaudeBackend.arguments(for: Query(text: "x"), config: .defaults, streaming: false)
        XCTAssertFalse(without.contains("--mcp-config"))

        let with = ClaudeBackend.arguments(for: Query(text: "x", tools: true), config: .defaults, streaming: false)
        XCTAssertTrue(with.contains("--mcp-config"))
        let allowed = zip(with, with.dropFirst()).first { $0.0 == "--allowedTools" }?.1 ?? ""
        XCTAssertTrue(allowed.contains("mcp__kestrel__open_app"), allowed)
        XCTAssertTrue(allowed.contains("mcp__kestrel__run_applescript"), allowed)
    }

    func testAToolQuestionWithAScreenshotStillAllowsRead() {
        let arguments = ClaudeBackend.arguments(
            for: Query(text: "do it", screenshot: URL(fileURLWithPath: "/tmp/a.png"), tools: true),
            config: .defaults, streaming: false)
        let allowed = zip(arguments, arguments.dropFirst()).first { $0.0 == "--allowedTools" }?.1 ?? ""
        XCTAssertTrue(allowed.contains("Read"), allowed)
        XCTAssertTrue(allowed.contains("mcp__kestrel__click"), allowed)
    }

    func testTheMCPConfigNamesTheSocketRelay() {
        let json = ClaudeBackend.mcpConfig(socket: URL(fileURLWithPath: "/tmp/mcp.sock"))
        XCTAssertTrue(json.contains("/usr/bin/nc"))
        XCTAssertTrue(json.contains("/tmp/mcp.sock"))
        XCTAssertTrue(json.contains("kestrel"))
    }

    // MARK: - Timeout

    func testAToolQuestionGetsALongerLeash() {
        XCTAssertEqual(Query(text: "x").timeout, 75)
        XCTAssertGreaterThan(Query(text: "x", tools: true).timeout, 75)
    }
}
