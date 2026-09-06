import AppKit
import SwiftUI

/// Draws the trail while the user circles part of the screen, on a click-through window over the
/// display they are drawing on.
final class SelectionOverlay {
    let model = SelectionModel()
    private var window: NSWindow?

    func show() {
        let window = ensureWindow()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        model.origin = frame.origin
        model.size = frame.size
        window.setFrame(frame, display: false)
        window.orderFrontRegardless()
    }

    func update(points: [CGPoint]) {
        model.points = points
    }

    func hide() {
        model.points = []
        window?.orderOut(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: SelectionView(model: model))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none          // never part of the screenshot it is describing
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }
}

final class SelectionModel: ObservableObject {
    @Published var points: [CGPoint] = []
    var origin: CGPoint = .zero
    var size: CGSize = .zero
}

private struct SelectionView: View {
    @ObservedObject var model: SelectionModel

    var body: some View {
        Canvas { context, _ in
            let local = model.points.map {
                CGPoint(x: $0.x - model.origin.x, y: model.size.height - ($0.y - model.origin.y))
            }
            guard local.count > 1 else { return }

            var path = Path()
            path.addLines(local)
            context.stroke(path, with: .color(KestrelPalette.cyan.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            context.addFilter(.blur(radius: 8))
            context.stroke(path, with: .color(KestrelPalette.cyan.opacity(0.45)),
                           style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}
