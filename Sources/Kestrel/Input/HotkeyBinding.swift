import AppKit
import Carbon.HIToolbox
import Foundation

/// A global hotkey as stored in config.json: a virtual key code plus modifier names.
/// Names rather than a bitmask so the file stays hand-editable.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: [String]

    static let modifierOrder = ["control", "option", "shift", "command"]

    /// Carbon modifier mask for `RegisterEventHotKey`.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        for name in modifiers {
            switch name.lowercased() {
            case "control", "ctrl", "^": mask |= UInt32(controlKey)
            case "option", "alt", "⌥": mask |= UInt32(optionKey)
            case "shift", "⇧": mask |= UInt32(shiftKey)
            case "command", "cmd", "⌘": mask |= UInt32(cmdKey)
            default: break
            }
        }
        return mask
    }

    /// "⌃⌘Space" — used in the panel hint, the menu and the settings window.
    var display: String {
        var out = ""
        let lowered = Set(modifiers.map { $0.lowercased() })
        if lowered.contains("control") || lowered.contains("ctrl") { out += "⌃" }
        if lowered.contains("option") || lowered.contains("alt") { out += "⌥" }
        if lowered.contains("shift") { out += "⇧" }
        if lowered.contains("command") || lowered.contains("cmd") { out += "⌘" }
        return out + HotkeyBinding.keyName(keyCode)
    }

    var isValid: Bool { carbonModifiers != 0 }

    static func modifierNames(from flags: NSEvent.ModifierFlags) -> [String] {
        var names: [String] = []
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.option) { names.append("option") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.command) { names.append("command") }
        return names
    }

    /// Human-readable name for a virtual key code. Letters and digits come from the current
    /// keyboard layout; everything else is a fixed table because layouts do not name them.
    static func keyName(_ keyCode: UInt32) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let layoutName = layoutKeyName(keyCode) { return layoutName.uppercased() }
        return "Key\(keyCode)"
    }

    private static let specialKeys: [UInt32: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func layoutKeyName(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
