import XCTest
@testable import Kestrel

final class OnboardingTests: XCTestCase {
    /// Built against a config, because what counts as required depends on it — Accessibility is
    /// mandatory for the default bare-chord hotkey and merely recommended for a keyed one.
    private func report(_ ok: [DependencyCheck.Requirement: Bool],
                        config: Config = .defaults) -> DependencyCheck.Report {
        DependencyCheck.Report(items: DependencyCheck.Requirement.allCases.map {
            DependencyCheck.Item(requirement: $0, ok: ok[$0] ?? true, detail: "",
                                 isRequired: $0.isRequired(for: config))
        })
    }

    /// A keyed ask hotkey, for the cases where Accessibility is not the thing under test.
    private var keyedHotkeys: Config {
        var config = Config.defaults
        config.hotkeys.ask = HotkeyBinding(keyCode: 0, modifiers: ["control", "command"])
        return config
    }

    // MARK: - What counts as ready

    func testCodexIsOptional() {
        let missing = report([.codex: false])
        XCTAssertTrue(missing.readyToUse, "Kestrel answers questions without Codex")
        XCTAssertFalse(missing.allGood)
    }

    /// The default ask hotkey is a bare ⌘⌥ chord, which Carbon cannot register — it is watched
    /// through an event tap, so without Accessibility it never fires and the app cannot be used at
    /// all. Treating it as optional meant a revoked grant left Kestrel silently dead: no hotkey, and
    /// no setup window either, because nothing "required" was missing.
    func testAccessibilityIsRequiredForTheDefaultChordHotkey() {
        XCTAssertTrue(DependencyCheck.Requirement.accessibility.isRequired(for: .defaults))
        XCTAssertFalse(report([.accessibility: false]).readyToUse)
    }

    /// Bound to an ordinary keyed shortcut, asking works without the grant; dictation and circling
    /// still want it, so it stays on the list as recommended rather than blocking.
    func testAccessibilityIsOptionalForAKeyedHotkey() {
        let config = keyedHotkeys
        XCTAssertFalse(DependencyCheck.Requirement.accessibility.isRequired(for: config))
        XCTAssertTrue(report([.accessibility: false], config: config).readyToUse)
    }

    /// The whole point of the rule: a grant that disappears brings the window back by itself.
    func testLosingAccessibilityBringsTheSetupWindowBack() {
        var config = Config.defaults
        config.onboardingCompleted = true
        XCTAssertTrue(OnboardingModel.shouldPresent(config: config,
                                                    report: report([.accessibility: false])))
    }

    func testAMissingMicrophoneBlocksEverything() {
        XCTAssertFalse(report([.microphone: false]).readyToUse)
    }

    func testEachRequiredPieceBlocksOnItsOwn() {
        for requirement in DependencyCheck.Requirement.allCases
        where requirement.isRequired(for: .defaults) {
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
            // `speech` is the summary row: satisfied by the OS on Apple's engine, and on whisper it
            // says to read the two rows under it, which carry the commands. Nothing of its own to
            // do. `voice` has a way forward, but it is a button rather than a command — the Kokoro
            // download runs in the app (see `KokoroRowAction`), and skipping it just uses a macOS
            // voice.
            guard !isPermission, requirement != .speech, requirement != .voice else { continue }
            XCTAssertNotNil(DependencyCheck.fixCommand(for: requirement),
                            "\(requirement) offers neither a prompt nor a command")
        }
    }

    /// The report lists what the configured engine actually needs. Apple's engine is built into
    /// macOS, so the two whisper rows would be asking the user to install something for an engine
    /// they are not using — a checklist that cannot be completed is worse than a short one.
    func testTheLiveReportCoversWhatTheChosenEngineNeeds() {
        var config = Config.defaults
        config.transcriptionEngine = .whisper
        let onWhisper = DependencyCheck.run(config: config)
        for requirement in DependencyCheck.Requirement.allCases {
            XCTAssertNotNil(onWhisper.item(requirement), "\(requirement) missing on whisper")
            XCTAssertFalse(onWhisper.item(requirement)?.detail.isEmpty ?? true,
                           "\(requirement) has no detail")
        }

        config.transcriptionEngine = .apple
        let onApple = DependencyCheck.run(config: config)
        for requirement in DependencyCheck.Requirement.allCases {
            // The whisper rows are shown only when whisper is the engine that will actually run —
            // which, on a Mac too old for Apple's, it still is.
            let isWhisperRow = requirement == .whisperBinary || requirement == .whisperModel
            let expected = !isWhisperRow || config.effectiveTranscriptionEngine == .whisper
            XCTAssertEqual(onApple.item(requirement) != nil, expected, "\(requirement)")
        }
        XCTAssertNotNil(onApple.item(.speech)?.detail, "the summary row is always shown")
    }
}
