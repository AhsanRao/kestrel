import AppKit
import os

/// Watches for a mouse drag while the ask hotkey is held, so the user can circle part of the
/// screen and ask about that (spec §8.16).
///
/// Global *mouse* monitors need no Accessibility grant, unlike keyboard ones, so circling works
/// out of the box. The drag is only observed — never swallowed — so whatever is underneath still
/// behaves normally.
final class DragTracker {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "drag")
    private var monitors: [Any] = []
    private(set) var points: [CGPoint] = []

    /// Ignore the small drags that are really just a click, or a hand resting on the trackpad.
    static let minimumSpan: CGFloat = 40

    /// Called on the main thread as the trail grows, so the overlay can draw it.
    var onChange: (([CGPoint]) -> Void)?

    var isTracking: Bool { !monitors.isEmpty }

    func begin() {
        end()
        points = []
        for mask in [NSEvent.EventTypeMask.leftMouseDragged, .leftMouseDown, .leftMouseUp] {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.handle(event)
            }) {
                monitors.append(monitor)
            }
        }
    }

    /// Stops watching and returns the region the user circled, in global AppKit points.
    @discardableResult
    func end() -> CGRect? {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        let rect = DragTracker.boundingBox(of: points)
        points = []
        return rect
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            points = [NSEvent.mouseLocation]
        case .leftMouseDragged:
            points.append(NSEvent.mouseLocation)
        default:
            break
        }
        let snapshot = points
        DispatchQueue.main.async { self.onChange?(snapshot) }
    }

    /// The box around a trail, padded a little so the circled thing is inside rather than on the
    /// line. Returns nil when the gesture was too small to be deliberate.
    static func boundingBox(of points: [CGPoint], padding: CGFloat = 12) -> CGRect? {
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard rect.width >= minimumSpan || rect.height >= minimumSpan else { return nil }
        return rect.insetBy(dx: -padding, dy: -padding)
    }
}
