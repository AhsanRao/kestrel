import AppKit
import CoreGraphics
import os

/// Watches for a mouse drag while the ask hotkey is held, so the user can circle part of the screen
/// and ask about that (spec §8.16).
///
/// The press and the release are **swallowed**, not merely observed. They used to be watched with a
/// passive global monitor, which cannot consume anything, so circling a paragraph in a browser also
/// selected it, circling a link followed it, and — because every ask hotkey contains Control, and
/// Control-click is the secondary click on macOS — circling anything at all opened the context menu
/// on top of the thing the user was trying to ask about. A click aimed at Kestrel should not reach
/// the app underneath, so while the hotkey is down the button events go nowhere else.
///
/// The movement between them is let through. Consuming a drag stops the window server moving the
/// pointer, which froze the cursor mid-gesture and — because the trail was read from
/// `NSEvent.mouseLocation` — recorded a hundred copies of the point where the press landed. Every
/// circle came out as a dot, failed the minimum span, and was thrown away: the gesture looked
/// dead. Points now come from each event's own coordinates, which are right whether or not
/// anything is consumed, and an app that sees drags without ever seeing the press that would have
/// started them has nothing to act on.
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

    /// The events that are consumed. The drags are watched but passed on, so the pointer keeps up
    /// with the hand — see the note above.
    private static let swallowed: Set<CGEventType> = [
        .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
    ]

    static func swallows(_ type: CGEventType) -> Bool { swallowed.contains(type) }

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
        log.debug("circled \(self.points.count) point(s) → \(String(describing: rect), privacy: .public)")
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
                self?.record(event.type == .leftMouseDown || event.type == .rightMouseDown,
                             at: NSEvent.mouseLocation)
            }) {
                monitors.append(monitor)
            }
        }
    }

    /// One point of the trail, in the global AppKit points the overlay and the crop both want.
    fileprivate func record(_ isPress: Bool, at point: CGPoint) {
        if isPress { points = [point] } else { points.append(point) }
        let snapshot = points
        DispatchQueue.main.async { self.onChange?(snapshot) }
    }

    /// A CoreGraphics event location — measured down from the top-left of the primary display —
    /// as an AppKit point measured up from the bottom.
    fileprivate static func appKitPoint(_ location: CGPoint) -> CGPoint {
        ScreenGrabber.appKitFrame(fromCoreGraphics: CGRect(origin: location, size: .zero)).origin
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

/// Returning nil swallows the event: the click is drawn for Kestrel and must not also press
/// whatever it was drawn over. Movement is passed on, or the pointer stops dead under the hand.
private let dragTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<DragTracker>.fromOpaque(userInfo).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        tracker.reenable()
        return Unmanaged.passUnretained(event)
    case .leftMouseDown, .rightMouseDown:
        tracker.record(true, at: DragTracker.appKitPoint(event.location))
        return nil
    case .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp:
        tracker.record(false, at: DragTracker.appKitPoint(event.location))
        // Drags travel on so the pointer keeps moving; the press and release that would have made
        // them mean anything to the app underneath were already swallowed.
        return DragTracker.swallows(type) ? nil : Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
