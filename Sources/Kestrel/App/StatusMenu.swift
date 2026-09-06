import AppKit

/// Menu bar item and its menu (spec §8.12). The icon is a monochrome template so it inverts with
/// the menu bar automatically.
final class StatusMenu: NSObject, NSMenuDelegate {
    var onOpenSettings: (() -> Void)?
    var onCheckDependencies: (() -> Void)?
    var onOpenOnboarding: (() -> Void)?

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusMenu.templateIcon()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Kestrel — hover, ask, do"
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuild() }

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
            menu.addItem(item)
        }
        menu.addItem(.separator())

        addToggle("Speak answers", isOn: config.speakAnswers, action: #selector(toggleSpeak))
        addToggle("Clean up dictation", isOn: config.cleanupDictation, action: #selector(toggleCleanup))
        addToggle("Draw walkthroughs", isOn: config.walkthroughs, action: #selector(toggleWalkthroughs))
        menu.addItem(.separator())

        addItem("Open memory file", #selector(openMemory))
        addItem("Setup & permissions…", #selector(openOnboarding))
        addItem("Check dependencies…", #selector(checkDependencies))
        addItem("Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        addItem("Quit Kestrel", #selector(quit), key: "q")
    }

    private func addItem(_ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func addToggle(_ title: String, isOn: Bool, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        menu.addItem(item)
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

    @objc private func toggleWalkthroughs() {
        ConfigStore.shared.update { $0.walkthroughs.toggle() }
    }

    @objc private func openMemory() { MemoryStore.openInEditor() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func checkDependencies() { onCheckDependencies?() }
    @objc private func openOnboarding() { onOpenOnboarding?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
