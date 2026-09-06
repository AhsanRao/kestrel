import CoreGraphics
import Foundation

/// Keystrokes and typed text, delivered to one process.
///
/// Every event here is posted with `postToPid`, never to the global event stream. That is the whole
/// point: the keystroke reaches the app Kestrel is working in, while the user keeps typing in
/// theirs. A `.cghidEventTap` post would go wherever the focus happens to be a moment later, which
/// for a keystroke is not a risk worth taking.
enum KeyEvents {
    /// UTF-16 units per synthetic event. Long strings are typed in chunks; 20 is well inside the
    /// limit and keeps each event small enough for every app tested.
    static let chunkSize = 20

    static func press(_ chord: KeyChord, to pid: pid_t) throws {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: chord.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: chord.keyCode, keyDown: false)
        else { throw KestrelError.actionFailed("press \(chord.display)") }
        down.flags = chord.flags
        up.flags = chord.flags
        down.postToPid(pid)
        up.postToPid(pid)
    }

    /// Types text into whatever has focus in that process, leaving what is already there alone.
    /// This is the difference from `setValue`, which replaces a field wholesale.
    static func type(_ text: String, to pid: pid_t) throws {
        guard !text.isEmpty else { return }
        for chunk in chunks(of: text) {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            else { throw KestrelError.actionFailed("type that text") }
            var units = Array(chunk.utf16)
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }

    /// Split on UTF-16 length, so a surrogate pair is never cut in half.
    static func chunks(of text: String, size: Int = chunkSize) -> [String] {
        var out: [String] = []
        var current = ""
        var count = 0
        for character in text {
            let width = String(character).utf16.count
            if count + width > size, !current.isEmpty {
                out.append(current)
                current = ""
                count = 0
            }
            current.append(character)
            count += width
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}
