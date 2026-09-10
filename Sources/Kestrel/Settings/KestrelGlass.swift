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
                .fill(KestrelPalette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(KestrelPalette.surfaceBorder, lineWidth: 1)
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

/// Kestrel's primary action: the brand's cyan, with the logo's navy on top of it.
///
/// The stock prominent button takes whatever accent colour the Mac is set to, which is why it was
/// a blue with nothing to do with Kestrel — and tinting it with the logo's blue only made it a
/// duller version of the same thing. Cyan is the mark's actual accent, and navy on cyan reads at
/// 11:1 in either theme, which white on cyan does not. It is the pairing the draft card's Copy
/// button already uses.
struct KestrelPrimaryButton: ButtonStyle {
    var size: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(KestrelPalette.navy)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(KestrelPalette.accent.opacity(configuration.isPressed ? 0.78 : 1),
                        in: Capsule())
            // Feedback on the press, not on the release — anything else reads as lag.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// The quieter one beside it: same shape, no fill.
struct KestrelSecondaryButton: ButtonStyle {
    var size: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(KestrelPalette.surfaceStrong.opacity(configuration.isPressed ? 1.6 : 1),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(KestrelPalette.surfaceBorder, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
