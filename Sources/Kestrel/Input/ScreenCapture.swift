import CoreGraphics
import Foundation

/// A screenshot, and where a rectangle on the screen falls inside it.
///
/// Kestrel does not ask a model for coordinates at all: it offers a numbered list of real controls
/// read from macOS and the model picks one, because locating a small control in a resized
/// screenshot is genuinely hard for a vision model while reading an exact frame out of the
/// Accessibility tree is free and correct. All the arithmetic for translating a model's own grid
/// back onto the display went with the walkthroughs that needed it. What remains is the one
/// conversion the circled-region crop still makes — AppKit measures up from the bottom, a PNG
/// counts down from the top.
struct ScreenCapture: Equatable {
    var url: URL
    /// Frame of whatever was captured — the front window, or the whole display — in global
    /// AppKit points (origin bottom-left).
    var captureFrame: CGRect
    /// Pixel size of the PNG actually handed to the model. Not used for mapping — kept for logs.
    var pixelSize: CGSize

    /// Where a global screen rect falls inside the captured PNG, in its pixels.
    func pixelRect(forScreenRect rect: CGRect) -> CGRect? {
        guard captureFrame.width > 0, captureFrame.height > 0, pixelSize.width > 0 else { return nil }
        let clipped = rect.intersection(captureFrame)
        guard clipped.width > 8, clipped.height > 8 else { return nil }
        let scaleX = pixelSize.width / captureFrame.width
        let scaleY = pixelSize.height / captureFrame.height
        return CGRect(x: (clipped.minX - captureFrame.minX) * scaleX,
                      y: (captureFrame.maxY - clipped.maxY) * scaleY,   // PNG counts down from the top
                      width: clipped.width * scaleX,
                      height: clipped.height * scaleY)
    }

}
