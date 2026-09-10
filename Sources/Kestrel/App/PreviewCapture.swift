import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// The one screenshot routine the preview probes share.
///
/// `CGWindowListCreateImage` is deprecated in macOS 14 and kept anyway. The replacement,
/// ScreenCaptureKit, is async and wants the main run loop — which a probe blocks. And
/// `/usr/sbin/screencapture`, which `ScreenGrabber` uses for real captures, is worse here: as a
/// subprocess its Screen Recording grant is judged against whatever launched Kestrel, so it fails
/// from a terminal, which is precisely where these are run from.
enum PreviewCapture {
    /// How long to let things settle before the shutter, and where to put the file. A probe with no
    /// `KESTREL_PREVIEW_OUT` just leaves the window open to be looked at by hand.
    static var destination: URL? {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"].map { URL(fileURLWithPath: $0) }
    }

    static func delay(default fallback: Double) -> Double {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_DELAY"].flatMap(Double.init) ?? fallback
    }

    /// Photograph, then quit. The extra beat after the shutter is for the file to land.
    static func shoot(after seconds: Double, _ region: @escaping () -> CGRect) {
        guard let url = destination else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            write(region(), to: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
    }

    /// The whole desktop — for the island and the overlays, where the surrounding screen is the
    /// context the picture is being taken for.
    static let wholeScreen: () -> CGRect = { .infinite }

    /// One window and the breathing room around it, so a shot of a 540-point panel is not mostly
    /// wallpaper. Screen coordinates run from the top down and AppKit's from the bottom up, hence
    /// the flip.
    @MainActor
    static func around(_ window: NSWindow?, margin: CGFloat = 24) -> () -> CGRect {
        {
            guard let window, let screen = window.screen ?? NSScreen.main else { return .infinite }
            let frame = window.frame.insetBy(dx: -margin, dy: -margin)
            return CGRect(x: frame.minX,
                          y: screen.frame.maxY - frame.maxY,
                          width: frame.width,
                          height: frame.height)
        }
    }

    /// Straight away, on whatever queue is asking — `MenuPreview` has to shoot from a background
    /// queue, because menu tracking runs a modal loop that starves the main one.
    static func now(_ region: CGRect) {
        guard let url = destination else { return }
        write(region, to: url)
    }

    private static func write(_ region: CGRect, to url: URL) {
        guard let image = CGWindowListCreateImage(
                region, .optionAll, kCGNullWindowID, [.bestResolution]),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
