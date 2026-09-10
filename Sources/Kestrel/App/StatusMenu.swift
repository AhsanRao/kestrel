import AppKit

/// Menu bar item and its menu (spec §8.12). The icon is a monochrome template so it inverts with
/// the menu bar automatically.
final class StatusMenu: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onCheckDependencies: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?

    private var statusItem: NSStatusItem?
    private var animator: StatusItemAnimator?
    private let menu = NSMenu()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusMenu.templateIcon()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Kestrel — hover, ask, do"
        menu.delegate = self
        item.menu = menu
        statusItem = item
        animator = StatusItemAnimator(button: item.button)
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

    /// For `MenuPreview` only: drops the menu open where it normally appears. Tracking blocks the
    /// main thread until it is dismissed, which is why the preview photographs it from another one.
    func popUpForPreview() {
        guard let button = statusItem?.button else { return }
        rebuild()
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: button.bounds.minY - 6), in: button)
    }

    /// Called as the session moves, so the menu bar shows what Kestrel is doing even when the
    /// panel is hidden behind a full-screen window.
    func show(state: SessionState) {
        animator?.apply(state)
    }

    /// `assets/kestrel-menubar-template.svg`, rendered by `scripts/make-icon.sh` into the bundle.
    /// Falls back to an SF Symbol when running from `swift run` with no bundle around.
    private static func templateIcon() -> NSImage? {
        if let url = BundleResources.url(for: "MenuBarIcon.png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "bird.fill", accessibilityDescription: "Kestrel")
    }

    private func rebuild() {
        let config = ConfigStore.shared.current
        menu.removeAllItems()

        let header = NSMenuItem(title: "Ask \(config.hotkeys.ask.display)   ·   Dictate \(config.hotkeys.dictate.display)",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for kind in BackendKind.allCases {
            let item = NSMenuItem(title: kind.displayName, action: #selector(selectBackend(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = config.backend == kind ? .on : .off
            // Both carry one: an item without an icon indents its title differently, and a menu
            // where half the rows start in one column and half in another reads as a mistake.
            item.image = StatusMenu.icon(kind == .claude
                                         ? "sparkle" : "chevron.left.forwardslash.chevron.right")
            menu.addItem(item)
        }
        menu.addItem(.separator())

        addToggle("Speak answers", isOn: config.speakAnswers, action: #selector(toggleSpeak),
                  symbol: "speaker.wave.2")
        addToggle("Clean up dictation", isOn: config.cleanupDictation, action: #selector(toggleCleanup),
                  symbol: "wand.and.sparkles")
        menu.addItem(.separator())

        addItem("Open what I remember", #selector(openMemory), symbol: "brain")
        // "Skills" was the folder's name, not a description of it. What is in there is a note per
        // app that Kestrel reads when that app is in front.
        addItem("Open per-app notes", #selector(openSkills), symbol: "note.text")
        addItem("Setup & permissions…", #selector(openOnboarding), symbol: "checklist")
        addItem("Check what's installed…", #selector(checkDependencies), symbol: "stethoscope")
        addItem("Settings…", #selector(openSettings), key: ",", symbol: "gearshape")
        menu.addItem(.separator())
        addItem("Quit Kestrel", #selector(quit), key: "q", symbol: "power")
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "", symbol: String? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = StatusMenu.icon(symbol)
        menu.addItem(item)
    }

    private func addToggle(_ title: String, isOn: Bool, action: Selector, symbol: String? = nil) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        item.image = StatusMenu.icon(symbol)
        menu.addItem(item)
    }

    /// A menu item's icon, at the size AppKit expects. Template so it inverts with the menu and
    /// stays legible when the row is highlighted — a tinted glyph on a blue row does not.
    private static func icon(_ symbol: String?) -> NSImage? {
        guard let symbol,
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else { return nil }
        let configured = image.withSymbolConfiguration(
            .init(pointSize: 13, weight: .regular)) ?? image
        configured.isTemplate = true
        return configured
    }

    // MARK: - Actions

    @objc private func selectBackend(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = BackendKind(rawValue: raw) else { return }
        ConfigStore.shared.update { $0.backend = kind }
    }

    @objc private func toggleSpeak() {
        ConfigStore.shared.update { $0.speakAnswers.toggle() }
    }

    @objc private func toggleCleanup() {
        ConfigStore.shared.update { $0.cleanupDictation.toggle() }
    }

    @objc private func openMemory() { MemoryStore.openInEditor() }
    @objc private func openSkills() { NSWorkspace.shared.open(Paths.skills) }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func checkDependencies() { onCheckDependencies?() }
    @objc private func openOnboarding() { onOpenOnboarding?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
