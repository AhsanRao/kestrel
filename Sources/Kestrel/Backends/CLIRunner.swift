import Foundation
import os

/// Spawns a CLI, captures stdout/stderr, enforces a timeout, and can be cancelled.
/// Blocking by design — always called from a background queue.
final class CLIRunner {
    struct Result {
        var stdout: String
        var stderr: String
        var exitCode: Int32
        var timedOut: Bool
        var durationMs: Int
    }

    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "cli")
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// Resolves a bare command name against the subprocess PATH. Returns nil when not installed.
    static func locate(_ command: String) -> URL? {
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? URL(fileURLWithPath: command) : nil
        }
        for dir in Paths.subprocessPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        running?.terminate()
    }

    /// - Parameter onLine: called on a background queue for every complete line of stdout as it
    ///   arrives. Streaming is what makes the answer start being spoken while the model is still
    ///   writing it, instead of after.
    func run(executable: URL, arguments: [String], cwd: URL,
             environment extra: [String: String] = [:], timeout: TimeInterval,
             onLine: ((String) -> Void)? = nil) throws -> Result {
        let started = Date()
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        task.currentDirectoryURL = cwd

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Paths.subprocessPath
        env["HOME"] = Paths.home.path
        // A GUI app has no TERM; some CLIs emit ANSI garbage or hang without a sane default.
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        // `claude` refuses to start when it thinks it is nested inside another Claude Code session
        // ("Claude Code cannot be launched inside another Claude Code session"). Kestrel launched
        // from such a terminal would inherit those markers, so drop them.
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            env.removeValue(forKey: key)
        }
        for (key, value) in extra { env[key] = value }
        task.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        task.standardInput = FileHandle.nullDevice

        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = task
        lock.unlock()

        try task.run()

        // Drain both pipes concurrently: a full pipe buffer deadlocks a chatty CLI.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        let ioQueue = DispatchQueue(label: "dev.0xash.kestrel.cli.io", attributes: .concurrent)
        ioQueue.async(group: group) {
            guard let onLine else {
                outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                return
            }
            var pending = Data()
            while true {
                let chunk = outPipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                outData.append(chunk)
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending[pending.startIndex..<newline]
                    pending = pending[pending.index(after: newline)...]
                    if let text = String(data: line, encoding: .utf8), !text.isEmpty { onLine(text) }
                }
            }
            if let text = String(data: pending, encoding: .utf8), !text.isEmpty { onLine(text) }
        }
        ioQueue.async(group: group) { errData = errPipe.fileHandleForReading.readDataToEndOfFile() }

        var timedOut = false
        let deadline = DispatchWorkItem { [weak task] in
            guard let task, task.isRunning else { return }
            timedOut = true
            task.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        task.waitUntilExit()
        deadline.cancel()
        group.wait()

        lock.lock()
        process = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { throw CancellationError() }

        let duration = Int(Date().timeIntervalSince(started) * 1000)
        CLIRunner.log.debug("\(executable.lastPathComponent, privacy: .public) exited \(task.terminationStatus) in \(duration)ms")
        return Result(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: task.terminationStatus,
            timedOut: timedOut,
            durationMs: duration
        )
    }
}
