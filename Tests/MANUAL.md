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

## 5b. Marks

- [ ] "How do I upload a file here?" answers in a sentence or two and rings the control it names
- [ ] Two marks are drawn one after the other — the pencil rings the first, travels, rings the second
- [ ] Nothing waits for a click: the marks finish on their own and the answer stays put
- [ ] Clicking the marked control does nothing to Kestrel; no second screenshot is taken
- [ ] Esc clears the marks immediately
- [ ] Asking again while marks are showing clears the old ones before listening
- [ ] The marks never appear in a screenshot taken by the next question
- [ ] On the second display, the marks land on the right controls
- [ ] "What app is this?" answers with no marks, or one, and never a route

## 5b-ii. Drafts

- [ ] "Write a reply to this email" shows the draft in a card with a **Copy** button
- [ ] The draft is *not* read aloud — only the one-line summary above it is
- [ ] **Copy** puts subject and body on the clipboard; the button says "Copied" and reverts
- [ ] A long draft scrolls inside its card rather than growing the island off the screen
- [ ] Asking an ordinary question afterwards clears the draft

## 5c. Spatial context (M5)

- [ ] Holding the ask key and circling a button shows a cyan trail
- [ ] Asking "what does this do?" about the circled control answers about that control
- [ ] A tiny twitch of the mouse is ignored, and the question behaves as normal
- [ ] The trail never appears in the screenshot that is sent

## 5d. Voice and timing

- [ ] Kestrel says something within a second of releasing the key
- [ ] The answer starts being spoken before it has finished appearing on screen
- [ ] The voice is one of the premium or enhanced ones, not a compact voice
- [ ] Muting the Mac skips speech and leaves the answer on screen
- [ ] A question about the front window is answered without any mention of resolution or zooming

## 5e. Follow-ups, skills, sounds

- [ ] Ask a question, then ask "and the one below it?" — the second answer uses the first
- [ ] Wait two minutes and ask again: the thread has gone cold
- [ ] Switch app between questions: the thread has gone cold
- [ ] Write `~/.kestrel/skills/default.md` and confirm the answer reflects it, with no relaunch
- [ ] A cue plays on hotkey down, on release, on answer and on error; muting the Mac silences them

## 5f. Acting (T5–T9)

- [ ] "Open Slack" launches it; "how do I open Slack?" explains instead
- [ ] An action in an app with no policy entry asks first, and Stop leaves nothing changed
- [ ] "Send it" in Mail is confirmed even after allowing Mail
- [ ] An action in Terminal is refused outright
- [ ] The overlay names each step and counts them; Esc stops mid-run
- [ ] The real cursor does not move and focus is not stolen while a run is in progress
- [ ] `~/.kestrel/logs/actions.jsonl` has one line per action, with the decision recorded
- [ ] A task leaves a folder in `~/.kestrel/projects/`

### 5g. Keyboard actions

- [ ] "save this" in TextEdit presses ⌘S rather than walking the File menu
- [ ] "add a line saying hello" appends rather than replacing what is in the document
- [ ] "press Return" in a chat app is confirmed first, even if that app is set to `allow`
- [ ] Typing lands in the target app while you keep working in another — the frontmost app does not
      change, and neither does the cursor
- [ ] After answering a confirmation, you are put back in the app you were in
- [ ] "right click that" opens the control's context menu
- [ ] "page down" moves a screenful, not a nudge
- [ ] `open -n Kestrel.app --env KESTREL_PROBE_ACTIONS=1 --stdout /tmp/probe.txt` reports the marker
      in the file and an unchanged frontmost app

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
