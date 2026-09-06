import Foundation

/// v1: hands back the backend named in config. `autoRoute` (spec §8.8) is off by default and
/// only nudges short, screenshot-free questions toward Codex.
final class BackendRouter {
    private let claude = ClaudeBackend()
    private let codex = CodexBackend()
    private var inFlight: Backend?

    var current: BackendKind { ConfigStore.shared.current.backend }

    func backend(for kind: BackendKind) -> Backend {
        switch kind {
        case .claude: return claude
        case .codex: return codex
        }
    }

    func select(for query: Query, config: Config) -> Backend {
        guard config.autoRoute else { return backend(for: config.backend) }
        return backend(for: BackendRouter.route(query, configured: config.backend))
    }

    static func route(_ query: Query, configured: BackendKind) -> BackendKind {
        // Screen-heavy or long questions stay with Claude; short factual ones go to Codex.
        if query.screenshot != nil || query.focusCrop != nil { return .claude }
        if query.mode == .walkthrough { return .claude }
        return query.text.split(separator: " ").count <= 12 ? .codex : configured
    }

    /// Blocking. Runs on the coordinator's background queue.
    func ask(_ query: Query, config: Config, onDelta: ((String) -> Void)? = nil) throws -> Answer {
        let backend = select(for: query, config: config)
        inFlight = backend
        defer { inFlight = nil }
        return try backend.ask(query, config: config, onDelta: onDelta)
    }

    func cancel() {
        inFlight?.cancel()
    }

    func switchTo(_ kind: BackendKind) {
        ConfigStore.shared.update { $0.backend = kind }
    }
}
