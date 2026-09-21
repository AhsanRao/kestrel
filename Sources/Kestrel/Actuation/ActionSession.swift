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
        /// The same controls, numbered as listed, so `click` by number can find them.
        var elements: [AXElementScanner.Element] = []
    }

    struct Hooks {
        /// Speaks what is about to happen and waits for the user. True to go ahead.
        var confirm: (String) -> Bool
        var perform: (ToolCall, ScreenCapture?, [AXElementScanner.Element]) throws -> String
        /// The screen after a step, given how long that kind of step takes to show.
        var observe: (ToolCall) -> Observation
        var frontmostBundleID: () -> String?
        var elementLabel: (CGPoint) -> String?
        /// What the panel shows while a step runs, and then what it did.
        var progress: (String) -> Void
        var stepDone: (String) -> Void = { _ in }
        /// The budget is spent: say so out loud, before the model gets to.
        var capHit: () -> Void
        /// Whether an action is worth checking with the user, when something better than the
        /// word list is available to ask (spec §8.19). Nil hands the call back to the list.
        var judge: ActionPolicy.Judge? = nil
        /// After a step: does the request look carried out, and does the model need the picture
        /// to choose the next one. Nil says nothing and sends the picture.
        var review: ((String) -> ActionJudge.Progress?)? = nil
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
    /// The last numbered list the model was shown — what `click` by number refers to.
    private(set) var lastElements: [AXElementScanner.Element]
    /// Screenshots taken after steps. The one the question started with belongs to the coordinator.
    private var observed: [URL] = []
    /// What was asked, and what has been done about it so far, for the done-check.
    private let request: String
    private var taken: [String] = []
    /// The steps that worked, in words that will still mean something next week — a click by
    /// its label, not its number — for the recipe written when the job is done.
    private(set) var recipe: [String] = []
    private var recipeSpoiled = false
    /// What the last review made of the screen, for a macro to check its own work against.
    private(set) var lastReview: ActionJudge.Progress?

    init(policy: ActionPolicy, maximumSteps: Int, initialCapture: ScreenCapture?, hooks: Hooks,
         request: String = "", initialElements: [AXElementScanner.Element] = []) {
        self.policy = policy
        self.maximumSteps = maximumSteps
        self.lastCapture = initialCapture
        self.lastElements = initialElements
        self.hooks = hooks
        self.request = request
    }

    /// Another look at the screen, with no step taken: a page that was still loading at the
    /// last look may be done now.
    func lookAgain(after seconds: TimeInterval) -> ActionJudge.Progress? {
        Thread.sleep(forTimeInterval: seconds)
        let seen = hooks.observe(ToolCall(tool: .click))
        if let capture = seen.capture { lastCapture = capture; observed.append(capture.url) }
        lastElements = seen.elements
        lastReview = hooks.review?(progress(seen: seen))
        return lastReview
    }

    /// The screen was read again outside the loop — after a macro fell through — so the numbers
    /// the model is about to be shown are these, not the last observation's.
    func refresh(capture: ScreenCapture?, elements: [AXElementScanner.Element]) {
        if let capture { lastCapture = capture }
        lastElements = elements
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
    /// - Parameter observe: look at the screen afterwards. A macro's middle steps skip it — the
    ///   next step is already decided — and only its last is checked.
    func handle(_ call: ToolCall, observe: Bool = true) -> ToolResult {
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
        let verdict = policy.verdict(for: call, frontmostBundleID: hooks.frontmostBundleID(), target: target,
                                     judge: hooks.judge)

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
            let outcome = try hooks.perform(call, lastCapture, lastElements)
            entry.ok = true
            entry.result = String(outcome.prefix(ActionLog.resultLimit))
            hooks.stepDone(target.map { "Clicked \($0)" } ?? outcome.split(separator: "\n").first.map(String.init) ?? call.describe)
            // A click by coordinates names nothing that will be there next time: a route with one
            // in it is not a recipe.
            if call.tool == .click, target == nil { recipe = []; recipeSpoiled = true }
            if !recipeSpoiled { recipe.append(target.map { "click “\($0)”" } ?? call.describe) }
            guard observe else { return ToolResult(text: outcome, image: nil) }
            let seen = hooks.observe(call)
            if let capture = seen.capture { lastCapture = capture; observed.append(capture.url) }
            lastElements = seen.elements
            taken.append("\(call.describe) — \(outcome.prefix(120))")
            let review = hooks.review?(progress(seen: seen)) ?? ActionJudge.Progress()
            lastReview = review
            return ToolResult(text: describe(outcome, seen: seen, review: review),
                              image: review.picture ? seen.capture.flatMap { try? Data(contentsOf: $0.url) } : nil)
        } catch {
            let message = (error as? KestrelError)?.errorDescription ?? error.localizedDescription
            entry.result = message
            return .failure(message)
        }
    }

    /// The label under a click, looked up before the policy runs so "Delete" is a confirmation
    /// and not a surprise.
    private func clickTarget(_ call: ToolCall) -> String? {
        guard call.tool == .click else { return nil }
        if let number = call.number("control") {
            return lastElements.first { $0.id == Int(number) }?.label
        }
        guard let x = call.number("x"), let y = call.number("y"),
              let point = lastCapture?.screenPoint(forPixel: CGPoint(x: x, y: y)) else { return nil }
        return hooks.elementLabel(point)
    }

    /// The request and its progress as the done-check reads them: words only, no screenshot.
    func progress(seen: Observation) -> String {
        var lines = ["The user asked: \"\(request)\"", "Steps taken so far:"]
        lines += taken.enumerated().map { "\($0.offset + 1). \($0.element)" }
        if let app = seen.frontmost { lines.append("In front now: \(app).") }
        if !seen.controls.isEmpty { lines.append("On screen now:\n" + seen.controls.prefix(2_000)) }
        return lines.joined(separator: "\n")
    }

    private func describe(_ outcome: String, seen: Observation,
                          review: ActionJudge.Progress = .init()) -> String {
        var parts = [outcome]
        if review.done {
            parts.append("Kestrel's check says the request looks complete. If the screen agrees, stop here and tell the user in one sentence what was done.")
        }
        if let app = seen.frontmost { parts.append("In front now: \(app).") }
        if let capture = seen.capture, review.picture {
            parts.append("The screenshot attached is the screen after that, \(Int(capture.pixelSize.width))×\(Int(capture.pixelSize.height)) pixels; look at it before the next step.")
        } else if seen.capture != nil {
            parts.append("No screenshot this step: the controls below are the screen after that. Ask for one by taking any step if you need to see it.")
        }
        if !seen.controls.isEmpty {
            parts.append("Things you can click — by number with click(control: N), or at the coordinates given in that screenshot:\n\(seen.controls)")
        }
        parts.append("\(maximumSteps - steps) step\(maximumSteps - steps == 1 ? "" : "s") left.")
        return parts.joined(separator: "\n\n")
    }
}
