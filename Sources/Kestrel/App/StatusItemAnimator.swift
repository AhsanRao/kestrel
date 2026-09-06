import AppKit

/// Breathes the menu bar icon while Kestrel is busy.
///
/// The menu bar is the only part of Kestrel that is always visible, so it is the right place to
/// say "I am listening" — especially when the panel is behind a full-screen window. Kept to
/// opacity: a template image cannot be tinted, and anything larger would be noise in a menu bar.
final class StatusItemAnimator {
    /// How the icon behaves in each state.
    enum Pace: Equatable {
        case still
        case breathing(period: TimeInterval, floor: CGFloat)

        static func forState(_ state: SessionState) -> Pace {
            switch state {
            case .listening, .dictating: return .breathing(period: 0.75, floor: 0.4)
            case .transcribing, .thinking, .injecting, .acting: return .breathing(period: 1.4, floor: 0.55)
            default: return .still
            }
        }
    }

    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var dim = false
    private var pace: Pace = .still
    private var lastState: SessionState?

    /// Live system setting — checked at the moment it matters rather than cached.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(button: NSStatusBarButton?) {
        self.button = button
    }

    func apply(_ state: SessionState) {
        defer { lastState = state }
        let next = Pace.forState(state)
        if next != pace {
            pace = next
            timer?.invalidate()
            timer = nil

            guard case .breathing(let period, let floor) = next else {
                setAlpha(1, duration: 0.2)
                return applyOneShot(for: state)
            }
            guard !reduceMotion else {
                // A steady dim still says "busy" without the repeating loop Reduce Motion asks to skip.
                setAlpha(floor, duration: 0.2)
                return
            }
            dim = false
            timer = Timer.scheduledTimer(withTimeInterval: period / 2, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.dim.toggle()
                self.setAlpha(self.dim ? floor : 1, duration: period / 2)
            }
            setAlpha(floor, duration: period / 2)
        }
        applyOneShot(for: state)
    }

    /// Cues that fire once on arrival rather than looping, so the menu bar is legible even when the
    /// panel is hidden behind a full-screen window — a landed answer and a failure should not look
    /// the same as settling back to idle.
    private func applyOneShot(for state: SessionState) {
        guard state != lastState, !reduceMotion else { return }
        switch state {
        case .answering: pulseOnce()
        case .error: flashError()
        default: break
        }
    }

    /// A single quick dip: "the answer landed."
    private func pulseOnce() {
        setAlpha(0.35, duration: 0.12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.setAlpha(1, duration: 0.25)
        }
    }

    /// Three quick blinks: an error is worth noticing out of the corner of the eye.
    private func flashError() {
        var delay: TimeInterval = 0
        for _ in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.setAlpha(0.25, duration: 0.09)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.09) { [weak self] in
                self?.setAlpha(1, duration: 0.09)
            }
            delay += 0.22
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pace = .still
        lastState = nil
        button?.alphaValue = 1
    }

    private func setAlpha(_ value: CGFloat, duration: TimeInterval) {
        guard let button else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.animator().alphaValue = value
        }
    }
}
