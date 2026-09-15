import CoreGraphics
import Foundation

/// A screenshot, and where a rectangle on the screen falls inside it.
///
/// The model is never asked for coordinates: it picks from a numbered list of real controls read
/// out of the Accessibility tree, which is exact and free, where locating a small control in a
/// resized screenshot is not. The only conversion left is the circled-region crop — AppKit
/// measures up from the bottom, a PNG counts down from the top.
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

    /// The inverse: where a pixel in the PNG is on the screen, in CoreGraphics coordinates (down
    /// from the top-left of the primary display), which is what a synthetic click is posted in.
    /// The model only ever sees the screenshot, so that is the space its coordinates come in.
    func screenPoint(forPixel pixel: CGPoint,
                     primaryHeight: CGFloat = ScreenGrabber.primaryDisplayHeight) -> CGPoint? {
        guard captureFrame.width > 0, captureFrame.height > 0,
              pixelSize.width > 0, pixelSize.height > 0 else { return nil }
        let x = captureFrame.minX + pixel.x * (captureFrame.width / pixelSize.width)
        let appKitY = captureFrame.maxY - pixel.y * (captureFrame.height / pixelSize.height)
        return CGPoint(x: x, y: primaryHeight - appKitY)
    }

    /// The pixel in the PNG for a global AppKit point, for listing controls in the model's terms.
    func pixel(forScreenPoint point: CGPoint) -> CGPoint? {
        guard captureFrame.width > 0, captureFrame.height > 0, pixelSize.width > 0 else { return nil }
        return CGPoint(x: (point.x - captureFrame.minX) * (pixelSize.width / captureFrame.width),
                       y: (captureFrame.maxY - point.y) * (pixelSize.height / captureFrame.height))
    }
}
