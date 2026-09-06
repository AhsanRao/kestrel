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
    static func capture(maxEdge: Int) throws -> URL {
        guard hasPermission else { throw KestrelError.screenRecordingDenied }

        let raw = Paths.temporaryFile(ext: "png")
        var arguments = ["-x", "-o", "-t", "png"]           // -x silent, -o no window shadow
        if let index = activeDisplayIndex() { arguments += ["-D", String(index)] }
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

        return downscale(raw, maxEdge: maxEdge) ?? raw
    }

    /// 1-based index into the active display list, which is what `screencapture -D` expects.
    private static func activeDisplayIndex() -> Int? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        let target = CGDirectDisplayID(number.uint32Value)

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.firstIndex(of: target).map { $0 + 1 }
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
