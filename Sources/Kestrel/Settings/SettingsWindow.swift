import AppKit
import SwiftUI

/// Plain titled window hosting `SettingsView`. Kestrel is an accessory app, so the window has to
/// activate the app explicitly or it opens behind everything.
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if window == nil { window = build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.center()
    }

    private func build() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Kestrel Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 560))
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
