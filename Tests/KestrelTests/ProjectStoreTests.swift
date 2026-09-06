import XCTest
@testable import Kestrel

/// Folder names come from whatever the user said out loud, so the slugging has to cope with
/// punctuation, other alphabets and, most importantly, anything that looks like a path.
final class ProjectStoreTests: XCTestCase {
    private var created: [URL] = []

    override func setUpWithError() throws {
        try Paths.bootstrap()
    }

    override func tearDown() {
        created.forEach { try? FileManager.default.removeItem(at: $0) }
        created.removeAll()
    }

    // MARK: - Slugs

    func testASpokenGoalBecomesAFolderName() {
        XCTAssertEqual(ProjectStore.slug(from: "Research SpaceX competitors"),
                       "research-spacex-competitors")
        XCTAssertEqual(ProjectStore.slug(from: "Export the Q3 report as PDF"),
                       "export-the-q3-report-as-pdf")
    }

    func testPunctuationCollapsesRatherThanRepeating() {
        XCTAssertEqual(ProjectStore.slug(from: "what's  next --- really?"), "what-s-next-really")
    }

    func testLongGoalsAreTrimmedToSomethingUsable() {
        let slug = ProjectStore.slug(from: String(repeating: "word ", count: 40))
        XCTAssertLessThanOrEqual(slug.count, ProjectStore.maximumSlugLength)
        XCTAssertFalse(slug.hasSuffix("-"))
    }

    func testAGoalWithNothingUsableStillGetsAName() {
        XCTAssertEqual(ProjectStore.slug(from: "…"), "task")
        XCTAssertEqual(ProjectStore.slug(from: ""), "task")
    }

    // MARK: - Containment

    func testAPathLikeNameIsRefused() {
        XCTAssertNil(ProjectStore.resolve("../../etc"))
        XCTAssertNil(ProjectStore.resolve("a/b"))
        XCTAssertNil(ProjectStore.resolve(".hidden"))
        XCTAssertNil(ProjectStore.resolve(""))
    }

    func testASluggedGoalCanNeverEscapeTheProjectsFolder() {
        // Even a goal written to look like a path slugs down to something harmless.
        let slug = ProjectStore.slug(from: "../../.ssh/id_rsa")
        XCTAssertFalse(slug.contains("/"))
        XCTAssertFalse(slug.hasPrefix("."))
        let url = try? XCTUnwrap(ProjectStore.resolve(slug))
        XCTAssertTrue(url?.path.hasPrefix(Paths.projects.path) ?? false)
    }

    // MARK: - Creation

    func testCreatingAProjectMakesItsFolderAndMemoryLinks() throws {
        let goal = "kestrel test \(UUID().uuidString.prefix(8))"
        let url = try XCTUnwrap(ProjectStore.create(for: goal))
        created.append(url)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        // Both CLIs read their memory file from the working directory.
        for name in ["CLAUDE.md", "AGENTS.md"] {
            let link = url.appendingPathComponent(name).path
            XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link), name)
        }
    }

    func testASecondTaskWithTheSameGoalGetsItsOwnFolder() throws {
        let goal = "kestrel duplicate \(UUID().uuidString.prefix(8))"
        let first = try XCTUnwrap(ProjectStore.create(for: goal))
        let second = try XCTUnwrap(ProjectStore.create(for: goal))
        created += [first, second]
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasSuffix("-2"))
    }

    func testOutputsIgnoreTheMemoryLinks() throws {
        let url = try XCTUnwrap(ProjectStore.create(for: "kestrel outputs \(UUID().uuidString.prefix(8))"))
        created.append(url)
        XCTAssertTrue(ProjectStore.outputs(in: url).isEmpty)

        try "hello".write(to: url.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectStore.outputs(in: url).map(\.lastPathComponent), ["report.md"])
    }
}
