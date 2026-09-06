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
    static func inject(_ text: String, mode: Config.InjectMode) throws {
        let payload = sanitize(text, frontmostBundleID: frontmostBundleID())
        guard !payload.isEmpty else { return }
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
    private static func type(_ text: String) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for chunk in text.chunked(20) {
            var utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(4000)
        }
        log.debug("typed \(text.count) characters")
    }
}

private extension String {
    /// CGEvent's unicode payload is capped in practice; send it in small pieces.
    func chunked(_ size: Int) -> [String] {
        var result: [String] = []
        var current = ""
        for character in self {
            current.append(character)
            if current.count >= size { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
