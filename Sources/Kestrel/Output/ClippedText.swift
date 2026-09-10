import AppKit
import SwiftUI

/// Text cut off at a line count, saying how much of it did not fit.
///
/// The island grows to its content, but not without end: a long answer or a long draft stops at a
/// line limit. Stopping silently is the problem — the last line reads as the last line, and there
/// is nothing to suggest otherwise. This measures the same string at its own width and says what
/// was left out.
struct ClippedText: View {
    let text: String
    let font: NSFont
    var lineSpacing: CGFloat = 0
    let limit: Int
    var color: Color = KestrelPalette.onHousing
    /// What to say about the lines that did not fit.
    let note: (Int) -> String

    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(Font(font))
                .lineSpacing(lineSpacing)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .lineLimit(limit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MeasuresWidth { width = $0 })
            if hidden > 0 {
                Text(note(hidden))
                    .font(.system(size: 11))
                    .foregroundStyle(KestrelPalette.onHousingSecondary)
            }
        }
    }

    private var hidden: Int {
        TextFit.overflow(text, font: font, lineSpacing: lineSpacing, width: width, limit: limit)
    }
}

/// Reports the width its content was given, which is the width the text has to be measured at.
struct MeasuresWidth: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { onChange(geometry.size.width) }
                .onChange(of: geometry.size.width) { _, width in onChange(width) }
        }
    }
}
