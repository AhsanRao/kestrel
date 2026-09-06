import CoreGraphics
import Foundation

/// A keystroke the model asked for: `"return"`, `"cmd+s"`, `"cmd+shift+p"`.
///
/// Parsed rather than passed through, for two reasons. A chord has to become a virtual key code
/// and a flag set before it can be delivered to a pid at all, and the parse is the only place that
/// can recognise a keystroke as irreversible — ⌘Q and Return in a chat box do more than their
/// `describe` line usually admits.
struct KeyChord: Equatable {
    var keyCode: CGKeyCode
    var flags: CGEventFlags
    /// The canonical spelling, for the log and the confirmation dialog.
    var display: String

    static let separators = CharacterSet(charactersIn: "+- ")

    /// US-layout virtual key codes. Only keys a plan has any business pressing.
    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29,
        "equal": 24, "minus": 27, "leftbracket": 33, "rightbracket": 30, "quote": 39,
        "semicolon": 41, "backslash": 42, "comma": 43, "slash": 44, "period": 47, "grave": 50,
        "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "keypadenter": 76,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// What people and models actually write.
    static let aliases: [String: String] = [
        "enter": "return", "ret": "return", "⏎": "return", "esc": "escape", "⎋": "escape",
        "backspace": "delete", "back": "delete", "bksp": "delete", "⌫": "delete",
        "del": "forwarddelete", "fwddelete": "forwarddelete", "⌦": "forwarddelete",
        "spacebar": "space", "pgup": "pageup", "pgdn": "pagedown", "pagedn": "pagedown",
        "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down",
        "plus": "equal", "dash": "minus", "hyphen": "minus", "dot": "period", "point": "period",
        "[": "leftbracket", "]": "rightbracket", ",": "comma", ".": "period", "/": "slash",
        ";": "semicolon", "'": "quote", "\\": "backslash", "`": "grave", "=": "equal", "-": "minus",
    ]

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand, "meta": .maskCommand,
        "shift": .maskShift, "⇧": .maskShift,
        "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
    ]

    /// Keys that commit or destroy something. Return sends the message; ⌘Q closes the app with the
    /// draft in it. Neither is undoable, so both are confirmed however permissive the policy is.
    static let irreversibleKeys: Set<String> = ["return", "keypadenter", "delete", "forwarddelete"]
    static let irreversibleCommandKeys: Set<String> = ["q", "w", "delete", "forwarddelete", "return"]

    init?(_ raw: String) {
        let parts = raw.lowercased()
            .components(separatedBy: KeyChord.separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }

        var flags = CGEventFlags()
        var names: [String] = []
        for part in parts.dropLast() {
            guard let flag = KeyChord.modifiers[part] else { return nil }
            flags.insert(flag)
            names.append(part)
        }

        let key = KeyChord.aliases[last] ?? last
        guard let code = KeyChord.keyCodes[key] else { return nil }
        keyCode = code
        self.flags = flags
        display = (names + [key]).joined(separator: "+")
    }

    var keyName: String { display.components(separatedBy: "+").last ?? display }

    /// True when pressing this cannot be quietly taken back.
    var isIrreversible: Bool {
        if KeyChord.irreversibleKeys.contains(keyName) { return true }
        return flags.contains(.maskCommand) && KeyChord.irreversibleCommandKeys.contains(keyName)
    }

    /// Convenience for the policy, which holds a raw string rather than a parsed chord.
    static func isIrreversible(_ raw: String?) -> Bool {
        guard let raw, let chord = KeyChord(raw) else { return false }
        return chord.isIrreversible
    }
}
