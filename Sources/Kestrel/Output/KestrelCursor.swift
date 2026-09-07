import SwiftUI

/// Kestrel's own pointer — the thing that draws the marks and rests on whatever is being talked
/// about.
///
/// It is deliberately *not* the system cursor. The user's pointer is never moved, never borrowed
/// and never hidden: two pointers on screen, one of them plainly not theirs, is the difference
/// between watching an assistant work and having your Mac taken away from you. So this one is
/// cyan, slightly smaller than the real arrow, and carries a soft glow no system cursor has.
struct KestrelCursor: View {
    /// Fades and shrinks the cursor as it settles, so a mark that is finished is not competing with
    /// the control it points at.
    var isDrawing: Bool = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            CursorArrow()
                .fill(KestrelPalette.cyan)
                .overlay(CursorArrow().stroke(Color.black.opacity(0.35), lineWidth: 0.75))
                .frame(width: 15, height: 22)
                .shadow(color: KestrelPalette.cyan.opacity(0.65), radius: isDrawing ? 8 : 4)
        }
        .frame(width: 15, height: 22, alignment: .topLeading)
        // The tip is the top-left corner of the glyph, so the whole thing hangs down-right of the
        // point it is actually pointing at — exactly like the real cursor.
        .offset(x: 0.5, y: 0.5)
        .opacity(isDrawing ? 1 : 0.85)
        .scaleEffect(isDrawing ? 1 : 0.92, anchor: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The arrow itself: the familiar pointer silhouette, drawn from its tip.
struct CursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height * 0.86))
        path.addLine(to: CGPoint(x: width * 0.29, y: height * 0.65))
        path.addLine(to: CGPoint(x: width * 0.48, y: height))
        path.addLine(to: CGPoint(x: width * 0.70, y: height * 0.91))
        path.addLine(to: CGPoint(x: width * 0.51, y: height * 0.58))
        path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.56))
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// A short trail behind the cursor while it is drawing, so the eye can find it on a busy screen.
struct CursorHalo: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(colors: [KestrelPalette.cyan.opacity(0.35), .clear],
                               center: .center, startRadius: 0, endRadius: 15)
            )
            .frame(width: 30, height: 30)
            .allowsHitTesting(false)
    }
}
