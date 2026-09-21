import AppKit
import Carbon.HIToolbox
import os

/// Puts dictated text into whatever app is frontmost: pasteboard + synthetic ⌘V, with the previous
/// pasteboard restored afterwards, and per-character typing as a fallback (spec §8.10).
enum TextInjector {
    private static let log = Logger(subsystem: "dev.0xash.kestrel", category: "inject")

    /// Apps where a stray newline would submit a command line.
    static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "org.alacritty",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
    ]

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once. Returns the current trust state.
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    /// Newlines become spaces in terminals so dictation can never execute a command.
    static func sanitize(_ text: String, frontmostBundleID: String?) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let bundleID = frontmostBundleID, terminalBundleIDs.contains(bundleID) else { return trimmed }
        return trimmed
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Main thread only. Throws when Accessibility has not been granted.
    ///
    /// - Parameter spaced: put a space in front of it. Live dictation arrives a phrase at a time
    ///   and each phrase is typed as it lands, so something has to keep the words apart — and it
    ///   cannot be a leading space in the text itself, which `sanitize` trims off.
    static func inject(_ text: String, mode: Config.InjectMode, spaced: Bool = false) throws {
        let cleaned = sanitize(text, frontmostBundleID: frontmostBundleID())
        guard !cleaned.isEmpty else { return }
        let payload = spaced ? " " + cleaned : cleaned
        guard hasAccessibilityPermission else { throw KestrelError.accessibilityDenied }

        if mode == .type {
            type(payload)
            return
        }
        paste(payload)
    }

    // MARK: - Paste

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data] in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { copy[type] = item.data(forType: type) }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCommandV()

        // The target app reads the pasteboard asynchronously; restoring too early loses the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let saved, !saved.isEmpty else { return }
            pasteboard.clearContents()
            let items = saved.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entry { item.setData(data, forType: type) }
                return item
            }
            pasteboard.writeObjects(items)
        }
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Typing fallback

    /// Posts the text as unicode key events. Slower, but survives apps that reject synthetic ⌘V.
    ///
    /// One character per key press. Twenty at a time was tried and Chrome's address bar dropped
    /// the lot — measured: "Typed 16 characters", field unchanged. The flags are cleared on every
    /// event because the source carries whatever is physically held, and the ask chord is held
    /// for as long as the user is talking: without this a typed "g" arrived as ⌘⌥G.
    private static func type(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for character in text {
            var utf16 = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.flags = []
            up.flags = []
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(3000)
        }
        log.debug("typed \(text.count) characters")
    }
}
