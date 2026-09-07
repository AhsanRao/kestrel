import Foundation
import os

/// Keeps `KESTREL.md` up to date from what the user says, without a second model call.
///
/// The file is sent on *every* request, so it has to stay small — which rules out writing down
/// everything and hoping. Only durable first-person facts are kept ("I'm working on the billing
/// rewrite", "I prefer short answers"), one line each, deduplicated, oldest dropped first. Anything
/// read off the screen is never stored: what the user is looking at is not a fact about them.
enum MemoryWriter {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "memory")

    /// The heading facts are filed under.
    static let heading = "## What I've picked up"
    static let maximumFacts = 14
    static let maximumLength = 140

    /// Openings that mean the user is telling Kestrel something about themselves, rather than
    /// asking about the screen.
    static let leads = [
        "i'm working on", "i am working on", "i work on", "i work at", "i'm building",
        "i am building", "my project is", "my name is", "i'm called", "call me",
        "i prefer", "i like", "i don't like", "i hate", "i always", "i usually", "i never",
        "remember that", "remember i", "keep in mind", "for future reference", "from now on",
        "i use", "i'm learning", "i am learning", "my team", "my job", "my role is",
    ]

    /// The fact worth keeping in this sentence, if there is one.
    ///
    /// Deliberately conservative. A false positive puts noise in a file that is sent on every
    /// request for ever; a false negative costs nothing, because the user can say it again or edit
    /// the file by hand.
    static func fact(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        guard lowered.count >= 8, lowered.count <= maximumLength * 2 else { return nil }
        // A question is a question, even one that starts "I always wonder".
        guard !trimmed.hasSuffix("?") else { return nil }
        guard leads.contains(where: { lowered.hasPrefix($0) || lowered.contains(" \($0)") })
        else { return nil }

        var sentence = trimmed
        if let stop = sentence.firstIndex(where: { $0 == "." || $0 == "!" }) {
            sentence = String(sentence[..<stop])
        }
        sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sentence.count >= 8 else { return nil }
        return String(sentence.prefix(maximumLength))
    }

    /// Files a fact under its heading, creating the section if this is the first one.
    static func remember(_ fact: String, in memory: String) -> String {
        let line = "- \(fact)"
        guard !contains(fact, in: memory) else { return memory }

        var text = memory
        if !text.contains(heading) {
            if !text.hasSuffix("\n") { text += "\n" }
            text += "\n\(heading)\n\n"
        }
        guard let range = text.range(of: heading) else { return memory }

        // Insert at the top of the section: the most recent thing said is the most likely to matter.
        let afterHeading = text.index(range.upperBound, offsetBy: 0)
        var head = String(text[..<afterHeading])
        var tail = String(text[afterHeading...])
        while tail.hasPrefix("\n") { tail.removeFirst() }
        head += "\n\n\(line)\n"
        text = head + tail

        return trim(text)
    }

    /// Keeps the section inside its budget, dropping the oldest lines from the bottom.
    static func trim(_ memory: String) -> String {
        guard let range = memory.range(of: heading) else { return memory }
        let head = String(memory[..<range.upperBound])
        let rest = String(memory[range.upperBound...])
        var kept: [String] = []
        var overflow: [String] = []
        for line in rest.components(separatedBy: "\n") {
            guard line.hasPrefix("- ") else { overflow.append(line); continue }
            if kept.count < maximumFacts { kept.append(line) }
        }
        let others = overflow.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return head + "\n\n" + kept.joined(separator: "\n")
            + (others.isEmpty ? "\n" : "\n\n" + others.joined(separator: "\n") + "\n")
    }

    static func contains(_ fact: String, in memory: String) -> Bool {
        let needle = normalize(fact)
        return memory.components(separatedBy: "\n")
            .filter { $0.hasPrefix("- ") }
            .contains { normalize(String($0.dropFirst(2))) == needle }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!"))
    }

    // MARK: - Disk

    /// Records anything durable in the question. Called after an answer, on a background queue.
    static func note(question: String) {
        guard let fact = fact(in: question) else { return }
        let memory = MemoryStore.read()
        let updated = remember(fact, in: memory)
        guard updated != memory else { return }
        MemoryStore.write(updated)
        log.info("remembered a fact from the question")
    }
}
