import AppKit
import SwiftUI

/// The glass Kestrel's windows are made of.
///
/// `.menu` is the material AppKit gives an `NSMenu`, so a window backed by it *is* the same glass
/// as the menu bar dropdown rather than an imitation of it — the same blur and tint, and the same
/// behaviour when the desktop moves behind it, when the system switches to dark, or when Reduce
/// Transparency asks for something solid. A hand-rolled blur would get none of that for free.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A raised surface *on* the glass: a card, a row group, a meter's track.
///
/// Deliberately a thin white wash and a hairline rather than a second blur. Stacking a translucent
/// surface on a translucent surface is what turns glass into soup, and the text on top of it has to
/// stay readable at a glance.
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
        )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

extension NSWindow {
    /// Lets the glass run edge to edge, titlebar included. Without `fullSizeContentView` the strip
    /// behind the titlebar keeps the window's own background, and a clear background there shows
    /// the desktop straight through — a transparent notch across the top of the window.
    func applyGlassChrome() {
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        styleMask.insert(.fullSizeContentView)
        isMovableByWindowBackground = true
    }
}
