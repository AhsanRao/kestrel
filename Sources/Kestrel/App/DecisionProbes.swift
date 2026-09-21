import AppKit
import Foundation

/// The decision probes: what Jev and the actuator make of a phrase, an action, a reply or a
/// control, printed and done — no model, no microphone. `ActionProbe` dispatches to them.
extension ActionProbe {
    /// `KESTREL_TRIAGE="open Finder;what is this"` — the routing decision for each phrase, and
    /// how long Jev took over it, without a model or a microphone.
    static func triage(_ lines: String, config: Config) {
        let screen = ScreenSnapshot.read(bundleID: TextInjector.frontmostBundleID())
        print("\(screen.targets.filter { $0.kind == .control }.count) controls on screen")
        for text in lines.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let started = Date()
            let triage = QuestionTriage.decide(text, frontmostApp: NSWorkspace.shared.frontmostApplication?.localizedName,
                                               previous: nil, controls: screen.targets, config: config)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            var line = "\(ms)ms  \(triage.kind.rawValue)"
            if let app = triage.app { line += " → \(app.name)" + (triage.opensFirst ? " first" : "") }
            if let macro = triage.macro { line += " → \(SessionCoordinator.describe(macro))" }
            if triage.wantsDraft { line += "  draft" }
            if triage.needsDesktop { line += "  desktop" }
            print(line + "  [\(triage.source)]  \(text)")
        }
        exit(0)
    }

    /// `KESTREL_JUDGE="click the control labelled “Send”;type the text: hello"` — worth asking?
    static func judge(_ lines: String, config: Config) {
        for action in lines.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let verdict = ActionJudge.isSensitive(action, in: "Mail", config: config)
            print("\(verdict.map { $0 ? "ask   " : "allow " } ?? "list  ")  \(action)")
        }
        exit(0)
    }

    /// `KESTREL_CONSENT="yes;no;yes but not that one"` — read as a go-ahead?
    static func consent(_ lines: String, config: Config) {
        for reply in lines.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let verdict = ActionJudge.isYes(reply, to: "send the email", config: config)
            print("\(verdict.map { $0 ? "yes   " : "no    " } ?? "list  ")  \(Confirmation.isYes(reply) ? "(list: yes)" : "(list: no) ")  \(reply)")
        }
        exit(0)
    }

    /// `KESTREL_AIM="New Tab"` — the round trip a click takes: the control's frame, the pixel the
    /// model is told, the screen point that pixel maps back to, and what is actually under it.
    static func aim(_ label: String, config: Config) {
        let capture: ScreenCapture
        do {
            capture = try ScreenGrabber.capture(maxEdge: config.screenshotMaxEdge, mode: config.captureMode)
        } catch {
            print("no capture: \(error)"); exit(1)
        }
        print("capture frame \(capture.captureFrame) → \(Int(capture.pixelSize.width))x\(Int(capture.pixelSize.height)) px")
        print("primary display height \(ScreenGrabber.primaryDisplayHeight); screens: \(NSScreen.screens.map(\.frame))")
        for element in AXElementScanner.scanFrontmostApp() where element.label.localizedCaseInsensitiveContains(label) {
            let centre = CGPoint(x: element.frame.midX, y: element.frame.midY)
            guard let pixel = capture.pixel(forScreenPoint: centre) else { print("off capture: \(element.label)"); continue }
            let back = capture.screenPoint(forPixel: pixel) ?? .zero
            let under = Actuator.elementLabel(at: back) ?? "nothing"
            print("\(element.label): frame \(element.frame) → pixel \(Int(pixel.x)),\(Int(pixel.y)) → CG \(Int(back.x)),\(Int(back.y)) → under pointer: \(under)")
        }
        try? FileManager.default.removeItem(at: capture.url)
        exit(0)
    }

    /// `KESTREL_TYPE="Address and search bar|hello"` — click the control, type into it the way
    /// `type_text` does, press return, and read the field back at each stage.
    static func typeTest(_ spec: String, config: Config) {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { print("KESTREL_TYPE=label|text"); exit(1) }
        DispatchQueue.global().async {
            let elements = AXElementScanner.scanFrontmostApp()
            guard let element = elements.first(where: { $0.label.localizedCaseInsensitiveContains(parts[0]) }) else {
                print("no control matching \(parts[0])"); exit(1)
            }
            func field() -> String {
                var value: CFTypeRef?
                guard let ref = element.ref, AXUIElementCopyAttributeValue(ref, kAXValueAttribute as CFString, &value) == .success
                else { return "(unreadable)" }
                return value as? String ?? "?"
            }
            let steps: [ToolCall] = [
                ToolCall(tool: .click, arguments: ["control": element.id]),
                ToolCall(tool: .pressKey, arguments: ["key": "a", "modifiers": ["cmd"]]),
                ToolCall(tool: .typeText, arguments: ["text": parts[1]]),
                ToolCall(tool: .pressKey, arguments: ["key": "return"]),
            ]
            for step in steps {
                do {
                    print(try Actuator.perform(step, screenshot: nil, config: config, controls: elements))
                } catch { print("failed: \(error)"); exit(1) }
                Thread.sleep(forTimeInterval: step.tool == .pressKey ? 2 : 0.6)
                print("  field: \(field().prefix(80))")
            }
            exit(0)
        }
    }
}
