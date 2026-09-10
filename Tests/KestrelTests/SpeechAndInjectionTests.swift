import AVFoundation
import XCTest
@testable import Kestrel

final class SpeechAndInjectionTests: XCTestCase {

    // MARK: - Voice ranking

    func testAPersonalVoiceOutranksEveryInstalledVoice() {
        // It reports `.default` quality, so only the explicit check keeps it off the bottom.
        let personal = SystemSpeaker.rank(quality: .default, name: "Ahsan\u{2019}s Personal Voice",
                                         language: "en-US", isPersonal: true)
        let premium = SystemSpeaker.rank(quality: .premium, name: "Zoe", language: "en-US",
                                        isPersonal: false)
        XCTAssertGreaterThan(personal, premium)
    }

    func testPremiumOutranksEnhancedOutranksCompact() {
        let premium = SystemSpeaker.rank(quality: .premium, name: "Zoe", language: "en-US", isPersonal: false)
        let enhanced = SystemSpeaker.rank(quality: .enhanced, name: "Zoe", language: "en-US", isPersonal: false)
        let compact = SystemSpeaker.rank(quality: .default, name: "Zoe", language: "en-US", isPersonal: false)
        XCTAssertGreaterThan(premium, enhanced)
        XCTAssertGreaterThan(enhanced, compact)
    }

    func testAPreferredNameBreaksATieWithinTheSameQuality() {
        let ava = SystemSpeaker.rank(quality: .premium, name: "Ava", language: "en-US", isPersonal: false)
        let unknown = SystemSpeaker.rank(quality: .premium, name: "Grandma", language: "en-US", isPersonal: false)
        XCTAssertGreaterThan(ava, unknown)
    }

    // MARK: - Kokoro voices

    /// Indices come from the model's `speaker2id` metadata, not from any order you could guess.
    /// A wrong one does not fail — it speaks in a stranger's voice — so they are pinned.
    func testKokoroSpeakerIDsMatchTheModelMetadata() {
        XCTAssertEqual(KokoroVoice.named("af_heart").speakerID, 3)
        XCTAssertEqual(KokoroVoice.named("af_sarah").speakerID, 9)
        XCTAssertEqual(KokoroVoice.named("am_michael").speakerID, 16)
        XCTAssertEqual(KokoroVoice.named("am_puck").speakerID, 18)
    }

    func testTheDefaultKokoroVoiceIsHeart() {
        XCTAssertEqual(KokoroVoice.default.id, "af_heart")
        XCTAssertEqual(Config.defaults.kokoroVoice, "af_heart")
    }

    /// A hand-edited config naming an unshipped voice must still speak.
    func testAnUnknownKokoroVoiceFallsBackToTheDefault() {
        XCTAssertEqual(KokoroVoice.named("bf_emma"), KokoroVoice.default)
        XCTAssertEqual(KokoroVoice.named("").id, "af_heart")
    }

    /// Skipping the download is supported, so the system engine must stay reachable.
    func testVoiceEngineDefaultsToKokoroButSystemIsSelectable() {
        XCTAssertEqual(Config.defaults.voiceEngine, .kokoro)
        XCTAssertTrue(Config.VoiceEngine.allCases.contains(.system))
    }

    // MARK: - Markdown stripping for speech

    func testHeadersAndBulletsAreSpokenAsProse() {
        let markdown = """
        ## Export as PDF

        - Open the File menu
        - Choose Export
        """
        let spoken = SpeechOutput.strippedForSpeech(markdown)
        XCTAssertFalse(spoken.contains("#"))
        XCTAssertFalse(spoken.contains("- "))
        XCTAssertTrue(spoken.hasPrefix("Export as PDF"))
        XCTAssertTrue(spoken.contains("Open the File menu"))
    }

    func testCodeFencesAreNotSpoken() {
        let markdown = "Run this:\n```bash\nbrew install whisper-cpp\n```\nThen relaunch."
        let spoken = SpeechOutput.strippedForSpeech(markdown)
        XCTAssertFalse(spoken.contains("brew install"))
        XCTAssertTrue(spoken.contains("Then relaunch."))
    }

    func testEmphasisAndLinksAreUnwrapped() {
        let spoken = SpeechOutput.strippedForSpeech("Press **Export**, then see [the docs](https://x.dev).")
        XCTAssertEqual(spoken, "Press Export, then see the docs.")
    }

    func testEmDashBecomesAPause() {
        XCTAssertEqual(SpeechOutput.strippedForSpeech("Ready — press the key."), "Ready, press the key.")
    }

    // MARK: - Terminal safety (spec §8.10)

    func testNewlinesCollapseInTerminals() {
        let dictated = "list the files\nrm -rf /tmp/x\n"
        let injected = TextInjector.sanitize(dictated, frontmostBundleID: "com.apple.Terminal")
        XCTAssertFalse(injected.contains("\n"))
        XCTAssertEqual(injected, "list the files rm -rf /tmp/x")
    }

    func testEveryKnownTerminalIsCovered() {
        for bundleID in ["com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty"] {
            XCTAssertFalse(TextInjector.sanitize("a\nb", frontmostBundleID: bundleID).contains("\n"), bundleID)
        }
    }

    func testNewlinesSurviveInNormalApps() {
        let injected = TextInjector.sanitize("first line\nsecond line", frontmostBundleID: "com.apple.TextEdit")
        XCTAssertEqual(injected, "first line\nsecond line")
    }

    func testUnknownFrontmostAppKeepsNewlines() {
        XCTAssertEqual(TextInjector.sanitize("a\nb", frontmostBundleID: nil), "a\nb")
    }

    // MARK: - Prompt assembly

    func testAskPromptCarriesTheScreenshotPathForClaude() {
        let query = Query(text: "what is this?", screenshot: URL(fileURLWithPath: "/tmp/shot.png"))
        let prompt = PromptBuilder.build(query)
        XCTAssertTrue(prompt.contains("/tmp/shot.png"))
        XCTAssertTrue(prompt.contains("Question: what is this?"))
    }

    func testCodexPromptOmitsThePathBecauseTheImageIsAttached() {
        let query = Query(text: "what is this?", screenshot: URL(fileURLWithPath: "/tmp/shot.png"))
        let prompt = PromptBuilder.build(query, mentionScreenshotPath: false)
        XCTAssertFalse(prompt.contains("/tmp/shot.png"))
        XCTAssertTrue(prompt.contains("Question: what is this?"))
    }

    func testCleanupPromptEndsWithTheDictatedText() {
        let prompt = PromptBuilder.build(Query(text: "hello there", mode: .dictationCleanup))
        XCTAssertTrue(prompt.hasSuffix("hello there"))
    }

    func testTimeoutsMatchTheSpec() {
        XCTAssertEqual(Query(text: "x", mode: .ask).timeout, 75)
        XCTAssertEqual(Query(text: "x", mode: .dictationCleanup).timeout, 20)
    }
}

/// The pause that ends a live dictation. Pure timing, so none of it waits for real seconds.
final class SilenceWatchTests: XCTestCase {
    private let now = Date()

    func testATakeThatHasHeardNothingNeverEndsItself() {
        // Both clocks sit in the distant future until the first sound: the user may still be
        // gathering their thoughts, and ending the take under them is worse than waiting.
        XCTAssertFalse(SilenceWatch.isQuiet(sound: .distantFuture, words: .distantFuture,
                                            now: now, seconds: 2.5))
    }

    func testAQuietRoomEndsTheTakeOnceTheTranscriberHasCaughtUp() {
        XCTAssertTrue(SilenceWatch.isQuiet(sound: now.addingTimeInterval(-3),
                                           words: now.addingTimeInterval(-1),
                                           now: now, seconds: 2.5))
    }

    /// The failure this rule exists for: recognition trails the voice by up to two seconds, and a
    /// take ended on the room alone cut the start of the next sentence off.
    func testItWaitsForWordsStillArriving() {
        XCTAssertFalse(SilenceWatch.isQuiet(sound: now.addingTimeInterval(-3),
                                            words: now.addingTimeInterval(-0.3),
                                            now: now, seconds: 2.5))
    }

    /// A fan, a café, a Mac with its own noise: the room never falls quiet, so the take has to end
    /// on the transcriber going quiet instead.
    func testANoisyRoomStillEnds() {
        XCTAssertTrue(SilenceWatch.isQuiet(sound: now, words: now.addingTimeInterval(-6),
                                           now: now, seconds: 2.5))
    }

    func testTurningThePauseOffMeansItNeverEnds() {
        XCTAssertFalse(SilenceWatch.isQuiet(sound: now.addingTimeInterval(-600),
                                            words: now.addingTimeInterval(-600),
                                            now: now, seconds: 0))
    }
}
