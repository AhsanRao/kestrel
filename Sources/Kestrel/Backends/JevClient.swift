import Foundation
import os

/// One typed question for Jev: yes-or-no, one of a list, or a place on a scale.
struct JevQuestion: Encodable, Equatable {
    enum Kind: Equatable {
        case noul
        /// Option key → what it means. Up to 255.
        case choice([String: String])
        /// Ordered levels, 2 to 10.
        case score([String])
    }

    var instructions: String
    var kind: Kind

    static func yesNo(_ instructions: String) -> JevQuestion { .init(instructions: instructions, kind: .noul) }
    static func oneOf(_ options: [String: String], _ instructions: String) -> JevQuestion {
        .init(instructions: instructions, kind: .choice(options))
    }

    private enum Keys: String, CodingKey { case type, instructions, criteria }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(instructions, forKey: .instructions)
        switch kind {
        case .noul:
            try c.encode("noul", forKey: .type)
        case .choice(let options):
            try c.encode("choice", forKey: .type)
            try c.encode(options, forKey: .criteria)
        case .score(let levels):
            try c.encode("score", forKey: .type)
            try c.encode(levels, forKey: .criteria)
        }
    }
}

/// What came back, keyed the way the questions were.
struct JevAnswers: Decodable {
    struct Answer: Decodable {
        var type: String
        var noul: Double?
        var choice: String?
        var confidence: Double?
        var probabilities: [String: Double]?
        var score: Double?
    }

    var answers: [String: Answer]

    /// The probability that the answer is yes.
    func yes(_ key: String) -> Double? { answers[key]?.noul }

    /// The option picked, and how sure the model is of it.
    func choice(_ key: String) -> (option: String, confidence: Double)? {
        guard let answer = answers[key], let option = answer.choice else { return nil }
        return (option, answer.confidence ?? answer.probabilities?[option] ?? 0)
    }
}

/// Jev, TypeSafe AI's decision model, reached over HTTPS through Vercel's AI Gateway (spec §8.19).
///
/// Not a language model. It is handed a piece of text and a few typed questions about it, and
/// answers each with a probability, in a few hundred milliseconds and for a hundredth of a cent.
/// It cannot write, cannot see a screenshot and cannot pick coordinates — it judges. Every caller
/// keeps the behaviour it had before Jev for when the key is missing or the call fails, so it can
/// only make a decision faster or better, never leave Kestrel without one.
///
/// Only text is sent: the transcript, and what the screen says — never a screenshot. It is off
/// until `jev.apiKey` is set.
enum Jev {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "jev")
    /// Longer than this and the old heuristics would have been the better deal.
    static let timeout: TimeInterval = 2.5

    /// One connection, kept warm: the TLS handshake is most of a cold call.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    /// Blocking; call from a background queue. Nil when Jev is off or anything went wrong —
    /// callers fall back, they do not fail.
    static func ask(_ state: String, _ questions: [String: JevQuestion], config: Config.Jev,
                    label: String = "jev") -> JevAnswers? {
        guard config.isEnabled, let url = URL(string: config.endpoint) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body(model: config.model, state: state, questions: questions)
        let started = Date()
        // The gateway drops the odd call with a 503 that succeeds a moment later. One more try
        // is a few hundred milliseconds; giving up is a model round-trip.
        for attempt in 1...2 {
            switch send(request) {
            case .answers(let answers):
                log.info("\(label, privacy: .public) in \(Int(Date().timeIntervalSince(started) * 1000))ms")
                return answers
            case .retry(let why) where attempt == 1:
                log.error("\(label, privacy: .public) retrying: \(why, privacy: .public)")
            case .retry(let why), .fail(let why):
                log.error("\(label, privacy: .public) failed: \(why, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    private enum Outcome { case answers(JevAnswers), retry(String), fail(String) }

    private static func send(_ request: URLRequest) -> Outcome {
        let done = DispatchSemaphore(value: 0)
        var outcome = Outcome.fail("no response")
        let task = session.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let detail = error?.localizedDescription
                ?? String(decoding: (data ?? Data()).prefix(200), as: UTF8.self)
            if let error { outcome = .retry(error.localizedDescription); return }
            guard let data, status == 200 else {
                outcome = status >= 500 || status == 429 ? .retry("HTTP \(status) \(detail)") : .fail("HTTP \(status) \(detail)")
                return
            }
            do {
                outcome = .answers(try JSONDecoder().decode(JevAnswers.self, from: data))
            } catch {
                outcome = .fail("unreadable: \(error.localizedDescription) in \(detail)")
            }
        }
        task.resume()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            return .fail("timed out after \(Int(timeout * 1000))ms")
        }
        return outcome
    }

    /// A cold call spends most of its time on the TLS handshake. One throwaway question at
    /// launch, and the first real one goes out on a warm connection.
    static func warmUp(config: Config.Jev) {
        guard config.isEnabled else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = ask("ready", ["ok": .yesNo("Is the word 'ready' present?")], config: config, label: "warm-up")
        }
    }

    /// The request as TypeSafe's System One API reads it. Pure, so the shape is unit-tested.
    static func body(model: String, state: String, questions: [String: JevQuestion]) -> Data {
        struct Body: Encodable {
            var model: String
            var state: String
            var questions: [String: JevQuestion]
        }
        return (try? JSONEncoder().encode(Body(model: model, state: state, questions: questions))) ?? Data()
    }
}
