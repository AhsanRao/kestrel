import Foundation

/// The Model Context Protocol, as much of it as a tool server needs: `initialize`, `tools/list`,
/// `tools/call`, `ping`. One JSON-RPC object per line in, one per line out. Pure — the socket is
/// somebody else's job — so the whole exchange can be tested with strings.
struct MCPProtocol {
    /// Runs a tool. Called on whatever thread the line arrived on; may block for as long as the
    /// action (or the user's confirmation) takes.
    var call: (ToolCall) -> ToolResult

    static let version = "2025-11-25"

    /// The reply to one line, or nil when the line was a notification and wants none.
    func respond(to line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return MCPProtocol.encode(id: nil, error: (-32700, "parse error")) }

        let id = request["id"]
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]
        // Notifications carry no id and expect no answer.
        guard id != nil, !(id is NSNull) else { return nil }

        switch method {
        case "initialize":
            return MCPProtocol.encode(id: id, result: [
                "protocolVersion": (params["protocolVersion"] as? String) ?? MCPProtocol.version,
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": ActionTool.serverName, "version": MCPProtocol.serverVersion],
            ])
        case "ping":
            return MCPProtocol.encode(id: id, result: [:])
        case "tools/list":
            return MCPProtocol.encode(id: id, result: ["tools": ActionTool.allCases.map(\.listing)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = ActionTool(rawValue: name) else {
                return MCPProtocol.encode(id: id, error: (-32602, "unknown tool"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = call(ToolCall(tool: tool, arguments: arguments))
            return MCPProtocol.encode(id: id, result: ["content": result.content, "isError": result.isError])
        default:
            return MCPProtocol.encode(id: id, error: (-32601, "method not found"))
        }
    }

    static var serverVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func encode(id: Any?, result: [String: Any]) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    static func encode(id: Any?, error: (code: Int, message: String)) -> String {
        encode(["jsonrpc": "2.0", "id": id ?? NSNull(),
                "error": ["code": error.code, "message": error.message]])
    }

    /// One line, no pretty-printing: the transport is newline-delimited.
    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
