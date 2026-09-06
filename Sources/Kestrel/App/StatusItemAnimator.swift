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

    init(button: NSStatusBarButton?) {
        self.button = button
    }

    func apply(_ state: SessionState) {
        let next = Pace.forState(state)
        guard next != pace else { return }
        pace = next
        timer?.invalidate()
        timer = nil

        guard case .breathing(let period, let floor) = next else {
            setAlpha(1, duration: 0.2)
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

    func stop() {
        timer?.invalidate()
        timer = nil
        pace = .still
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
