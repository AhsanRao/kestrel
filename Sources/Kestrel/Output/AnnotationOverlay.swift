import AppKit
import SwiftUI

/// Marks on the real screen that go with a spoken answer.
///
/// This is the difference between an assistant and a chat window: when the answer is "click Share
/// in the toolbar", the toolbar button gets circled while the sentence is being said, so the user
/// never has to translate a description of a location into a place to look. Click-through, never
/// focused, and excluded from capture like every other Kestrel window.
final class AnnotationOverlay {
    let model = AnnotationOverlayModel()

    private var window: NSWindow?
    private var hideWork: DispatchWorkItem?

    /// Told whenever the marks leave the screen, so whatever was watching for Esc can stop.
    var onHide: (() -> Void)?

    func show(_ annotations: [Annotation]) {
        guard !annotations.isEmpty else { return hide() }
        hideWork?.cancel()
        // Geometry before the view: a mark laid out against a zero frame starts off screen, and
        // the correction then arrives on the same render pass as the drawing animation.
        let bounds = AnnotationOverlayModel.desktopBounds
        model.windowFrame = bounds
        let window = ensureWindow()
        model.annotations = annotations
        model.generation += 1
        window.setFrame(bounds, display: true)
        window.orderFrontRegardless()
    }

    /// Marks outlive the panel by a moment: the user is usually still looking at the control when
    /// the answer has finished being spoken.
    func hide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        let wasShowing = !model.annotations.isEmpty
        model.annotations = []
        window?.orderOut(nil)
        if wasShowing { onHide?() }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// For `OverlayPreview` only: lift the capture exclusion so the marks can be photographed.
    func setExcludedFromCapture(_ excluded: Bool) {
        window?.sharingType = excluded ? .none : .readOnly
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: AnnotationView(model: model))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}

final class AnnotationOverlayModel: ObservableObject {
    @Published var annotations: [Annotation] = []
    /// Bumped per answer so each new set of marks draws itself rather than appearing whole.
    @Published var generation = 0

    @Published var windowFrame: CGRect = .zero

    /// A mark's frame inside the overlay window, which spans every display.
    func viewRect(for frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - windowFrame.minX,
               y: windowFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }

    /// The union of every display, which is what the overlay window covers.
    static var desktopBounds: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }
}
