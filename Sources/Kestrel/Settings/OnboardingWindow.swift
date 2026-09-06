import AppKit
import SwiftUI

/// Hosts `OnboardingView`. Kestrel is an accessory app with no Dock icon, so the window has to
/// activate the app itself or it opens behind whatever the user is doing.
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private var window: NSWindow?

    var onFinish: (() -> Void)?

    func show() {
        if window == nil { window = build() }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func build() -> NSWindow {
        let hosting = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
            self?.model.markCompleted()
            self?.close()
            self?.onFinish?()
        })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Kestrel"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
    }
}
