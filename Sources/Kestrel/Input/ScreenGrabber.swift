import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

/// Captures the display the mouse is on — not every display — via `/usr/sbin/screencapture -x`,
/// then downscales so the PNG stays cheap to send (spec §8.3).
enum ScreenGrabber {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "screen")

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Blocking; call from a background queue. The panel must already be hidden or ordered out.
    /// Returns the PNG together with the geometry needed to map model coordinates back to screen
    /// points, which the v2 walkthrough overlay depends on.
    static func capture(maxEdge: Int) throws -> ScreenCapture {
        guard hasPermission else { throw KestrelError.screenRecordingDenied }

        let display = activeDisplay()
        let raw = Paths.temporaryFile(ext: "png")
        var arguments = ["-x", "-o", "-t", "png"]           // -x silent, -o no window shadow
        if let index = display.index { arguments += ["-D", String(index)] }
        arguments.append(raw.path)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = arguments
        let errPipe = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            throw KestrelError.screenshotFailed(error.localizedDescription)
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: raw.path) else {
            let detail = String(data: errData, encoding: .utf8) ?? "exit \(task.terminationStatus)"
            throw KestrelError.screenshotFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let final = downscale(raw, maxEdge: maxEdge) ?? raw
        return ScreenCapture(url: final, displayFrame: display.frame, pixelSize: pixelSize(of: final))
    }

    /// The display under the mouse: its 1-based index for `screencapture -D`, and its frame in
    /// global AppKit points.
    private static func activeDisplay() -> (index: Int?, frame: CGRect) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return (nil, frame) }
        let target = CGDirectDisplayID(number.uint32Value)

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return (nil, frame) }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return (nil, frame) }
        return (displays.firstIndex(of: target).map { $0 + 1 }, frame)
    }

    static func pixelSize(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return .zero }
        return CGSize(width: width, height: height)
    }

    /// Rewrites the PNG in place at a smaller size. Returns nil (keep the original) on any failure.
    private static func downscale(_ url: URL, maxEdge: Int) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        guard max(width, height) > maxEdge else { return url }

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let scaled = Paths.temporaryFile(ext: "png")
        guard let destination = CGImageDestinationCreateWithURL(
            scaled as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        try? FileManager.default.removeItem(at: url)
        log.debug("screenshot \(width)x\(height) → \(thumbnail.width)x\(thumbnail.height)")
        return scaled
    }
}
