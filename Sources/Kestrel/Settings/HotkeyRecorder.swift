import AppKit
import SwiftUI

/// Click, then press a combination. Pressing modifiers and a key records that key; holding two or
/// more modifiers and letting go without pressing anything records a bare chord like ⌃⌘.
struct HotkeyRecorder: View {
    let title: String
    @Binding var binding: HotkeyBinding
    /// Bare chords are watched through an event tap, so they cost an Accessibility grant. Ask is
    /// allowed to use one; dictate is not, or every ⌃⌘ shortcut would race it.
    var allowsBareChord: Bool = true

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var heldModifiers: [String] = []

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? hint : binding.display) {
                isRecording ? stop() : start()
            }
            .frame(minWidth: 130)
            .buttonStyle(.bordered)
            .tint(isRecording ? KestrelPalette.accent : nil)
        }
        .onDisappear(perform: stop)
    }

    private var hint: String {
        if heldModifiers.count >= 2 && allowsBareChord { return "Release for \(preview)" }
        return "Press keys…"
    }

    private var preview: String {
        HotkeyBinding(keyCode: nil, modifiers: heldModifiers).display
    }

    private func start() {
        isRecording = true
        heldModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            event.type == .keyDown ? handleKey(event) : handleFlags(event)
            return nil
        }
    }

    private func handleKey(_ event: NSEvent) {
        let modifiers = HotkeyBinding.modifierNames(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        // Esc cancels; a bare key with no modifiers would swallow normal typing system-wide.
        if event.keyCode == 53 && modifiers.isEmpty { return stop() }
        guard !modifiers.isEmpty else { return NSSound.beep() }
        binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        stop()
    }

    private func handleFlags(_ event: NSEvent) {
        let modifiers = HotkeyBinding.modifierNames(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if !modifiers.isEmpty {
            heldModifiers = modifiers
            return
        }
        // Everything let go. Two or more modifiers held and released cleanly is a bare chord.
        defer { heldModifiers = [] }
        guard allowsBareChord, heldModifiers.count >= 2 else { return }
        binding = HotkeyBinding(keyCode: nil, modifiers: heldModifiers)
        stop()
    }

    private func stop() {
        isRecording = false
        heldModifiers = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
