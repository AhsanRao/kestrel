import AppKit
import SwiftUI

/// Click, then press a combination. Captures the next key-down while the settings window is key,
/// which is enough here — the global Carbon hotkeys are unregistered and re-registered on save.
struct HotkeyRecorder: View {
    let title: String
    @Binding var binding: HotkeyBinding

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press keys…" : binding.display) {
                isRecording ? stop() : start()
            }
            .frame(minWidth: 110)
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let modifiers = HotkeyBinding.modifierNames(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            // Esc cancels; a bare key with no modifiers would swallow normal typing system-wide.
            if event.keyCode == 53 && modifiers.isEmpty {
                stop()
                return nil
            }
            guard !modifiers.isEmpty else { NSSound.beep(); return nil }
            binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stop()
            return nil
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
