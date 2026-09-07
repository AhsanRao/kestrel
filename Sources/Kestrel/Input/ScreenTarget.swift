import AppKit
import ApplicationServices

/// Something on screen that an answer can point at.
///
/// Kestrel used to offer the model only *clickable* controls, which is why an answer about a page's
/// layout had nothing to draw on: "tighten the card spacing" is about a region, and a region is not
/// a button. A target is either kind — the button you press, or the block of content you are
/// talking about — numbered in one list so the model can name either without knowing the difference.
struct ScreenTarget: Equatable {
    enum Kind: String, Equatable {
        case control    // a thing you can click
        case region     // a heading, a card, an image, a paragraph, a table
    }

    var id: Int
    var label: String
    var role: String
    /// Global AppKit points, origin bottom-left.
    var frame: CGRect
    var kind: Kind
    /// The live handle, so the frame can be re-read at the moment of drawing.
    var ref: AXUIElement?

    init(id: Int, label: String, role: String, frame: CGRect, kind: Kind, ref: AXUIElement? = nil) {
        self.id = id
        self.label = label
        self.role = role
        self.frame = frame
        self.kind = kind
        self.ref = ref
    }

    static func == (lhs: ScreenTarget, rhs: ScreenTarget) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.role == rhs.role
            && lhs.frame == rhs.frame && lhs.kind == rhs.kind
    }

    /// "12. Sign in  (button)" — the line the model chooses from.
    var listing: String {
        "\(id). \(label)  (\(AXElementScanner.friendlyRole(role)))"
    }

    /// Where this is **now**. The scan happened before the model was asked.
    var currentFrame: CGRect? {
        guard let ref, let frame = AXElementScanner.frame(of: ref),
              AXElementScanner.isOnScreen(frame) else { return nil }
        return frame
    }

    /// A big block of content wants a box round it; a small square control wants a circle.
    var preferredShape: Annotation.Shape {
        guard kind == .control else { return .rect }
        return frame.width / max(frame.height, 1) > 2.2 ? .rect : .circle
    }
}

extension AXElementScanner.Element {
    var asTarget: ScreenTarget {
        ScreenTarget(id: id, label: label, role: role, frame: frame, kind: .control, ref: ref)
    }
}
