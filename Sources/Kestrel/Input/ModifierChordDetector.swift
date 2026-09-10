import AppKit

/// Decides when a bare modifier chord — ⌃⌥ held on its own, with no letter — counts as a press.
///
/// Pure logic so the awkward parts can be tested: the chord is also the prefix of every shortcut
/// built on the same modifiers, so it must not fire the instant those go down. It waits out a short
/// dwell, and any key pressed while it is held means the user was reaching for a shortcut, not
/// talking to Kestrel.
struct ModifierChordDetector {
    /// Long enough that reaching through the chord for a shortcut never trips it, short enough to
    /// feel immediate on a deliberate hold.
    static let dwell: TimeInterval = 0.28

    enum Input: Equatable {
        case flagsChanged(NSEvent.ModifierFlags)
        case dwellElapsed
        case keyPressed
    }

    enum Output: Equatable {
        case arm          // chord is down; start the dwell timer
        case disarm       // chord let go, or a key intervened, before it ever fired
        case fire         // dwell survived: this is a real press
        case release      // chord let go after firing
        case abort        // a key was pressed while the chord was already firing
    }

    private enum State { case idle, armed, active }

    let required: Set<String>
    private var state: State = .idle

    init(required: Set<String>) {
        self.required = required
    }

    var isActive: Bool { state == .active }

    mutating func apply(_ input: Input) -> Output? {
        switch input {
        case .flagsChanged(let flags):
            return matches(flags) ? chordDown() : chordUp()
        case .dwellElapsed:
            guard state == .armed else { return nil }
            state = .active
            return .fire
        case .keyPressed:
            switch state {
            case .armed: state = .idle; return .disarm
            case .active: state = .idle; return .abort
            case .idle: return nil
            }
        }
    }

    private mutating func chordDown() -> Output? {
        guard state == .idle else { return nil }
        state = .armed
        return .arm
    }

    private mutating func chordUp() -> Output? {
        switch state {
        case .armed: state = .idle; return .disarm
        case .active: state = .idle; return .release
        case .idle: return nil
        }
    }

    /// Exact match: ⌃⌥⌘ held is a different chord, not this one. Caps Lock is ignored.
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        Set(HotkeyBinding.modifierNames(from: flags.intersection(.deviceIndependentFlagsMask))) == required
    }
}
