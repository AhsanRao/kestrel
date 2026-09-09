import AppKit
import CoreText

/// How many lines a piece of text needs at a given width.
///
/// SwiftUI will clip a `Text` at a line limit and never say that it did, so the island had no way
/// to know it was showing half an answer — and neither did the user. CoreText lays the same string
/// out with the same font and leading and counts the lines it produces.
enum TextFit {
    static func lineCount(_ text: String, font: NSFont, lineSpacing: CGFloat,
                          width: CGFloat) -> Int {
        guard !text.isEmpty, width > 1 else { return 0 }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter,
                                             CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as? [CTLine])?.count ?? 0
    }

    /// Lines that will not fit inside `limit` — zero when all of it shows.
    static func overflow(_ text: String, font: NSFont, lineSpacing: CGFloat,
                         width: CGFloat, limit: Int) -> Int {
        max(0, lineCount(text, font: font, lineSpacing: lineSpacing, width: width) - limit)
    }
}
