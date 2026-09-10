# Kestrel

**Ask. Look. Point.** — a voice-first, screen-aware assistant for macOS that runs on *your* Claude
and ChatGPT subscriptions.

Hold a key, ask about what is on screen, hear the answer. Tap another key and talk, and the words appear in whatever app you are in as you say them.
Speech-to-text is local. There is no Kestrel backend, no account, and no telemetry: the only things
that leave your Mac are the transcribed question and one screenshot, sent by the vendors' own CLIs,
only while you are holding the key.

| | |
|---|---|
| **Ask** | Hold `⌃⌥`, speak, release. Kestrel screenshots the display your mouse is on, transcribes it on this Mac, asks Claude or Codex, then shows and speaks the answer. |
| **Dictate** | Tap `⌃⌘K` and talk. The words appear in the frontmost app as you say them, a phrase at a time, and the take ends itself once you have been quiet for a couple of seconds — or on another tap. Newlines are collapsed in terminals so dictation can never run a command. |
| **Show** | Kestrel draws on the real screen while it talks — a pencil rings the thing the answer is about, one mark after another. Ask *"how do I upload a file?"* and the button gets circled while the sentence is spoken. Esc clears it. |
| **Write** | Ask for a reply, an email or a paragraph and you get it as text with a **Copy** button, not read aloud. |
| **Point** | Circle something with the mouse while holding the ask key, then ask about it. |
| **Open** | Say "open Spotify" and it opens. That is the only thing Kestrel does *to* your Mac. |
| **Follow up** | Ask again within 90 seconds and it continues the same thread. |
| **Switch** | Claude ↔ Codex from the menu bar. |
| **Remember** | `~/.kestrel/KESTREL.md` is loaded by both CLIs on every request. |

## Requirements

- macOS 14 or later, Apple Silicon
- A **Claude Pro/Max** subscription with the Agent SDK credit claimed in account settings, and/or a
  **ChatGPT Plus/Pro** subscription
- Homebrew

> **Single user.** Kestrel drives your personal CLI logins. Sharing it with another person is
> against both vendors' terms — if you need that, set an API key in Settings ▸ Advanced instead.

## Setup

```bash
# 1. The CLIs Kestrel drives (at least one)
#    Claude Code: https://claude.ai/download   → then: claude auth
npm i -g @openai/codex && codex login          # optional second backend

# 2. Kestrel
git clone https://github.com/AhsanRao/kestrel.git && cd kestrel
./scripts/make-signing-cert.sh                 # once; see below
./scripts/check-deps.sh                        # everything should be ✓
make run
```

The menu bar gains a small falcon. There is no Dock icon and no window until you press a hotkey.

### First run

Kestrel opens a setup window on first launch listing everything it needs, what each thing is for,
and a button that asks for it. It re-checks itself while open, so a switch flipped in System
Settings ticks the row without coming back to press anything. Reopen it any time from the menu bar:
**Setup & permissions…**

| | Needed for | Note |
|---|---|---|
| Microphone | hearing the question | required |
| Screen Recording | seeing the screen you ask about | required, **applies after a relaunch** — the window offers one |
| Accessibility | the `⌃⌥` hotkey, reading the screen's contents, circling a region, pasting dictation | required for the default hotkey |
| Speech to text | hearing what you said | built into macOS 26; below that, `brew install whisper-cpp` and `./scripts/download-whisper-model.sh` |
| Claude Code CLI | answering | required |
| Codex CLI | second backend | optional |

The window lets you skip and finish later; Kestrel's error panel also links straight to the right
Privacy pane whenever something turns out to be missing mid-use.

> **Run `./scripts/make-signing-cert.sh` before granting anything.** An ad-hoc signature is a hash
> of the binary, so without a stable certificate *every rebuild is a different app* as far as macOS
> is concerned — it silently stops honouring Accessibility and Screen Recording while leaving the
> checkbox ticked, which is a miserable thing to debug. The script creates a self-signed code-signing
> certificate once; `build.sh` picks it up automatically and the grants then survive every rebuild.

## Using it

- **Ask:** hold `⌃⌥`, say *"what is this window for?"* or *"how could this page look better?"*,
  release. The island opens out of the notch and the answer is spoken — and a pencil draws on the
  thing the answer is about while it says it. Not just buttons: the section, the card, the heading,
  whatever it is talking about. It points instead of saying "in the top right", and if it names
  something without marking it, Kestrel works out what it meant and marks it anyway. Your real
  pointer is never touched. Press the hotkey again to interrupt, Esc to take the marks off.
- **Dictate:** tap `⌃⌘K` and talk. Text lands in the focused app as you speak, and stops when you do.
- **Be shown:** ask *"how do I upload a file here?"* and you get a sentence plus a mark on the
  thing it names. Nothing waits for you to click and nothing takes a second screenshot — do the
  thing, and ask again if you want the next part. That question gets a fresh look at the new screen.
- **Write something:** *"draft a reply to this"* gives you one spoken line and the draft in a card
  with a **Copy** button. Drafts are never read aloud.
- Both hotkeys are rebindable in Settings ▸ Shortcuts.

**Why these keys.** Asking is held down for as long as you are talking, so it is a bare chord —
`⌃⌥` is one shape the hand already makes, macOS claims nothing on it, and with no letter it cannot
collide with an app's shortcut. It fires after a short dwell so `⌃⌥` on its way to some other
shortcut is not mistaken for a question, and any key pressed while it is held cancels it. Because
Carbon cannot register a bare chord it is watched through an event tap, which is why the ask hotkey
needs Accessibility.

Dictation is a tap rather than a hold, so it stays an ordinary keyed hotkey needing no permission of
its own. `⌃⌘` is the quietest modifier pair on macOS — the system claims only `⌃⌘Space`, `⌃⌘D`,
`⌃⌘F` and `⌃⌘Q` — and `K` is free in it, so **nothing has to be turned off for Kestrel to work**.

## Configuration

Everything lives in `~/.kestrel/config.json` and is editable by hand — Kestrel reloads it as soon as
you save. The Settings window writes the same file.

| Key | Default | Notes |
|---|---|---|
| `backend` | `"claude"` | or `"codex"` |
| `claudeModel` / `codexModel` | `null` | `null` uses the CLI's own default |
| `autoRoute` | `false` | send short, screenshot-free questions to Codex |
| `transcriptionEngine` | `"apple"` | `"whisper"` to use whisper.cpp instead; `"apple"` falls back to it below macOS 26 |
| `whisperBinary` | `/opt/homebrew/bin/whisper-cli` | only read by the whisper engine |
| `whisperModel` | `~/.kestrel/models/ggml-base.en.bin` | only read by the whisper engine |
| `speakAnswers` | `true` | |
| `voiceEngine` | `"kokoro"` | `"system"` uses the macOS voices instead |
| `kokoroVoice` | `"af_heart"` | `af_heart`, `af_sarah`, `am_michael`, `am_puck` |
| `voiceIdentifier` / `voiceRate` | `null` / `0.52` | `system` engine only; your Personal Voice is preferred when you have one, then premium voices |
| `cleanupDictation` | `true` | punctuation, capitals and the ums, fixed locally |
| `dictationSilenceSeconds` | `2.5` | how long a pause ends a live dictation; `0` means only the hotkey does |
| `injectMode` | `"paste"` | `"type"` for apps that reject synthetic ⌘V |
| `hotkeys.ask` / `hotkeys.dictate` | `⌃⌥` / `⌃⌘K` | `{keyCode, modifiers}`; omit `keyCode` for a bare chord |
| `answerAnnotations` | `true` | draw on what a spoken answer is pointing at |
| `followUpSeconds` | `90` | how long a conversation stays warm; 0 disables |
| `sounds` | `true` | short cues for each state change |
| `spatialContext` | `true` | circle a region while holding the ask key |
| `captureMode` | `"window"` | `"display"` to send the whole screen instead |
| `acknowledgeWhileThinking` | `true` | say "one sec" while the model reads the screen |
| `allowMCPServers` | `false` | leave off: MCP discovery added ~10 s to every question |
| `voicePitch` | `0.98` | |
| `transcriptionHint` | `null` | names, Roman Urdu words and jargon to expect |
| `panelAutoHideSeconds` | `20` | hovering the panel pauses the timer |
| `screenshotMaxEdge` | `2048` | smaller is faster and cheaper |
| `apiKeys.anthropic` / `apiKeys.openai` | `null` | pay-as-you-go override |

**Speech to text.** On macOS 26 Kestrel uses Apple's own on-device engine — the one system
dictation runs on. There is nothing to install and no model to download, it is roughly six times
faster than whisper on the same clip, and it is the only one of the two that can transcribe a live
stream, which is what lets dictation type as you talk. Below macOS 26, and under whisper, dictation
records the take and types it when you tap the hotkey again:

```bash
brew install whisper-cpp
./scripts/download-whisper-model.sh            # ~148 MB into ~/.kestrel/models
```

**Language.** English only, both engines. Roman Urdu is transcribed as English, which is how it is
written; put the words you use often into `transcriptionHint` and both engines will expect them.

## Development

```bash
make build     # swift build -c release + assemble Kestrel.app
make run       # build, then launch
make test      # swift test
make icon      # regenerate icons from assets/kestrel-logo.svg
make deps      # scripts/check-deps.sh
```

- [`docs/SPEC.md`](docs/SPEC.md) is the design of record: architecture, folder layout, module
  contracts. `CLAUDE.md` holds the working rules for anyone (or anything) writing code here.
- **Seeing the real panel.** Offscreen SwiftUI renders cannot show window chrome, materials or
  shadows, which is where panel bugs actually live. To photograph the real thing:

      KESTREL_PREVIEW_PANEL=1 KESTREL_PREVIEW_STATE=listening \
        KESTREL_PREVIEW_OUT=/tmp/panel.png Kestrel.app/Contents/MacOS/Kestrel

  States: `listening`, `thinking`, `answer`, `error`. Without the env vars nothing changes.
- **Seeing the drawing.** Same reason, same shape — strokes that animate onto a live screen cannot
  be judged from a static render:

      KESTREL_PREVIEW_OVERLAY=annotation \
        KESTREL_PREVIEW_OUT=/tmp/overlay.png Kestrel.app/Contents/MacOS/Kestrel

  `annotation` draws the marks that accompany an answer, `region` shades a block of content,
  `calibrate` puts a box in three known corners so the screen-to-overlay mapping can be checked by
  eye, and `live` reads the app in front and prints everything it found — which is how you tell a
  thin Accessibility tree from a bad guess.
  `KESTREL_PREVIEW_DELAY=0.5` catches the cursor mid-stroke; `KESTREL_PREVIEW_BACKDROP=light` puts
  a plain backdrop behind the panel, because a black island on a black desktop tells you nothing
  about its edges.
- `Tests/MANUAL.md` is the checklist for everything unit tests cannot reach.
- Icons are generated from the original logo by `scripts/icon-tool.swift`; nothing is redrawn.
- **CLI flags drift between releases.** Every invocation is confined to
  `Sources/Kestrel/Backends/ClaudeBackend.swift` and `CodexBackend.swift`, with the verified flags
  in a comment above it. `scripts/check-deps.sh` re-checks them against `--help` and warns on drift.

## What Kestrel does *not* do

It does not drive your apps. Pressing buttons, filling fields and planning multi-step tasks were
removed: every plan went stale the moment anything moved, every step needed a confirmation, and the
confirmations became something to click through rather than read. What made Kestrel worth having was
never that it could press Send — it was that it could look at the screen with you and point.

The one exception is **opening an app**: say "open Spotify" and it opens. One verb, nothing to undo,
no permission theatre. Anything after that — "and play something" — is not done, and Kestrel says so
rather than half-doing it.


## Teaching it your own vocabulary

Drop a markdown file in `~/.kestrel/skills/`. `default.md` is sent with every question;
`<bundle id>.md` only while that app is in front. Menu bar ▸ Open skills folder.

## What Kestrel never does

- Read, store, or forward OAuth tokens from `~/.claude`, `~/.codex`, or the Keychain
- Call `api.anthropic.com` or `api.openai.com` directly (unless *you* set an API key)
- Capture the screen or the microphone unless a hotkey is held
- Write anywhere outside `~/.kestrel`
- Phone home. There is nowhere to phone.

## Status

Working and in daily use by its author. See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for what has
changed and, more usefully, why.

## Licence

[MIT](LICENSE). Kestrel drives the Claude Code and Codex CLIs; it does not bundle them, and their
own licences and terms of service are yours to keep to — in particular, the single-user note above.
