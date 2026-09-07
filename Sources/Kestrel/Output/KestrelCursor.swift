import SwiftUI

/// The pencil Kestrel draws with.
///
/// It is deliberately *not* a pointer. The user's cursor is never moved, borrowed or hidden, and a
/// second arrow on screen invites exactly the reading that it has been — a pencil says plainly that
/// what is happening is drawing, not clicking. Its point sits on the origin of its frame, which is
/// the place on the stroke it has reached.
struct KestrelCursor: View {
    /// Dims a little once the stroke is finished, so a completed mark stops competing with the
    /// thing it points at.
    var isDrawing: Bool = true

    static let size = CGSize(width: 26, height: 26)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Pencil(part: .body)
                .fill(KestrelPalette.cyan)
            Pencil(part: .nib)
                .fill(KestrelPalette.navy)
            Pencil(part: .body)
                .stroke(Color.black.opacity(0.30), lineWidth: 0.75)
        }
        .frame(width: KestrelCursor.size.width, height: KestrelCursor.size.height,
               alignment: .topLeading)
        .shadow(color: KestrelPalette.cyan.opacity(0.7), radius: isDrawing ? 8 : 4)
        .opacity(isDrawing ? 1 : 0.85)
        .scaleEffect(isDrawing ? 1 : 0.92, anchor: .topLeading)
        .allowsHitTesting(false)
    }
}

/// A pencil lying at 45°, its point on the origin.
///
/// Built along its own axis and then rotated, rather than by writing seven rotated corners out by
/// hand: the first attempt did the latter, and the two sides of the barrel ended up two points
/// apart, which at this size is a line rather than a pencil.
struct Pencil: Shape {
    enum Part {
        /// The whole silhouette: sharpened point, barrel, flat end.
        case body
        /// Just the sharpened point, so it can be filled darker.
        case nib
    }

    var part: Part = .body

    /// Along the pencil, in points, from the tip.
    private static let nibLength: CGFloat = 7
    private static let length: CGFloat = 21
    private static let halfWidth: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        // Laid out pointing along +x, then turned 45° so it hangs down and to the right of its
        // point, the way a hand holds one.
        let along = Pencil.length, nib = Pencil.nibLength, half = Pencil.halfWidth
        let local: [CGPoint]
        switch part {
        case .body:
            local = [CGPoint(x: 0, y: 0),
                     CGPoint(x: nib, y: -half),
                     CGPoint(x: along, y: -half),
                     CGPoint(x: along, y: half),
                     CGPoint(x: nib, y: half)]
        case .nib:
            local = [CGPoint(x: 0, y: 0),
                     CGPoint(x: nib, y: -half),
                     CGPoint(x: nib, y: half)]
        }

        let angle = CGFloat.pi / 4
        let cosine = cos(angle), sine = sin(angle)
        // Half a barrel's worth of clearance, so the side that swings left of the tip still fits.
        let inset = half * sine + 1

        var path = Path()
        for (index, point) in local.enumerated() {
            let turned = CGPoint(x: point.x * cosine - point.y * sine + inset,
                                 y: point.x * sine + point.y * cosine)
            let placed = CGPoint(x: rect.minX + turned.x, y: rect.minY + turned.y)
            if index == 0 { path.move(to: placed) } else { path.addLine(to: placed) }
        }
        path.closeSubpath()
        return path
    }
}

/// A soft glow under the pencil while it is drawing, so the eye can find it on a busy screen.
struct CursorHalo: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [KestrelPalette.cyan.opacity(0.35), .clear],
                               center: .center, startRadius: 0, endRadius: 16)
            )
            .frame(width: 32, height: 32)
            .allowsHitTesting(false)
    }
}
