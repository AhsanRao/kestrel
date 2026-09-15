import Foundation
import os

/// A Unix-domain socket that speaks newline-delimited JSON, so `claude -p` can reach the tools
/// living inside the running app.
///
/// Claude Code spawns MCP servers itself, as child processes on stdio. The tools cannot live in a
/// child, though: they need the Accessibility grant, the microphone and the voice, all of which
/// belong to Kestrel.app. So the child Claude spawns is `nc -U <this socket>` — a relay of no code
/// at all — and every line it forwards is answered here. No TCP port is opened.
final class MCPSocketServer {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "mcp")
    private let path: String
    private var listener: Int32 = -1
    private let accepting = DispatchQueue(label: "dev.0xash.kestrel.mcp.accept")
    /// One connection at a time is served here, so tool calls arrive in order and confirmations
    /// never overlap.
    private let serving = DispatchQueue(label: "dev.0xash.kestrel.mcp.serve")

    /// Answers one line. Nil means the line wanted no reply.
    var handler: ((String) -> String?)?

    init(path: URL) { self.path = path.path }

    var isRunning: Bool { listener >= 0 }

    func start() {
        guard listener < 0 else { return }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return log.error("socket() failed: \(errno)") }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return log.error("socket path too long: \(self.path, privacy: .public)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = UInt8(bitPattern: byte) }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0, listen(fd, 4) == 0 else {
            log.error("bind/listen failed: \(errno)")
            close(fd)
            return
        }
        // Only this user may connect: the socket is a door into the Mac.
        chmod(path, 0o600)
        listener = fd
        log.info("listening on \(self.path, privacy: .public)")
        accepting.async { [weak self] in self?.acceptLoop(fd) }
    }

    func stop() {
        guard listener >= 0 else { return }
        close(listener)
        listener = -1
        unlink(path)
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            serving.async { [weak self] in self?.serve(client) }
        }
    }

    /// Reads lines until the peer hangs up, answering each in turn.
    private func serve(_ client: Int32) {
        defer { close(client) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return }
            pending.append(buffer, count: count)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending = Data(pending[pending.index(after: newline)...])
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                      let reply = handler?(line) else { continue }
                var out = Array((reply + "\n").utf8)
                var offset = 0
                while offset < out.count {
                    let written = out.withUnsafeMutableBytes { write(client, $0.baseAddress! + offset, $0.count - offset) }
                    guard written > 0 else { return }
                    offset += written
                }
            }
        }
    }
}
