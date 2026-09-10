import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Photographs the menu bar dropdown. `KESTREL_PREVIEW_MENU=1`.
///
/// Menu tracking runs its own modal loop on the main thread, so nothing scheduled there fires while
/// the menu is down. The capture is therefore taken from a background queue — the only probe here
/// that has to be.
enum MenuPreview {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["KESTREL_PREVIEW_MENU"] != nil
    }

    @MainActor
    static func run(on menu: StatusMenu) {
        guard let path = ProcessInfo.processInfo.environment["KESTREL_PREVIEW_OUT"] else {
            return menu.popUpForPreview()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            capture(to: URL(fileURLWithPath: path))
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        menu.popUpForPreview()
    }

    private static func capture(to url: URL) {
        guard let image = CGWindowListCreateImage(
            .infinite, .optionAll, kCGNullWindowID, [.bestResolution]),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
