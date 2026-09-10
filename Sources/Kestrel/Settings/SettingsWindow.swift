import AppKit
import SwiftUI

/// Plain titled window hosting `SettingsView`. Kestrel is an accessory app, so the window has to
/// activate the app explicitly or it opens behind everything.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    /// Exposed for `SettingsPreview`, which frames its screenshot on the window.
    private(set) var window: NSWindow?

    /// What the sidebar's access light does when pressed. The settings window cannot open the setup
    /// window itself — only the delegate that owns both can — so it is handed in.
    var onOpenSetup: (() -> Void)?

    func show() {
        if window == nil { window = build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func build() -> NSWindow {
        let hosting = NSHostingController(
            rootView: SettingsView(onOpenSetup: { [weak self] in self?.onOpenSetup?() }))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Kestrel"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.applyGlassChrome()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 660, height: 560))
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
