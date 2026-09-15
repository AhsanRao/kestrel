import CoreGraphics
import Foundation
import os

/// One question's worth of doing things: the step budget, the policy, and the screen as it was
/// after the last step. Lives from the moment a question goes to the model until its answer lands.
///
/// Every dependency is a closure so the whole act-observe loop can be tested without a Mac to act
/// on: what the session decides is the interesting part, not the CGEvents.
final class ActionSession {
    /// The screen after a step, as the model gets to see it.
    struct Observation {
        var capture: ScreenCapture?
        /// Controls on screen with their coordinates in that capture, ready to `click`.
        var controls: String
        var frontmost: String?
    }

    struct Hooks {
        /// Speaks what is about to happen and waits for the user. True to go ahead.
        var confirm: (String) -> Bool
        var perform: (ToolCall, ScreenCapture?) throws -> String
        var observe: () -> Observation
        var frontmostBundleID: () -> String?
        var elementLabel: (CGPoint) -> String?
        /// What the panel shows while a step runs.
        var progress: (String) -> Void
        /// The budget is spent: say so out loud, before the model gets to.
        var capHit: () -> Void
    }

    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "act")
    private let policy: ActionPolicy
    private let maximumSteps: Int
    private let hooks: Hooks
    private let lock = NSLock()
    private var cancelled = false

    /// Steps taken so far. Read by the coordinator to tell an answer that acted from one that
    /// only looked, because the marks from the original screen mean nothing after the first step.
    private(set) var steps = 0
    private(set) var hitCap = false
    /// The last screenshot the model was shown — what `click` coordinates refer to.
    private(set) var lastCapture: ScreenCapture?
    /// Screenshots taken after steps. The one the question started with belongs to the coordinator.
    private var observed: [URL] = []

    init(policy: ActionPolicy, maximumSteps: Int, initialCapture: ScreenCapture?, hooks: Hooks) {
        self.policy = policy
        self.maximumSteps = maximumSteps
        self.lastCapture = initialCapture
        self.hooks = hooks
    }

    /// Esc, or a new question: nothing further runs, and any confirmation being waited on is a no.
    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Removes the screenshots this session took. Call once the answer has landed.
    func cleanUp() {
        for url in observed { try? FileManager.default.removeItem(at: url) }
        observed = []
    }

    /// Blocking; runs on the socket's serial queue.
    func handle(_ call: ToolCall) -> ToolResult {
        guard !isCancelled else { return .failure("The user cancelled. Stop; do nothing more.") }
        steps += 1
        let started = Date()
        var entry = ActionLog.Entry(at: started, tool: call.tool.rawValue,
                                    arguments: ActionLog.flatten(call.arguments),
                                    verdict: "allow", confirmed: nil, ok: false, result: "", durationMs: 0)
        defer {
            entry.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            ActionLog.record(entry)
        }
        guard steps <= maximumSteps else {
            if !hitCap { hitCap = true; hooks.capHit() }
            entry.verdict = "cap"
            entry.result = "step limit \(maximumSteps) reached"
            return .failure("Step limit of \(maximumSteps) reached. Stop now and tell the user, in one sentence, what was and was not done.")
        }

        let target = clickTarget(call)
        let verdict = policy.verdict(for: call, frontmostBundleID: hooks.frontmostBundleID(), target: target)

        switch verdict {
        case .deny(let reason):
            entry.verdict = "deny"
            entry.result = reason
            return .failure("Refused: \(reason). Find another way, or tell the user it can't be done.")
        case .confirm(let what):
            entry.verdict = "confirm"
            let approved = hooks.confirm(what)
            entry.confirmed = approved
            guard approved else {
                entry.result = "declined"
                return .failure("The user declined to \(what). Do not retry or work around it; stop and say what was not done.")
            }
        case .allow:
            break
        }

        hooks.progress(call.describe.prefix(1).uppercased() + call.describe.dropFirst())
        do {
            let outcome = try hooks.perform(call, lastCapture)
            entry.ok = true
            entry.result = String(outcome.prefix(ActionLog.resultLimit))
            let seen = hooks.observe()
            if let capture = seen.capture { lastCapture = capture; observed.append(capture.url) }
            return ToolResult(text: describe(outcome, seen: seen),
                              image: seen.capture.flatMap { try? Data(contentsOf: $0.url) })
        } catch {
            let message = (error as? KestrelError)?.errorDescription ?? error.localizedDescription
            entry.result = message
            return .failure(message)
        }
    }

    /// The label under a click, looked up before the policy runs so "Delete" is a confirmation
    /// and not a surprise.
    private func clickTarget(_ call: ToolCall) -> String? {
        guard call.tool == .click, let x = call.number("x"), let y = call.number("y"),
              let point = lastCapture?.screenPoint(forPixel: CGPoint(x: x, y: y)) else { return nil }
        return hooks.elementLabel(point)
    }

    private func describe(_ outcome: String, seen: Observation) -> String {
        var parts = [outcome]
        if let app = seen.frontmost { parts.append("In front now: \(app).") }
        if seen.capture != nil {
            parts.append("The screenshot attached is the screen after that; look at it before the next step.")
        }
        if !seen.controls.isEmpty {
            parts.append("Things you can click, with their coordinates in that screenshot:\n\(seen.controls)")
        }
        parts.append("\(maximumSteps - steps) step\(maximumSteps - steps == 1 ? "" : "s") left.")
        return parts.joined(separator: "\n\n")
    }
}
