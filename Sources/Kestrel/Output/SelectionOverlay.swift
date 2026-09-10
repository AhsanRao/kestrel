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

    /// On release the freehand trail snaps to the box that is actually being sent, holds for a
    /// beat, then goes. Without it the user never sees what region their scribble became.
    func settle(_ rect: CGRect?) {
        guard let rect else { return hide() }
        model.settled = rect
        model.points = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.hide() }
    }

    func hide() {
        model.points = []
        model.settled = nil
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
    /// The bounding box the trail became, shown briefly after the user lets go.
    @Published var settled: CGRect?
    var origin: CGPoint = .zero
    var size: CGSize = .zero
}

private struct SelectionView: View {
    @ObservedObject var model: SelectionModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let local = model.points.map(local)
                guard local.count > 1 else { return }

                var path = Path()
                path.addLines(local)
                context.addFilter(.blur(radius: 9))
                context.stroke(path, with: .color(KestrelPalette.accentOnDark.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                context.addFilter(.blur(radius: 0))
                context.stroke(path, with: .color(KestrelPalette.accentOnDark.opacity(0.95)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let box = settledInView {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(KestrelPalette.accentOnDark, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    .background(KestrelPalette.accentOnDark.opacity(0.10))
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .transition(.scale(scale: 1.06).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.settled)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - model.origin.x, y: model.size.height - (point.y - model.origin.y))
    }

    private var settledInView: CGRect? {
        guard let rect = model.settled else { return nil }
        return CGRect(x: rect.minX - model.origin.x,
                      y: model.size.height - (rect.maxY - model.origin.y),
                      width: rect.width, height: rect.height)
    }
}
