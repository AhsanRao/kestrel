import AppKit
import ApplicationServices
import os

/// Carries out one tool call. No policy here — `ActionSession` has already decided the call may
/// run — and no screenshots; this is the hands only.
enum Actuator {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "actuate")
    /// A script or command still running after this has hung, and the model is waiting on it.
    static let subprocessTimeout: TimeInterval = 60
    /// Output past this is noise to a model that only needs to know whether it worked.
    static let outputLimit = 8_000

    /// Blocking; call from a background queue. Returns what the model is told.
    static func perform(_ call: ToolCall, screenshot: ScreenCapture?, config: Config) throws -> String {
        switch call.tool {
        case .openApp:
            let name = call.string("name") ?? ""
            guard let app = AppLauncher.installedApp(named: name) else {
                throw KestrelError.actionFailed("find an app called \(name)")
            }
            guard AppLauncher.launch(bundleID: app.bundleID) else {
                throw KestrelError.actionFailed("open \(app.name)")
            }
            return "\(app.name) is open and in front."

        case .runAppleScript:
            let file = Paths.temporaryFile(ext: "applescript")
            defer { try? FileManager.default.removeItem(at: file) }
            try (call.string("script") ?? "").write(to: file, atomically: true, encoding: .utf8)
            let result = try CLIRunner().run(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                                             arguments: [file.path], cwd: Paths.home,
                                             timeout: subprocessTimeout)
            return report(result, label: "AppleScript")

        case .runShell:
            let result = try CLIRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                             arguments: ["-c", call.string("command") ?? ""],
                                             cwd: Paths.home, timeout: subprocessTimeout)
            return report(result, label: "Command")

        case .click:
            guard let x = call.number("x"), let y = call.number("y") else {
                throw KestrelError.actionFailed("click without coordinates")
            }
            guard let point = screenshot?.screenPoint(forPixel: CGPoint(x: x, y: y)) else {
                throw KestrelError.actionFailed("click: there is no screenshot to measure against")
            }
            try click(at: point)
            return "Clicked at \(Int(x)), \(Int(y))."

        case .typeText:
            let text = call.string("text") ?? ""
            try DispatchQueue.main.sync { try TextInjector.inject(text, mode: config.injectMode) }
            return "Typed \(text.count) characters."

        case .pressKey:
            let name = call.string("key") ?? ""
            guard let code = KeyCodes.keyCode(named: name) else {
                throw KestrelError.actionFailed("press a key called \(name)")
            }
            try press(code, flags: KeyCodes.flags(for: call.modifiers))
            return "Pressed \(call.describe.dropFirst("press ".count))."
        }
    }

    /// stdout, stderr and the exit code, each only when it says something.
    private static func report(_ result: CLIRunner.Result, label: String) -> String {
        if result.timedOut { return "\(label) was still running after \(Int(subprocessTimeout))s and was stopped." }
        var lines: [String] = []
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !out.isEmpty { lines.append(String(out.prefix(outputLimit))) }
        if !err.isEmpty { lines.append("stderr: " + String(err.prefix(outputLimit))) }
        lines.append(result.exitCode == 0 ? "Exit code 0." : "Exit code \(result.exitCode).")
        return lines.joined(separator: "\n")
    }

    // MARK: - Events

    /// A real click: the pointer moves there, presses and releases. The user sees it happen, which
    /// is the point — nothing Kestrel does to the screen should be invisible.
    static func click(at point: CGPoint) throws {
        guard TextInjector.hasAccessibilityPermission else { throw KestrelError.accessibilityDenied }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { throw KestrelError.actionFailed("make a click event") }
        move.post(tap: .cghidEventTap)
        usleep(60_000)
        down.post(tap: .cghidEventTap)
        usleep(40_000)
        up.post(tap: .cghidEventTap)
        log.debug("clicked at \(Int(point.x)),\(Int(point.y))")
    }

    static func press(_ code: CGKeyCode, flags: CGEventFlags) throws {
        guard TextInjector.hasAccessibilityPermission else { throw KestrelError.accessibilityDenied }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { throw KestrelError.actionFailed("make a key event") }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(30_000)
        up.post(tap: .cghidEventTap)
    }

    /// The label of whatever control sits under a screen point, so a click on "Delete" can be
    /// recognised for what it is before it lands.
    static func elementLabel(at point: CGPoint) -> String? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else { return nil }
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }
}
