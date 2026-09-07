import AppKit
import CoreGraphics
import os

/// Watches for a mouse drag while the ask hotkey is held, so the user can circle part of the screen
/// and ask about that (spec §8.16).
///
/// The drag is **swallowed**, not merely observed. It used to be watched with a passive global
/// monitor, which cannot consume anything, so circling a paragraph in a browser also selected it,
/// circling a link followed it, and — because every ask hotkey contains Control, and Control-click
/// is the secondary click on macOS — circling anything at all opened the context menu on top of the
/// thing the user was trying to ask about. A gesture aimed at Kestrel should not reach the app
/// underneath, so while the hotkey is down these events go nowhere else.
///
/// Consuming events needs a real event tap and therefore Accessibility. Without it the old passive
/// monitor is used instead: circling still works, and still clicks through, which is worse but far
/// better than the gesture not working at all.
final class DragTracker {
    private let log = Logger(subsystem: "dev.0xash.kestrel", category: "drag")
    private var monitors: [Any] = []
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var points: [CGPoint] = []

    /// Ignore the small drags that are really just a click, or a hand resting on the trackpad.
    static let minimumSpan: CGFloat = 40

    /// Called on the main thread as the trail grows, so the overlay can draw it.
    var onChange: (([CGPoint]) -> Void)?

    var isTracking: Bool { tap != nil || !monitors.isEmpty }

    /// Left *and* right buttons. With Control held, macOS reports the press as a secondary click,
    /// so a tracker that listened only for the left button saw nothing and consumed nothing.
    private static let watched: [CGEventType] = [
        .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        .rightMouseDown, .rightMouseDragged, .rightMouseUp,
    ]

    func begin() {
        end()
        points = []
        guard !startTap() else { return log.debug("circling armed — events swallowed") }
        log.info("no accessibility permission — circling will click through")
        startPassiveMonitors()
    }

    /// Stops watching and returns the region the user circled, in global AppKit points.
    @discardableResult
    func end() -> CGRect? {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        let rect = DragTracker.boundingBox(of: points)
        log.debug("circled \(self.points.count) point(s) → \(String(describing: rect))")
        points = []
        return rect
    }

    // MARK: - Watching

    private func startTap() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let mask = DragTracker.watched.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: dragTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("could not create drag tap")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
        return true
    }

    private func startPassiveMonitors() {
        for mask in [NSEvent.EventTypeMask.leftMouseDragged, .leftMouseDown, .leftMouseUp,
                     .rightMouseDragged, .rightMouseDown, .rightMouseUp] {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
                self?.record(event.type == .leftMouseDown || event.type == .rightMouseDown)
            }) {
                monitors.append(monitor)
            }
        }
    }

    /// One point of the trail. `NSEvent.mouseLocation` is already in global AppKit points, which is
    /// what the overlay and the crop both want, so nothing has to be flipped here.
    fileprivate func record(_ isPress: Bool) {
        if isPress { points = [NSEvent.mouseLocation] } else { points.append(NSEvent.mouseLocation) }
        if points.count == 1 { log.debug("circling from \(String(describing: self.points.first))") }
        let snapshot = points
        DispatchQueue.main.async { self.onChange?(snapshot) }
    }

    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
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

/// Returning nil swallows the event, which is the whole point: the circle is drawn for Kestrel and
/// must not also press whatever it was drawn over.
private let dragTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<DragTracker>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tracker.reenable()
        return Unmanaged.passUnretained(event)
    case .leftMouseDown, .rightMouseDown:
        tracker.record(true)
        return nil
    case .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp:
        tracker.record(false)
        return nil
    default:
        return Unmanaged.passUnretained(event)
    }
}
