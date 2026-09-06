// Builds Kestrel's icon assets from the real logo artwork in assets/kestrel-logo.svg.
//
//   swift scripts/icon-tool.swift <logo.png> <out-dir>
//
// The logo ships as a 1254 px raster embedded in the SVG, on an off-white ground. This tool
// lifts that ground to transparency (keeping the anti-aliased edges), then writes:
//   AppIconMaster.png              1024 px, artwork on a squircle
//   MenuBarIcon.png                  36 px, the same artwork as a black template silhouette
//   kestrel-menubar-template.svg    512 px silhouette, the spec's monochrome asset
// No redrawing: every pixel comes from the original file.

import AppKit
import CoreGraphics
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: icon-tool.swift <logo.png> <out-dir>") }
let sourceURL = URL(fileURLWithPath: arguments[1])
let outDirectory = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("could not read \(sourceURL.path)")
}

// MARK: - Read pixels as straight RGBA8

let width = original.width, height = original.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not create bitmap context")
    }
    context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
}

// MARK: - Alpha

// The artwork already carries an alpha channel, so the mark is used exactly as drawn. Only if a
// source turns up fully opaque (a flattened export) is its near-white paper lifted, with the
// anti-aliased edge ramped so nothing gains a jagged outline.
let hasAlpha = stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
let floorDistance: Double = 10, ceilingDistance: Double = 38

var cutout = pixels
var silhouette = [UInt8](repeating: 0, count: pixels.count)

for index in stride(from: 0, to: pixels.count, by: 4) {
    let r = Double(pixels[index]), g = Double(pixels[index + 1]), b = Double(pixels[index + 2])
    let a8: UInt8
    if hasAlpha {
        a8 = pixels[index + 3]
    } else {
        let distance = max(255 - r, max(255 - g, 255 - b))
        let alpha = min(max((distance - floorDistance) / (ceilingDistance - floorDistance), 0), 1)
        a8 = UInt8(alpha * 255)
        cutout[index] = UInt8(r * alpha)          // premultiplied storage
        cutout[index + 1] = UInt8(g * alpha)
        cutout[index + 2] = UInt8(b * alpha)
        cutout[index + 3] = a8
    }
    silhouette[index] = 0                         // black ink
    silhouette[index + 1] = 0
    silhouette[index + 2] = 0
    silhouette[index + 3] = a8
}

func image(from data: [UInt8]) -> CGImage {
    var copy = data
    let provider = CGDataProvider(data: Data(bytes: &copy, count: copy.count) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true,
                   intent: .defaultIntent)!
}

// MARK: - Trim to the ink, so the artwork can be centred properly

func inkBounds(_ data: [UInt8]) -> CGRect {
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where data[(y * width + x) * 4 + 3] > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return CGRect(x: 0, y: 0, width: width, height: height) }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let bounds = inkBounds(cutout)
let artwork = image(from: cutout).cropping(to: bounds)!
let mark = image(from: silhouette).cropping(to: bounds)!

// MARK: - Writers

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fail("could not write \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("could not finalise \(url.path)") }
}

func canvas(_ size: Int, _ draw: (CGContext) -> Void) -> CGImage {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fail("could not create canvas")
    }
    context.interpolationQuality = .high
    draw(context)
    return context.makeImage()!
}

/// Fits `image` inside a square of `size`, inset on every edge, preserving aspect ratio.
func fitted(_ image: CGImage, size: Int, inset: CGFloat) -> CGRect {
    let available = CGFloat(size) - inset * 2
    let scale = min(available / CGFloat(image.width), available / CGFloat(image.height))
    let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
    return CGRect(x: (CGFloat(size) - w) / 2, y: (CGFloat(size) - h) / 2, width: w, height: h)
}

// App icon: the artwork on the logo's own paper colour, in a macOS squircle.
let iconSize = 1024
let appIcon = canvas(iconSize) { context in
    let rect = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
    let path = CGPath(roundedRect: rect, cornerWidth: 228, cornerHeight: 228, transform: nil)
    context.addPath(path)
    context.setFillColor(CGColor(red: 0.969, green: 0.969, blue: 0.965, alpha: 1))  // #F7F7F6
    context.fillPath()
    context.draw(artwork, in: fitted(artwork, size: iconSize, inset: 96))
}
write(appIcon, to: outDirectory.appendingPathComponent("AppIconMaster.png"))

// Menu bar: black template silhouette of the same artwork.
let menuSize = 36
let menuBar = canvas(menuSize) { context in
    context.draw(mark, in: fitted(mark, size: menuSize, inset: 1))
}
write(menuBar, to: outDirectory.appendingPathComponent("MenuBarIcon.png"))

// The spec names a monochrome SVG asset; it wraps the same silhouette so the two can never drift.
let templateSize = 512
let template = canvas(templateSize) { context in
    context.draw(mark, in: fitted(mark, size: templateSize, inset: 8))
}
let templateData = NSMutableData()
if let destination = CGImageDestinationCreateWithData(templateData, "public.png" as CFString, 1, nil) {
    CGImageDestinationAddImage(destination, template, nil)
    CGImageDestinationFinalize(destination)
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" \
viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="Kestrel">
  <!-- Generated by scripts/icon-tool.swift from assets/kestrel-logo.svg. Do not edit by hand.
       Black silhouette on transparency, for use as an AppKit template image. -->
  <image width="512" height="512" href="data:image/png;base64,\
\(( templateData as Data ).base64EncodedString())"/>
</svg>

"""
try? svg.write(to: outDirectory.appendingPathComponent("kestrel-menubar-template.svg"),
               atomically: true, encoding: .utf8)

print("source alpha: \(hasAlpha ? "present" : "lifted from paper")")
print("ink bounds \(Int(bounds.width))x\(Int(bounds.height)) of \(width)x\(height)")
print("wrote AppIconMaster.png, MenuBarIcon.png, kestrel-menubar-template.svg")
