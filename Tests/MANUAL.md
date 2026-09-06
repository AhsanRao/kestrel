# Kestrel manual test checklist

`swift test` covers the pure logic. Everything below needs a real Mac, a real microphone and real
permissions. Run it after any change to input, audio, screen capture or injection.

## 0. Fresh install

- [ ] `./scripts/check-deps.sh` on a machine without `codex` warns but exits 0-for-required
- [ ] Delete `~/.kestrel`, launch: config, `KESTREL.md`, and both symlinks are recreated
- [ ] Menu bar icon appears, no Dock icon, no window
- [ ] `Quit Kestrel` leaves no process behind (`pgrep -x Kestrel`)

## 0b. Setup window (test on a clean user account)

- [ ] Opens by itself on first launch, listing every permission and tool
- [ ] "Allow" on Microphone shows the system prompt; the row ticks without pressing anything else
- [ ] "Allow" on Screen Recording offers a relaunch, and the row is ticked after it
- [ ] Granting Accessibility in System Settings ticks that row within a couple of seconds
- [ ] "Copy command" puts the right shell command on the clipboard
- [ ] "Skip for now" closes it; it does not reappear on the next launch once everything required
      is in place
- [ ] Removing whisper-cli brings it back on the next launch
- [ ] Menu bar ▸ Setup & permissions… reopens it

## 1. Permissions (test on a clean user account)

- [ ] First hotkey press prompts for Microphone; denying shows the panel error with a working link
- [ ] First question prompts for Screen Recording; after granting and relaunching, capture works
- [ ] First dictation prompts for Accessibility; denying shows the panel error with a working link

## 2. Ask

- [ ] Hold `⌃⌘A`, ask "what app is this?", release → correct spoken answer
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

## 5b. Walkthroughs (M4)

- [ ] "How do I export as PDF in this app?" draws ≥2 steps on the right controls
- [ ] Clicking the highlighted control advances to the next step; the click still reaches the app
- [ ] Clicking somewhere else does not advance
- [ ] Esc clears the overlay immediately
- [ ] The last click ends the walkthrough and removes the overlay
- [ ] Pressing the ask hotkey mid-walkthrough clears the overlay and starts listening
- [ ] The overlay never appears in a screenshot taken by the next question
- [ ] On the second display, the rings land on the right controls
- [ ] Revoke Accessibility → the steps are spoken and nothing is drawn
- [ ] A question the model cannot answer from this screen returns one step and says there are more
- [ ] "What app is this?" still answers normally, with no overlay

## 6. Settings and config

- [ ] `⌃⌘A` starts listening on a machine where Accessibility has never been granted
- [ ] `⌃⌘K` starts dictation
- [ ] `⌃⌘Space`, `⌃⌘D`, `⌃⌘F`, `⌃⌘Q` still do their macOS jobs
- [ ] Recording a bare `⌥⌘` chord in Settings works, prompts for Accessibility, and cancels cleanly
      when a key is pressed while held
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
