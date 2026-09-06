import Foundation

/// Pulls the answer text out of `claude -p --output-format stream-json` as it arrives.
///
/// The stream is one JSON object per line. Only two shapes matter: the partial `text_delta`
/// events, which arrive while the model is still writing, and the final `result` envelope.
/// Everything else — tool calls, system init, usage — is ignored.
struct StreamParser {
    private(set) var text = ""
    private(set) var finalResult: String?
    private(set) var isError = false

    /// Returns the newly added text, if this line carried any.
    mutating func consume(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch object["type"] as? String {
        case "stream_event":
            guard let event = object["event"] as? [String: Any],
                  event["type"] as? String == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta",
                  let chunk = delta["text"] as? String, !chunk.isEmpty
            else { return nil }
            text += chunk
            return chunk

        case "result":
            isError = (object["is_error"] as? Bool) ?? false
            if let result = object["result"] as? String { finalResult = result }
            return nil

        default:
            return nil
        }
    }

    /// What the CLI reported as a failure, if it reported one. Never the answer: the quota check
    /// reads this, and reading the answer instead is what made a good reply end in "usage limit
    /// reached".
    var errorMessage: String? {
        guard isError else { return nil }
        let message = finalResult ?? text
        return message.isEmpty ? nil : message
    }

    /// The best text available: the final envelope when it arrived, else what was streamed.
    var answer: String {
        let candidate = finalResult ?? text
        return BackendSupport.cleanAnswer(candidate)
    }
}

/// Turns a stream of fragments into whole sentences, so speech can start on the first one instead
/// of waiting for the last. Speaking half a clause sounds broken; speaking a sentence does not.
struct SentenceAccumulator {
    private var buffer = ""

    /// Minimum length before a sentence is worth speaking on its own.
    static let minimumLength = 12

    mutating func push(_ fragment: String) -> [String] {
        buffer += fragment
        var out: [String] = []
        while let sentence = takeSentence() { out.append(sentence) }
        return out
    }

    /// Whatever is left when the model stops writing.
    mutating func flush() -> String? {
        let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return remainder.isEmpty ? nil : remainder
    }

    private mutating func takeSentence() -> String? {
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let character = buffer[index]
            let next = buffer.index(after: index)
            if terminators.contains(character) {
                // "3.5" and "e.g." are not sentence ends; a digit or letter straight after a full
                // stop means the sentence is still going.
                let followedByBreak = next == buffer.endIndex || buffer[next] == " " || buffer[next] == "\n"
                if followedByBreak {
                    let sentence = String(buffer[buffer.startIndex..<next])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let rest = String(buffer[next...])
                    if sentence.count >= SentenceAccumulator.minimumLength {
                        buffer = rest
                        return sentence.isEmpty ? nil : sentence
                    }
                }
            }
            index = next
        }
        return nil
    }
}
