import AppKit
import SwiftUI

/// Hosts `OnboardingView`. Kestrel is an accessory app with no Dock icon, so the window has to
/// activate the app itself or it opens behind whatever the user is doing.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    let model = OnboardingModel()
    /// Exposed for `OnboardingPreview`, which frames its screenshot on the window.
    private(set) var window: NSWindow?
    private var didFinish = false

    var onFinish: (() -> Void)?

    func show() {
        if window == nil { window = build() }
        model.go(to: .welcome)
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
        // Hidden rather than absent: the rail already says where the user is, and a title on the
        // glass would be a second, quieter heading saying the same thing.
        window.title = "Set up Kestrel"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable]
        window.applyGlassChrome()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        finish()
    }
}
