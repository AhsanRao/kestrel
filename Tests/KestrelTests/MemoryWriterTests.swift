import XCTest
@testable import Kestrel

/// The memory file is sent on every single request, so what goes in it matters more than what is
/// left out. These are mostly tests that Kestrel keeps its mouth shut.
final class MemoryWriterTests: XCTestCase {
    func testFirstPersonStatementsAreWorthKeeping() {
        for said in ["I'm working on a voice assistant for macOS",
                     "I prefer short answers",
                     "Remember that I use Swift, not Objective-C",
                     "My name is Ash"] {
            XCTAssertNotNil(MemoryWriter.fact(in: said), said)
        }
    }

    func testQuestionsAboutTheScreenAreNot() {
        for said in ["What is this window for?",
                     "How do I export this as a PDF?",
                     "Is there an error in this code?",
                     "Summarise this page",
                     "I always wonder what that button does?"] {
            XCTAssertNil(MemoryWriter.fact(in: said), said)
        }
    }

    func testAFactIsCutAtTheEndOfItsSentence() {
        let fact = MemoryWriter.fact(in: "I prefer short answers. What is on my screen right now")
        XCTAssertEqual(fact, "I prefer short answers")
    }

    func testAVeryLongRambleIsNotStored() {
        XCTAssertNil(MemoryWriter.fact(in: "I prefer " + String(repeating: "words ", count: 80)))
    }

    // MARK: - Writing

    private let seed = "# Kestrel memory\n\n## Profile\n\n- Name: Ash\n"

    func testAFactIsFiledUnderItsHeading() {
        let updated = MemoryWriter.remember("I prefer short answers", in: seed)
        XCTAssertTrue(updated.contains(MemoryWriter.heading))
        XCTAssertTrue(updated.contains("- I prefer short answers"))
        XCTAssertTrue(updated.contains("- Name: Ash"), "the rest of the file is left alone")
    }

    func testTheSameFactIsNotStoredTwice() {
        let once = MemoryWriter.remember("I prefer short answers", in: seed)
        let twice = MemoryWriter.remember("I prefer short answers.", in: once)
        XCTAssertEqual(once, twice)
    }

    /// It is sent on every request; it cannot grow for ever.
    func testTheSectionStopsGrowing() {
        var memory = seed
        for index in 1...(MemoryWriter.maximumFacts + 6) {
            memory = MemoryWriter.remember("I use tool number \(index)", in: memory)
        }
        let facts = memory.components(separatedBy: "\n").filter { $0.hasPrefix("- I use tool") }
        XCTAssertEqual(facts.count, MemoryWriter.maximumFacts)
        // Newest first: the oldest are the ones dropped.
        XCTAssertTrue(facts.first?.contains("number \(MemoryWriter.maximumFacts + 6)") ?? false)
    }
}

final class OnboardingInterviewTests: XCTestCase {
    func testTheProfileIsWrittenFromTheAnswers() {
        let memory = InterviewModel.memory(name: "Ash", role: "iOS engineer",
                                           project: "A voice assistant", style: .brief,
                                           existing: "# Kestrel memory\n\n## Profile\n\n- Name:\n")
        XCTAssertTrue(memory.contains("- Name: Ash"))
        XCTAssertTrue(memory.contains("- Role: iOS engineer"))
        XCTAssertTrue(memory.contains("- A voice assistant"))
        XCTAssertTrue(memory.contains("as short as possible"))
    }

    /// The user may have written in the file before ever seeing this window.
    func testWhatTheUserWroteThemselvesSurvives() {
        let existing = "# Kestrel memory\n\n## Profile\n\n- Name:\n\n## Notes\n\n- Keep it small\n"
        let memory = InterviewModel.memory(name: "Ash", role: "", project: "", style: .normal,
                                           existing: existing)
        XCTAssertTrue(memory.contains("## Notes"))
        XCTAssertTrue(memory.contains("- Keep it small"))
    }

    func testSkippingEverythingIsAllowed() {
        let model = InterviewModel()
        XCTAssertTrue(model.isEmpty)
        model.name = "Ash"
        XCTAssertFalse(model.isEmpty)
    }
}
