import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

/// Captures what the user is asking about via `/usr/sbin/screencapture -x`.
///
/// By default that is the **frontmost window**, not the whole desktop. A 5K display squeezed into
/// the 1568 px a vision model actually receives turns every label into mush — which is why the
/// model kept asking to zoom in. One window fills the same budget with the pixels that matter.
enum ScreenGrabber {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "screen")

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Blocking; call from a background queue.
    static func capture(maxEdge: Int, mode: Config.CaptureMode = .window) throws -> ScreenCapture {
        guard hasPermission else { throw KestrelError.screenRecordingDenied }

        if mode == .window, let window = frontmostWindow() {
            if let capture = try? shoot(["-o", "-l", String(window.id)], frame: window.frame, maxEdge: maxEdge) {
                log.debug("captured window \(window.id) at \(Int(window.frame.width))x\(Int(window.frame.height))pt")
                return capture
            }
            log.info("window capture failed, falling back to the display")
        }

        let display = activeDisplay()
        var arguments = ["-o"]
        if let index = display.index { arguments += ["-D", String(index)] }
        return try shoot(arguments, frame: display.frame, maxEdge: maxEdge)
    }

    // MARK: - screencapture

    private static func shoot(_ arguments: [String], frame: CGRect, maxEdge: Int) throws -> ScreenCapture {
        let raw = Paths.temporaryFile(ext: "png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-x", "-t", "png"] + arguments + [raw.path]   // -x silent
        let errPipe = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            throw KestrelError.screenshotFailed(error.localizedDescription)
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        guard task.terminationStatus == 0, FileManager.default.fileExists(atPath: raw.path),
              pixelSize(of: raw).width > 0 else {
            try? FileManager.default.removeItem(at: raw)
            let detail = String(data: errData, encoding: .utf8) ?? "exit \(task.terminationStatus)"
            throw KestrelError.screenshotFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let final = downscale(raw, maxEdge: maxEdge) ?? raw
        return ScreenCapture(url: final, captureFrame: frame, pixelSize: pixelSize(of: final))
    }

    // MARK: - What to capture

    /// The frontmost app's main window: its id for `screencapture -l`, and its frame in AppKit
    /// points. Skips windows too small to be worth asking about, like palettes and HUDs.
    static func frontmostWindow() -> (id: CGWindowID, frame: CGRect)? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let candidates = windows.compactMap { window -> (CGWindowID, CGRect)? in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid == frontmost,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return nil }
            return (id, rect)
        }
        guard let biggest = candidates.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }),
              biggest.1.width >= 320, biggest.1.height >= 240 else { return nil }
        return (biggest.0, appKitFrame(fromCoreGraphics: biggest.1))
    }

    /// CoreGraphics measures down from the top-left of the primary display; AppKit measures up.
    static func appKitFrame(fromCoreGraphics rect: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let height = primary?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 1-based index into the active display list, which is what `screencapture -D` expects.
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

    /// Cuts the circled region out of a capture and writes it as its own PNG, which is sent
    /// alongside the full frame so the model knows what the user pointed at (spec §8.16).
    static func crop(_ capture: ScreenCapture, to screenRect: CGRect) -> URL? {
        guard let pixels = capture.pixelRect(forScreenRect: screenRect),
              let source = CGImageSourceCreateWithURL(capture.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = image.cropping(to: pixels.integral) else { return nil }

        let url = Paths.temporaryFile(ext: "png")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        log.debug("cropped focus region \(cropped.width)x\(cropped.height)")
        return url
    }

    // MARK: - Image

    static func pixelSize(of url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return .zero }
        return CGSize(width: width, height: height)
    }

    /// Rewrites the PNG at a smaller size. Returns nil (keep the original) on any failure.
    private static func downscale(_ url: URL, maxEdge: Int) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let size = pixelSize(of: url)
        guard max(size.width, size.height) > CGFloat(maxEdge) else { return url }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let scaled = Paths.temporaryFile(ext: "png")
        guard let destination = CGImageDestinationCreateWithURL(
            scaled as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        try? FileManager.default.removeItem(at: url)
        log.debug("screenshot \(Int(size.width))x\(Int(size.height)) → \(thumbnail.width)x\(thumbnail.height)")
        return scaled
    }
}
