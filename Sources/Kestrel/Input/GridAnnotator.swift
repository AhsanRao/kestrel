import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

/// Draws a labelled 0–1000 grid over a copy of the screenshot, for walkthrough questions only.
///
/// Asking a model where a control is, in a picture it has silently resized, is guesswork: it
/// answers in its own frame and is roughly a button-width out. Printing the coordinate system onto
/// the image removes the guess — it can read the numbers off the lines nearest the control. The
/// user never sees this copy; it exists only for the walkthrough request.
enum GridAnnotator {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "grid")

    /// Spacing of the labelled lines, in per-mille of the image.
    static let step = 100

    /// Returns a new PNG beside the original, or nil to fall back to the plain screenshot.
    static func annotate(_ source: URL) -> URL? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }

        let width = CGFloat(image.width), height = CGFloat(image.height)
        guard width > 0, height > 0 else { return nil }

        // Labels live in a margin rather than on top of the interface: the menu bar and toolbar are
        // exactly what walkthroughs point at, so nothing may be painted over them.
        let margin = max(30, (height / 26).rounded())
        let canvasWidth = Int(width + margin), canvasHeight = Int(height + margin)

        guard let context = CGContext(data: nil, width: canvasWidth, height: canvasHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        context.setFillColor(CGColor(gray: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(canvasWidth), height: CGFloat(canvasHeight)))
        // Origin is bottom-left, so the image sits at the bottom-right of the canvas, leaving the
        // margin along the top and left edges.
        let frame = CGRect(x: margin, y: 0, width: width, height: height)
        context.draw(image, in: frame)
        draw(on: context, image: frame, margin: margin)

        guard let annotated = context.makeImage() else { return nil }
        let url = Paths.temporaryFile(ext: "png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, annotated, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        log.debug("annotated grid onto \(Int(width))x\(Int(height))")
        return url
    }

    /// Two-tone lines so they stay visible over both dark and light interfaces.
    private static func draw(on context: CGContext, image: CGRect, margin: CGFloat) {
        let thin = max(image.width / 1400, 1.0)
        let fontSize = max(margin * 0.55, 11)
        context.setLineCap(.butt)

        for unit in stride(from: 0, through: 1000, by: step) {
            let major = unit % 500 == 0
            let x = image.minX + image.width * CGFloat(unit) / 1000
            let y = image.minY + image.height * CGFloat(1000 - unit) / 1000

            if unit > 0 && unit < 1000 {
                for (gray, offset, alpha) in [(0.0, thin, 0.30), (1.0, 0.0, 0.55)] {
                    context.setStrokeColor(CGColor(gray: gray, alpha: major ? alpha + 0.15 : alpha))
                    context.setLineWidth(major ? thin * 2 : thin)
                    context.beginPath()
                    context.move(to: CGPoint(x: x + offset, y: image.minY))
                    context.addLine(to: CGPoint(x: x + offset, y: image.maxY))
                    context.move(to: CGPoint(x: image.minX, y: y - offset))
                    context.addLine(to: CGPoint(x: image.maxX, y: y - offset))
                    context.strokePath()
                }
            }

            // x label in the top margin, y label in the left margin.
            label("\(unit)", centredAt: CGPoint(x: x, y: image.maxY + margin / 2),
                  context: context, size: fontSize)
            label("\(unit)", centredAt: CGPoint(x: margin / 2, y: y), context: context, size: fontSize)
        }
    }

    private static func label(_ text: String, centredAt point: CGPoint,
                              context: CGContext, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let bounds = string.size()
        let origin = CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}
