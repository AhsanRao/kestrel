import AppKit
import QuartzCore

/// Moves the panel's window frame on a spring, a frame at a time, in step with the display.
///
/// AppKit's own frame animation runs a fixed curve towards a fixed target, and a window's `frame`
/// reads as that target the moment the animation starts — so a second size arriving mid-flight,
/// which is every sentence of a streaming answer, restarts the movement from a place the window is
/// not yet at. The result is a stutter on exactly the thing the island is for. A spring is
/// retargeted instead of restarted: it keeps whatever value and velocity it already has, so an
/// answer arriving line by line grows in one continuous movement.
///
/// Width and height are separate springs. One spring on the diagonal desynchronises the moment the
/// two axes have different distances to cover, which is most of the time.
final class PanelFrameAnimator {
    private weak var window: NSWindow?
    private var link: CADisplayLink?
    private var width = Spring(value: 0)
    private var height = Spring(value: 0)
    private var screen: CGRect = .zero
    private var lastTimestamp: CFTimeInterval = 0

    init(window: NSWindow) {
        self.window = window
    }

    /// Puts the window where it belongs at once, and takes the springs with it, so the next
    /// movement starts from where the window actually is.
    func place(_ size: CGSize, on screen: CGRect) {
        stop()
        self.screen = screen
        width = Spring(value: size.width)
        height = Spring(value: size.height)
        window?.setFrame(frame(width: size.width, height: size.height), display: true)
    }

    func animate(to size: CGSize, on screen: CGRect) {
        let unchanged = size.width == width.target && size.height == height.target
        self.screen = screen
        width.target = size.width
        height.target = size.height
        guard !unchanged || link != nil else { return }
        start()
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    // MARK: - Private

    private func start() {
        guard link == nil, let view = window?.contentView else { return }
        lastTimestamp = 0
        let link = view.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastTimestamp = now }
        guard lastTimestamp > 0 else { return }
        // Clamped: a frame missed behind a modal sheet, or a wake from sleep, must not integrate a
        // half-second step and throw the island off the top of the screen.
        let dt = min(now - lastTimestamp, 1.0 / 30)
        width.step(dt)
        height.step(dt)
        if width.isSettled, height.isSettled {
            width.settle()
            height.settle()
            stop()
        }
        window?.setFrame(frame(width: width.value, height: height.value), display: true)
    }

    /// The island hangs from the real top of the display, centred on the camera housing, so only
    /// its width and height are free — the origin follows from them.
    private func frame(width w: Double, height h: Double) -> NSRect {
        NSRect(x: (screen.midX - w / 2).rounded(),
               y: (screen.maxY - h).rounded(),
               width: w.rounded(), height: h.rounded())
    }
}
