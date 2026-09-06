# Kestrel manual test checklist

`swift test` covers the pure logic. Everything below needs a real Mac, a real microphone and real
permissions. Run it after any change to input, audio, screen capture or injection.

## 0. Fresh install

- [ ] `./scripts/check-deps.sh` on a machine without `codex` warns but exits 0-for-required
- [ ] Delete `~/.kestrel`, launch: config, `KESTREL.md`, and both symlinks are recreated
- [ ] Menu bar icon appears, no Dock icon, no window
- [ ] `Quit Kestrel` leaves no process behind (`pgrep -x Kestrel`)

## 1. Permissions (test on a clean user account)

- [ ] First hotkey press prompts for Microphone; denying shows the panel error with a working link
- [ ] First question prompts for Screen Recording; after granting and relaunching, capture works
- [ ] First dictation prompts for Accessibility; denying shows the panel error with a working link

## 2. Ask

- [ ] Hold `⌃⌥Space`, ask "what app is this?", release → correct spoken answer
- [ ] The screenshot never contains the Kestrel panel
- [ ] Question about the display the mouse is on, with two displays connected
- [ ] Press the hotkey while the answer is being spoken → speech stops, recording restarts
- [ ] A tap shorter than 300 ms does nothing at all
- [ ] Panel auto-hides after 20 s; hovering it pauses the timer
- [ ] Turn Wi-Fi off → readable error within the timeout, no hang

## 3. Dictate

- [ ] TextEdit: 30 seconds of speech lands complete, punctuation cleaned
- [ ] Slack and VS Code: same, nothing lost
- [ ] Terminal / iTerm2 / Warp / Ghostty: newlines are collapsed, nothing executes
- [ ] Clipboard contents before dictation are restored afterwards (text and an image)
- [ ] `injectMode: "type"` also works
- [ ] Cleanup off → raw transcript is pasted instantly
- [ ] Kill the network mid-cleanup → raw transcript is pasted, nothing lost

## 4. Audio edge cases

- [ ] Start on AirPods, disconnect mid-sentence → what was captured is still transcribed
- [ ] Recording from a 44.1 kHz or 96 kHz interface transcribes correctly
- [ ] Silence only → "Didn't catch that", no hallucinated "Thank you."
- [ ] 10-minute dictation completes

## 5. Backends

- [ ] Switch to Codex in the menu bar, repeat §2 and §3
- [ ] Rename `claude` on PATH → error names the exact install command
- [ ] Rename `whisper-cli` → error names `brew install whisper-cpp`
- [ ] Exhausted plan quota → "usage limit reached" with the switch-backend hint

## 6. Settings and config

- [ ] Rebind the ask hotkey; the new combination works immediately, the old one does not
- [ ] A combination already owned by another app shows the conflict error
- [ ] Edit `~/.kestrel/config.json` by hand → applied without relaunching
- [ ] Corrupt the JSON → Kestrel keeps the last good config and still runs
- [ ] Voice picker + Preview speaks in the chosen voice
- [ ] Mute system output → answer appears on screen, nothing is spoken
- [ ] Launch at login survives a reboot

## 7. Latency budget (spec §12)

- [ ] capture stop → transcript ≤ 800 ms with `base.en`
- [ ] transcript → CLI exit ≤ 4 s typical
- [ ] speech starts ≤ 200 ms after the answer arrives
