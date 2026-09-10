import AppKit

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
        guard PreviewCapture.destination != nil else { return menu.popUpForPreview() }
        // Off the main queue, and so not `PreviewCapture.shoot`, which schedules on it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
            PreviewCapture.now(PreviewCapture.wholeScreen())
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        menu.popUpForPreview()
    }
}
