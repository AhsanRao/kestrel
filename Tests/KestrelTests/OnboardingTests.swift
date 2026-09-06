import XCTest
@testable import Kestrel

final class OnboardingTests: XCTestCase {
    private func report(_ ok: [DependencyCheck.Requirement: Bool]) -> DependencyCheck.Report {
        DependencyCheck.Report(items: DependencyCheck.Requirement.allCases.map {
            DependencyCheck.Item(requirement: $0, ok: ok[$0] ?? true, detail: "")
        })
    }

    // MARK: - What counts as ready

    func testCodexAndAccessibilityAreOptional() {
        let missing = report([.codex: false, .accessibility: false])
        XCTAssertTrue(missing.readyToUse, "Kestrel answers questions without Codex or Accessibility")
        XCTAssertFalse(missing.allGood)
    }

    func testAMissingMicrophoneBlocksEverything() {
        XCTAssertFalse(report([.microphone: false]).readyToUse)
    }

    func testEachRequiredPieceBlocksOnItsOwn() {
        for requirement in DependencyCheck.Requirement.allCases where requirement.isRequired {
            XCTAssertFalse(report([requirement: false]).readyToUse, "\(requirement) should be required")
        }
    }

    // MARK: - When the window appears

    func testItAppearsOnAFirstLaunchEvenWhenEverythingIsInstalled() {
        var config = Config.defaults
        config.onboardingCompleted = false
        XCTAssertTrue(OnboardingModel.shouldPresent(config: config, report: report([:])))
    }

    func testItStaysAwayOnceCompletedAndHealthy() {
        var config = Config.defaults
        config.onboardingCompleted = true
        XCTAssertFalse(OnboardingModel.shouldPresent(config: config, report: report([:])))
    }

    func testItComesBackIfSomethingRequiredGoesMissing() {
        var config = Config.defaults
        config.onboardingCompleted = true
        XCTAssertTrue(OnboardingModel.shouldPresent(config: config, report: report([.whisperBinary: false])))
    }

    func testAnOptionalGapDoesNotDragTheWindowBack() {
        var config = Config.defaults
        config.onboardingCompleted = true
        XCTAssertFalse(OnboardingModel.shouldPresent(config: config, report: report([.codex: false])))
    }

    // MARK: - Content

    func testEveryRequirementExplainsItselfAndHasAWayForward() {
        for requirement in DependencyCheck.Requirement.allCases {
            XCTAssertFalse(requirement.title.isEmpty)
            XCTAssertFalse(requirement.reason.isEmpty, "\(requirement) has no explanation")
            let isPermission: Bool = [.microphone, .screenRecording, .accessibility].contains(requirement)
            XCTAssertTrue(isPermission || DependencyCheck.fixCommand(for: requirement) != nil,
                          "\(requirement) offers neither a prompt nor a command")
        }
    }

    func testOnlyScreenRecordingNeedsARelaunch() {
        let needing = DependencyCheck.Requirement.allCases.filter(\.needsRelaunch)
        XCTAssertEqual(needing, [.screenRecording])
    }

    func testTheLiveReportCoversEveryRequirement() {
        let live = DependencyCheck.run(config: .defaults)
        XCTAssertEqual(live.items.count, DependencyCheck.Requirement.allCases.count)
        for requirement in DependencyCheck.Requirement.allCases {
            XCTAssertNotNil(live.item(requirement))
            XCTAssertFalse(live.item(requirement)?.detail.isEmpty ?? true, "\(requirement) has no detail")
        }
    }
}
