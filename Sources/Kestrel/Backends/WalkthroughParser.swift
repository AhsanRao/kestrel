import Foundation

/// Turns whatever the model actually returned into a `Walkthrough`, or nothing.
///
/// Spec §8.15: parse defensively. Models wrap JSON in prose or code fences, renumber steps badly,
/// and occasionally emit a single step object instead of the envelope. None of that may crash the
/// overlay — a walkthrough that cannot be understood falls back to a plain spoken answer.
enum WalkthroughParser {
    static let maximumSteps = 15

    static func parse(_ raw: String) -> Walkthrough? {
        guard let json = extractObject(from: raw), let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        guard var walkthrough = try? decoder.decode(Walkthrough.self, from: data) else { return nil }

        walkthrough.steps = sanitize(walkthrough.steps)
        guard !walkthrough.steps.isEmpty else { return nil }
        walkthrough.goal = walkthrough.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        return walkthrough
    }

    /// Drops junk steps, renumbers from 1, and enforces the step cap.
    static func sanitize(_ steps: [WalkthroughStep]) -> [WalkthroughStep] {
        steps
            .filter { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .filter { $0.target.w > 0 && $0.target.h > 0 }
            .prefix(maximumSteps)
            .enumerated()
            .map { index, step in
                var copy = step
                copy.n = index + 1
                copy.instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.shape = ["rect", "circle"].contains(step.shape.lowercased()) ? step.shape.lowercased() : "rect"
                return copy
            }
    }

    /// Finds the outermost JSON object in a string that may also contain fences or commentary.
    static func extractObject(from raw: String) -> String? {
        let text = BackendSupport.cleanAnswer(raw)
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var insideString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" && insideString {
                escaped = true
            } else if character == "\"" {
                insideString.toggle()
            } else if !insideString {
                if character == "{" { depth += 1 }
                if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Spoken fallback when the coordinates are unusable but the instructions are not.
    static func spokenSummary(_ walkthrough: Walkthrough) -> String {
        var lines: [String] = []
        if !walkthrough.goal.isEmpty { lines.append(walkthrough.goal) }
        lines += walkthrough.steps.map { "\($0.n). \($0.instruction)" }
        if walkthrough.needs_more == true {
            lines.append("There are more steps after this screen.")
        }
        return lines.joined(separator: "\n")
    }
}
