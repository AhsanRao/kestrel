import XCTest
@testable import Kestrel

/// Skill files are user-authored and read on the ask path, so the library has to tolerate whatever
/// is in the folder and never make a question slower than it has to be.
final class SkillLibraryTests: XCTestCase {
    private var written: [URL] = []

    override func setUpWithError() throws {
        try Paths.bootstrap()
        try FileManager.default.createDirectory(at: Paths.skills, withIntermediateDirectories: true)
        SkillLibrary.invalidate()
    }

    override func tearDown() {
        written.forEach { try? FileManager.default.removeItem(at: $0) }
        written.removeAll()
        SkillLibrary.invalidate()
    }

    @discardableResult
    private func write(_ name: String, _ body: String) throws -> URL {
        let url = Paths.skills.appendingPathComponent("\(name).md")
        try body.write(to: url, atomically: true, encoding: .utf8)
        written.append(url)
        return url
    }

    private var testBundleID: String { "dev.0xash.kestrel.tests.\(UUID().uuidString)" }

    func testNotesForAnAppCombineTheGeneralAndTheSpecific() throws {
        let bundleID = testBundleID
        try write("default", "Always be brief.")
        try write(bundleID, "This is my staging cluster.")

        let notes = try XCTUnwrap(SkillLibrary.notes(forBundleID: bundleID))
        XCTAssertTrue(notes.contains("Always be brief."))
        XCTAssertTrue(notes.contains("This is my staging cluster."))
        XCTAssertTrue(notes.contains(bundleID), "the app's notes should be labelled as such")
    }

    func testAnAppWithNoFileStillGetsTheGeneralNotes() throws {
        try write("default", "Always be brief.")
        let notes = try XCTUnwrap(SkillLibrary.notes(forBundleID: testBundleID))
        XCTAssertEqual(notes, "Always be brief.")
    }

    func testNoFilesAtAllMeansNoNotes() {
        let defaultFile = Paths.skills.appendingPathComponent("default.md")
        let backup = try? Data(contentsOf: defaultFile)
        try? FileManager.default.removeItem(at: defaultFile)
        defer { if let backup { try? backup.write(to: defaultFile) } }
        SkillLibrary.invalidate()

        XCTAssertNil(SkillLibrary.notes(forBundleID: testBundleID))
    }

    func testAMissingFrontmostAppIsFine() throws {
        try write("default", "Always be brief.")
        XCTAssertEqual(SkillLibrary.notes(forBundleID: nil), "Always be brief.")
    }

    // MARK: - Content handling

    func testCommentLinesAreStripped() {
        let stripped = SkillLibrary.strip("<!-- a note to self -->\nKeep it short.\n")
        XCTAssertEqual(stripped, "Keep it short.")
    }

    func testBlankRunsAreCollapsed() {
        XCTAssertEqual(SkillLibrary.strip("one\n\n\n\n\ntwo"), "one\n\ntwo")
    }

    func testAFileOfOnlyCommentsCountsAsEmpty() throws {
        let bundleID = testBundleID
        try write(bundleID, "<!-- nothing yet -->\n\n")
        XCTAssertNil(SkillLibrary.read(named: bundleID))
    }

    func testARunawayFileIsTruncatedRatherThanSentWhole() throws {
        let bundleID = testBundleID
        try write(bundleID, String(repeating: "x", count: SkillLibrary.maximumCharacters * 3))
        let text = try XCTUnwrap(SkillLibrary.read(named: bundleID))
        XCTAssertEqual(text.count, SkillLibrary.maximumCharacters)
    }

    // MARK: - Caching

    func testEditingAFileTakesEffectWithoutARestart() throws {
        let bundleID = testBundleID
        try write(bundleID, "first version")
        XCTAssertEqual(SkillLibrary.read(named: bundleID), "first version")

        // A later modification date is what invalidates the cache.
        let url = Paths.skills.appendingPathComponent("\(bundleID).md")
        try "second version".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                              ofItemAtPath: url.path)
        XCTAssertEqual(SkillLibrary.read(named: bundleID), "second version")
    }

    // MARK: - Prompt

    func testNotesReachThePrompt() {
        let query = Query(text: "what is this?", skills: "Deploys go through Vercel.")
        let prompt = PromptBuilder.build(query)
        XCTAssertTrue(prompt.contains("Deploys go through Vercel."))
        XCTAssertTrue(prompt.contains("Question: what is this?"))
    }

    func testNoNotesMeansNothingExtraInThePrompt() {
        XCTAssertFalse(PromptBuilder.build(Query(text: "hi")).contains("keep in mind"))
        XCTAssertFalse(PromptBuilder.build(Query(text: "hi", skills: "")).contains("keep in mind"))
    }

    func testTheStarterFilesExplainTheFormat() {
        XCTAssertTrue(SkillLibrary.readmeTemplate.contains("<bundle id>.md"))
        XCTAssertTrue(SkillLibrary.readmeTemplate.contains("osascript"))
        XCTAssertFalse(SkillLibrary.defaultTemplate.isEmpty)
    }
}
