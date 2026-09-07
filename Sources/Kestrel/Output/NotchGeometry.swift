import AppKit
import SwiftUI

/// Where the notch is on the display the user is looking at, and how big a strip to leave for it.
///
/// Kestrel's panel hangs from the top edge of the screen rather than floating below it, so on a
/// MacBook with a notch it reads as the notch itself growing to say something. On a display without
/// one the same shape simply slides out of the top edge, which is the behaviour people already know
/// from the Dynamic Island — the illusion does not depend on the hardware.
struct NotchMetrics: Equatable {
    /// The camera housing's size in points. `.zero` on a display without a notch.
    var notchSize: CGSize
    var screenFrame: CGRect

    var hasNotch: Bool { notchSize.width > 1 }
    /// The strip along the top the content must stay clear of.
    ///
    /// A couple of points taller than the housing on purpose. `safeAreaInsets.top` is the menu bar
    /// inset, which the housing fills to within a point or two, and the window frame is rounded to
    /// whole points on top of that — so a bar sized to the inset exactly leaves the bottom edge of
    /// the housing showing beneath it as a faint step. Overshooting hides it; the island reads as
    /// the notch either way, because both are black.
    var barHeight: CGFloat { hasNotch ? notchSize.height + NotchMetrics.housingOvershoot : 30 }

    /// How far the bar hangs below the camera housing, so no edge of the housing is left visible.
    static let housingOvershoot: CGFloat = 4

    static let none = NotchMetrics(notchSize: .zero, screenFrame: .zero)

    /// Reads the notch off the screen under the mouse, which is the one the user is working on.
    static func current() -> NotchMetrics {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return .none }
        return metrics(for: screen)
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        // `auxiliaryTopLeftArea` is the usable menu bar strip to the left of the housing; what is
        // left over between the two auxiliary areas is the housing itself. On a screen without a
        // notch there are no auxiliary areas and the safe area inset is zero.
        let inset = screen.safeAreaInsets.top
        guard inset > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return NotchMetrics(notchSize: .zero, screenFrame: screen.frame)
        }
        let width = max(screen.frame.width - left.width - right.width, 0)
        return NotchMetrics(notchSize: CGSize(width: width, height: inset), screenFrame: screen.frame)
    }
}

/// The panel's outline: square against the top of the screen, rounded at the bottom, and flaring
/// into the screen edge at the shoulders so it looks grown out of it rather than stuck onto it.
struct NotchShape: Shape {
    var bottomRadius: CGFloat = 20
    /// The concave flare where the panel meets the top edge of the display.
    var shoulder: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        let bottom = min(bottomRadius, rect.height / 2)
        let flare = min(shoulder, rect.width / 4)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left shoulder: curves inward and down, so the top edge appears to widen into the screen.
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare),
                          control: CGPoint(x: rect.minX + flare, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - flare, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
