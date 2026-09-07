import XCTest
@testable import Kestrel

/// Opening an app is the only thing Kestrel still does to the Mac, so the test that matters is the
/// one that keeps it from doing anything else.
final class AppLauncherTests: XCTestCase {
    func testAnAppThatIsNotInstalledIsNotAnInstruction() {
        XCTAssertNil(AppLauncher.requestedApp(in: "open Thingamajig Pro"))
    }

    func testQuestionsAboutTheScreenAreNotLaunches() {
        for question in ["open the File menu",
                         "how do I open a new tab",
                         "what is this window for",
                         "open it"] {
            XCTAssertNil(AppLauncher.requestedApp(in: question), question)
        }
    }

    /// Finder is on every Mac, so this is the one real name that can be asserted anywhere.
    func testAnInstalledAppIsRecognisedByItsVisibleName() {
        guard AppLauncher.installedApp(named: "finder") != nil else {
            return XCTFail("Finder should be installable on any Mac")
        }
        XCTAssertEqual(AppLauncher.requestedApp(in: "open Finder")?.name, "Finder")
        XCTAssertEqual(AppLauncher.requestedApp(in: "switch to the Finder app")?.name, "Finder")
    }

    /// "Open Spotify and play something" opens Spotify. The rest was removed, and half-doing it
    /// would be worse than being clear about that.
    func testTheAppIsTakenFromTheStartOfALongerRequest() {
        XCTAssertEqual(AppLauncher.requestedApp(in: "open Finder and show my downloads")?.name,
                       "Finder")
    }
}
