import Foundation

/// The six things the model can do to the Mac, as MCP tools. The names here are what `claude -p`
/// is told to allow (`mcp__kestrel__<name>`), so renaming one means touching `ClaudeBackend` too.
enum ActionTool: String, CaseIterable {
    case openApp = "open_app"
    case runAppleScript = "run_applescript"
    case runShell = "run_shell"
    case click
    case typeText = "type_text"
    case pressKey = "press_key"

    static let serverName = "kestrel"

    /// `mcp__kestrel__open_app` — how Claude Code names a tool from a named MCP server.
    var qualifiedName: String { "mcp__\(ActionTool.serverName)__\(rawValue)" }

    var description: String {
        switch self {
        case .openApp:
            return "Launch or bring forward an application by its name, e.g. \"Safari\". Prefer this over anything else for getting an app in front."
        case .runAppleScript:
            return "Run an AppleScript and return what it prints. The most reliable way to drive Apple apps and, via System Events, menus and keystrokes in any app. Scripts that delete, send or pay are checked with the user first; administrator privileges are never granted."
        case .runShell:
            return "Run a shell command from a short allowlist (ls, cat, grep, find, open, mdfind, date and the like) and return stdout, stderr and the exit code. Pipes and && are fine; sudo, redirection and $() are refused."
        case .click:
            return "Click at a point in the most recent screenshot, in that screenshot's own pixel coordinates. Every tool result lists the controls on screen with their coordinates; use those. A fallback for apps that AppleScript cannot reach."
        case .typeText:
            return "Type text into whatever has keyboard focus. Newlines are collapsed to spaces in terminals."
        case .pressKey:
            return "Press one key, with optional modifiers: key such as return, tab, escape, space, delete, up, down, a–z, 0–9, f1–f12; modifiers any of cmd, ctrl, alt, shift."
        }
    }

    /// JSON Schema for the tool's arguments, as `tools/list` hands it over.
    var inputSchema: [String: Any] {
        func schema(_ properties: [String: [String: Any]], required: [String]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required]
        }
        switch self {
        case .openApp:
            return schema(["name": ["type": "string", "description": "The app's name as it appears in the Applications folder."]],
                          required: ["name"])
        case .runAppleScript:
            return schema(["script": ["type": "string"]], required: ["script"])
        case .runShell:
            return schema(["command": ["type": "string"]], required: ["command"])
        case .click:
            return schema(["x": ["type": "number"], "y": ["type": "number"]], required: ["x", "y"])
        case .typeText:
            return schema(["text": ["type": "string"]], required: ["text"])
        case .pressKey:
            return schema(["key": ["type": "string"],
                           "modifiers": ["type": "array", "items": ["type": "string"]]],
                          required: ["key"])
        }
    }

    /// The `tools/list` entry.
    var listing: [String: Any] {
        ["name": rawValue, "description": description, "inputSchema": inputSchema]
    }
}

/// One request from the model, as it arrived over MCP.
struct ToolCall: Equatable {
    var tool: ActionTool
    var arguments: [String: Any]

    init(tool: ActionTool, arguments: [String: Any] = [:]) {
        self.tool = tool
        self.arguments = arguments
    }

    func string(_ key: String) -> String? { arguments[key] as? String }
    func number(_ key: String) -> Double? {
        (arguments[key] as? Double) ?? (arguments[key] as? Int).map(Double.init)
    }
    var modifiers: [String] { (arguments["modifiers"] as? [String]) ?? [] }

    /// What the user is told is about to happen, and what the log records.
    var describe: String {
        switch tool {
        case .openApp: return "open \(string("name") ?? "an app")"
        case .runAppleScript: return "run an AppleScript: \(ToolCall.excerpt(string("script")))"
        case .runShell: return "run \(ToolCall.excerpt(string("command")))"
        case .click: return "click at \(Int(number("x") ?? 0)), \(Int(number("y") ?? 0))"
        case .typeText: return "type \(ToolCall.excerpt(string("text")))"
        case .pressKey:
            let combo = (modifiers + [string("key") ?? "?"]).joined(separator: "+")
            return "press \(combo)"
        }
    }

    static func excerpt(_ text: String?, limit: Int = 80) -> String {
        let flat = (text ?? "").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > limit ? "“\(flat.prefix(limit))…”" : "“\(flat)”"
    }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.tool == rhs.tool && NSDictionary(dictionary: lhs.arguments).isEqual(to: rhs.arguments)
    }
}

/// What goes back to the model. The screenshot rides along as an image block, so the model sees
/// the screen after the action without spending a turn reading a file.
struct ToolResult {
    var text: String
    var image: Data?
    var isError = false

    static func failure(_ message: String) -> ToolResult { ToolResult(text: message, isError: true) }

    /// MCP `content` blocks.
    var content: [[String: Any]] {
        var blocks: [[String: Any]] = [["type": "text", "text": text]]
        if let image {
            blocks.append(["type": "image", "data": image.base64EncodedString(), "mimeType": "image/png"])
        }
        return blocks
    }
}
