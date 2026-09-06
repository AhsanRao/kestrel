import XCTest
@testable import Kestrel

final class SpeechAndInjectionTests: XCTestCase {

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
        XCTAssertEqual(Query(text: "x", mode: .ask).timeout, 120)
        XCTAssertEqual(Query(text: "x", mode: .dictationCleanup).timeout, 30)
    }

    // MARK: - Walkthrough JSON (v2 schema, parsed defensively)

    func testWalkthroughJSONDecodes() throws {
        let json = #"""
        {"goal":"Export as PDF","needs_more":false,
         "steps":[{"n":1,"instruction":"Open the File menu","target":{"x":10,"y":8,"w":60,"h":24},"shape":"rect"}]}
        """#
        let walkthrough = try JSONDecoder().decode(Walkthrough.self, from: Data(json.utf8))
        XCTAssertEqual(walkthrough.steps.count, 1)
        XCTAssertEqual(walkthrough.steps[0].target.w, 60)
    }
}
