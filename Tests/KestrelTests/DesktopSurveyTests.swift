import AppKit
import XCTest
@testable import Kestrel

/// Window lists come back from CoreGraphics full of things a person would not call a window:
/// shadows, palettes, menu-bar layers. The filtering is what makes the list worth sending.
final class DesktopSurveyTests: XCTestCase {
    private func entry(pid: pid_t, app: String, title: String?, x: Double, y: Double,
                       w: Double, h: Double, layer: Int = 0) -> [String: Any] {
        var dict: [String: Any] = [
            kCGWindowLayer as String: layer,
            kCGWindowOwnerPID as String: pid,
            kCGWindowOwnerName as String: app,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h],
        ]
        if let title { dict[kCGWindowName as String] = title }
        return dict
    }

    func testNormalWindowsSurvive() {
        let windows = DesktopSurvey.windows(
            from: [entry(pid: 1, app: "Safari", title: "Pricing", x: 0, y: 0, w: 1200, h: 800)],
            frontmostPID: nil)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].app, "Safari")
        XCTAssertEqual(windows[0].title, "Pricing")
    }

    func testMenuBarAndOverlayLayersAreDropped() {
        let windows = DesktopSurvey.windows(
            from: [entry(pid: 1, app: "Safari", title: "x", x: 0, y: 0, w: 900, h: 700, layer: 25)],
            frontmostPID: nil)
        XCTAssertTrue(windows.isEmpty)
    }

    func testPalettesAndTooltipsAreTooSmallToCount() {
        let windows = DesktopSurvey.windows(
            from: [entry(pid: 1, app: "Figma", title: "Colour", x: 0, y: 0, w: 120, h: 90)],
            frontmostPID: nil)
        XCTAssertTrue(windows.isEmpty)
    }

    func testTheFrontmostWindowIsListedFirstAndMarked() {
        let windows = DesktopSurvey.windows(from: [
            entry(pid: 1, app: "Safari", title: "Big", x: 0, y: 0, w: 2000, h: 1200),
            entry(pid: 2, app: "Notes", title: "Small", x: 0, y: 0, w: 600, h: 400),
        ], frontmostPID: 2)
        XCTAssertEqual(windows.first?.app, "Notes")
        XCTAssertTrue(windows.first?.isFrontmost ?? false)
        XCTAssertFalse(windows.last?.isFrontmost ?? true)
    }

    func testOtherwiseBiggestComesFirst() {
        let windows = DesktopSurvey.windows(from: [
            entry(pid: 1, app: "Notes", title: "Small", x: 0, y: 0, w: 600, h: 400),
            entry(pid: 2, app: "Safari", title: "Big", x: 0, y: 0, w: 2000, h: 1200),
        ], frontmostPID: nil)
        XCTAssertEqual(windows.first?.app, "Safari")
    }

    func testTheListIsCapped() {
        let many = (1...40).map {
            entry(pid: pid_t($0), app: "App\($0)", title: "w", x: 0, y: 0, w: 800, h: 600)
        }
        XCTAssertEqual(DesktopSurvey.windows(from: many, frontmostPID: nil).count,
                       DesktopSurvey.maximumWindows)
    }

    func testAWindowWithNoTitleFallsBackToItsApp() {
        let windows = DesktopSurvey.windows(
            from: [entry(pid: 1, app: "Terminal", title: nil, x: 0, y: 0, w: 800, h: 600)],
            frontmostPID: nil)
        XCTAssertEqual(windows.first?.listing, "Terminal [800×600]")
    }

    func testBundleIdsAreAttachedWhenKnown() {
        let windows = DesktopSurvey.windows(
            from: [entry(pid: 7, app: "Safari", title: "x", x: 0, y: 0, w: 800, h: 600)],
            frontmostPID: nil, bundleIDs: [7: "com.apple.Safari"])
        XCTAssertEqual(windows.first?.bundleID, "com.apple.Safari")
    }

    func testMalformedEntriesAreSkippedRatherThanCrashing() {
        let windows = DesktopSurvey.windows(from: [[:], ["nonsense": 1]], frontmostPID: nil)
        XCTAssertTrue(windows.isEmpty)
    }

    // MARK: - Summary

    func testTheSummaryNamesWindowsAndApps() {
        let window = DesktopSurvey.Window(title: "Pricing", app: "Safari", bundleID: nil,
                                          frame: CGRect(x: 0, y: 0, width: 900, height: 700),
                                          isFrontmost: true)
        let summary = try? XCTUnwrap(DesktopSurvey.summary(windows: [window], apps: ["Safari", "Notes"]))
        XCTAssertTrue(summary?.contains("Safari — Pricing") ?? false)
        XCTAssertTrue(summary?.contains("in front") ?? false)
        XCTAssertTrue(summary?.contains("Apps running: Safari, Notes") ?? false)
    }

    func testNothingOpenMeansNoSummary() {
        XCTAssertNil(DesktopSurvey.summary(windows: [], apps: []))
    }

    // MARK: - When it is gathered

    func testDesktopQuestionsAskForIt() {
        for question in ["what else is open?", "switch to Slack", "which apps are running",
                         "is Figma in my other window?"] {
            XCTAssertTrue(DesktopContextDetector.needsDesktopContext(question), question)
        }
    }

    func testOrdinaryScreenQuestionsDoNot() {
        for question in ["what is this?", "explain this error", "how do I export a PDF?"] {
            XCTAssertFalse(DesktopContextDetector.needsDesktopContext(question), question)
        }
    }

    func testTheSummaryReachesThePrompt() {
        let prompt = PromptBuilder.build(Query(text: "what else is open?", desktop: "Windows open right now:\n- Safari"))
        XCTAssertTrue(prompt.contains("Windows open right now"))
    }
}
