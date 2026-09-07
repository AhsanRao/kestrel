import AppKit
import SwiftUI

/// A piece of writing Kestrel produced, shown so it can be taken away.
///
/// An email is not an answer to be listened to. It is a thing the user asked for in order to use it
/// somewhere else, and everything they will do next is select, copy, paste. So it gets a surface of
/// its own — monospaced, selectable, scrollable when it is long — with the copy button that is the
/// whole point of it, and it is never spoken.
struct DraftCard: View {
    let draft: Draft
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let subject = draft.subject, !subject.isEmpty {
                    Text(subject)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text("Draft")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 8)
                copyButton
            }
            // Long drafts scroll rather than growing the island past the screen. Short ones sit at
            // their own height, so a two-line reply does not get a scroller it has no use for.
            ScrollView(.vertical) {
                Text(draft.body)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.92))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
    }

    private var copyButton: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(draft.forClipboard, forType: .string)
            // The label confirms it rather than a toast: the button the user just pressed is
            // already where they are looking.
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeOut(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .bold))
                Text(copied ? "Copied" : "Copy")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(copied ? KestrelPalette.navy : .white.opacity(0.9))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(copied ? KestrelPalette.cyan : Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
