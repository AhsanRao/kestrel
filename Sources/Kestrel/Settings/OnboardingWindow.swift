import AppKit
import SwiftUI

/// Hosts `OnboardingView`. Kestrel is an accessory app with no Dock icon, so the window has to
/// activate the app itself or it opens behind whatever the user is doing.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    let model = OnboardingModel()
    private var window: NSWindow?
    private var didFinish = false

    var onFinish: (() -> Void)?

    func show() {
        if window == nil { window = build() }
        model.step = .checklist
        didFinish = false
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    /// Completing means "the user has seen setup", not "everything was granted" — a missing
    /// requirement brings the window back on its own. Closing it counts, or a first run dismissed
    /// with the red button would ask again on every launch forever.
    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        model.markCompleted()
        onFinish?()
    }

    private func build() -> NSWindow {
        let hosting = NSHostingController(rootView: OnboardingView(model: model) { [weak self] in
            self?.finish()
            self?.close()
        })
        let window = NSWindow(contentViewController: hosting)
        // The same name the window gives itself in its heading, and still true the second time it
        // is opened from the menu — which "Welcome" would not be.
        window.title = "Set up Kestrel"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        finish()
    }
}
