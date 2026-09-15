import XCTest
@testable import Kestrel

/// The MCP handshake, list and call, as strings — the transport (a Unix socket) is separate and
/// not exercised here.
final class MCPProtocolTests: XCTestCase {
    private func object(_ json: String?) -> [String: Any] {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    func testInitializeAnnouncesTools() {
        let mcp = MCPProtocol { _ in .init(text: "") }
        let reply = object(mcp.respond(to: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#))
        let result = reply["result"] as? [String: Any]
        XCTAssertEqual((result?["serverInfo"] as? [String: Any])?["name"] as? String, "kestrel")
        XCTAssertNotNil(result?["capabilities"] as? [String: Any])
    }

    func testNotificationsGetNoReply() {
        let mcp = MCPProtocol { _ in .init(text: "") }
        XCTAssertNil(mcp.respond(to: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#))
    }

    func testToolsListReturnsAllSix() {
        let mcp = MCPProtocol { _ in .init(text: "") }
        let reply = object(mcp.respond(to: #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = (reply["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, ActionTool.allCases.count)
        let names = Set((tools ?? []).compactMap { $0["name"] as? String })
        XCTAssertEqual(names, Set(ActionTool.allCases.map(\.rawValue)))
    }

    func testACallReachesTheHandlerWithArguments() {
        var seen: ToolCall?
        let mcp = MCPProtocol { call in seen = call; return .init(text: "opened") }
        let reply = object(mcp.respond(to: #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"open_app","arguments":{"name":"Safari"}}}"#))
        XCTAssertEqual(seen?.tool, .openApp)
        XCTAssertEqual(seen?.string("name"), "Safari")
        let content = (reply["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(content?.first?["text"] as? String, "opened")
    }

    func testAnImageResultBecomesAnImageBlock() {
        let mcp = MCPProtocol { _ in .init(text: "here", image: Data([0x89, 0x50])) }
        let reply = object(mcp.respond(to: #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"open_app","arguments":{}}}"#))
        let content = (reply["result"] as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertTrue(content?.contains { $0["type"] as? String == "image" } ?? false)
    }

    func testAnUnknownToolIsAnError() {
        let mcp = MCPProtocol { _ in .init(text: "") }
        let reply = object(mcp.respond(to: #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"launch_missiles"}}"#))
        XCTAssertNotNil(reply["error"])
    }

    func testGarbageIsAParseError() {
        let mcp = MCPProtocol { _ in .init(text: "") }
        let reply = object(mcp.respond(to: "not json"))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32700)
    }
}

/// The yes-or-no said back to a confirmation.
final class ConfirmationTests: XCTestCase {
    func testATapWithNothingSaidIsYes() {
        XCTAssertTrue(Confirmation.isYes(""))
        XCTAssertTrue(Confirmation.isYes("   "))
    }

    func testPlainYeses() {
        for word in ["yes", "yeah", "go ahead", "do it", "sure", "okay"] {
            XCTAssertTrue(Confirmation.isYes(word), word)
        }
    }

    func testPlainNoes() {
        for word in ["no", "nope", "stop", "cancel", "don't", "never mind", "wait"] {
            XCTAssertFalse(Confirmation.isYes(word), word)
        }
    }

    func testANoWinsWhenBothAppear() {
        // "no, don't do it" carries "do it"; the no has to win.
        XCTAssertFalse(Confirmation.isYes("no don't do it"))
    }

    func testAnUnrelatedMumbleIsNotAYes() {
        XCTAssertFalse(Confirmation.isYes("what was that"))
    }
}
