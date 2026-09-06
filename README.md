# Kestrel

**Hover. Ask. Do.** — a voice-first, screen-aware assistant for macOS that runs on *your* Claude and
ChatGPT subscriptions.

Hold a key, ask about what is on screen, hear the answer. Tap another key to dictate into any app.
Speech-to-text is local. There is no Kestrel backend, no account, and no telemetry: the only things
that leave your Mac are the transcribed question and one screenshot, sent by the vendors' own CLIs,
only while you are holding the key.

| | |
|---|---|
| **Ask** | Hold `⌃⌘Space`, speak, release. Kestrel screenshots the display your mouse is on, transcribes locally with whisper.cpp, asks Claude or Codex, then shows and speaks the answer. |
| **Dictate** | Tap `⌃⌘D`, speak, tap again. The text is cleaned up by the model and pasted into whatever app is frontmost. Newlines are collapsed in terminals so dictation can never run a command. |
| **Show** | Ask *"how do I export as PDF?"* and Kestrel draws numbered steps over the real UI, advancing each time you click the highlighted control. Esc stops it. |
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

# 2. Local speech to text
brew install whisper-cpp

# 3. Kestrel
git clone <this repo> && cd kestrel
./scripts/download-whisper-model.sh            # ~148 MB into ~/.kestrel/models
./scripts/check-deps.sh                        # everything should be ✓
make run
```

The menu bar gains a small falcon. There is no Dock icon and no window until you press a hotkey.

### Permissions

macOS asks once for each, at the moment it is first needed:

| Permission | Asked when | If you miss the prompt |
|---|---|---|
| Microphone | first hotkey press | System Settings ▸ Privacy & Security ▸ Microphone |
| Screen Recording | first question | …▸ Screen Recording, **then relaunch Kestrel** |
| Accessibility | first dictation | …▸ Accessibility |

Kestrel's error panel links straight to the right pane when one is missing.

## Using it

- **Ask:** hold `⌃⌘Space`, say *"what is this window for?"*, release. The panel shows the answer and
  speaks it. Press the hotkey again to interrupt.
- **Dictate:** tap `⌃⌘D`, speak, tap again. Text lands in the focused app.
- **Be shown:** ask a *"how do I…"*, *"where is…"* or *"show me how…"* question and the answer is
  drawn on screen: click each highlighted control to advance, Esc to stop. Needs Accessibility;
  without it Kestrel reads the steps out instead.

> Where the ring lands is only as good as the model's eye for a screenshot, and that is the weak
> part of this feature — on a toolbar of near-identical buttons it can be a button or two out.
> Each step also names its control, clicks near the ring count, and after two misses the overlay
> lets you advance with a click anywhere.
- Both hotkeys are rebindable in Settings.

> macOS ships its own shortcuts on these combinations: `⌃⌘Space` opens the Emoji & Symbols viewer
> and `⌃⌘D` looks a word up in the dictionary. If one of them wins, either turn it off in
> System Settings ▸ Keyboard ▸ Keyboard Shortcuts, or rebind Kestrel's in Settings ▸ General.

## Configuration

Everything lives in `~/.kestrel/config.json` and is editable by hand — Kestrel reloads it as soon as
you save. The Settings window writes the same file.

| Key | Default | Notes |
|---|---|---|
| `backend` | `"claude"` | or `"codex"` |
| `claudeModel` / `codexModel` | `null` | `null` uses the CLI's own default |
| `autoRoute` | `false` | send short, screenshot-free questions to Codex |
| `whisperBinary` | `/opt/homebrew/bin/whisper-cli` | |
| `whisperModel` | `~/.kestrel/models/ggml-base.en.bin` | |
| `language` | `"auto"` | forced to `en` for a `.en` model |
| `speakAnswers` | `true` | |
| `voiceIdentifier` / `voiceRate` | `null` / `0.52` | premium voices are preferred when installed |
| `cleanupDictation` | `true` | model fixes punctuation; falls back to the raw transcript |
| `injectMode` | `"paste"` | `"type"` for apps that reject synthetic ⌘V |
| `hotkeys.ask` / `hotkeys.dictate` | `⌃⌘Space` / `⌃⌘D` | `{keyCode, modifiers}` |
| `walkthroughs` | `true` | draw steps for "how do I…" questions |
| `panelAutoHideSeconds` | `20` | hovering the panel pauses the timer |
| `screenshotMaxEdge` | `2048` | smaller is faster and cheaper |
| `apiKeys.anthropic` / `apiKeys.openai` | `null` | pay-as-you-go override |

**Other languages.** `base.en` is English only. For Urdu or mixed speech:

```bash
./scripts/download-whisper-model.sh small
```

then point `whisperModel` at `~/.kestrel/models/ggml-small.bin` and set `language` to `auto`.

## Development

```bash
make build     # swift build -c release + assemble Kestrel.app (ad-hoc signed)
make run       # build, then launch
make test      # swift test
make icon      # regenerate icons from assets/kestrel-logo.svg
make deps      # scripts/check-deps.sh
```

- `KESTREL_SPEC.md` is the design of record; `CLAUDE.md` holds the working rules.
- `Tests/MANUAL.md` is the checklist for everything unit tests cannot reach.
- Icons are generated from the original logo by `scripts/icon-tool.swift`; nothing is redrawn.
- **CLI flags drift between releases.** Every invocation is confined to
  `Sources/Kestrel/Backends/ClaudeBackend.swift` and `CodexBackend.swift`, with the verified flags
  in a comment above it. `scripts/check-deps.sh` re-checks them against `--help` and warns on drift.

## What Kestrel never does

- Read, store, or forward OAuth tokens from `~/.claude`, `~/.codex`, or the Keychain
- Call `api.anthropic.com` or `api.openai.com` directly (unless *you* set an API key)
- Capture the screen or the microphone unless a hotkey is held
- Write anywhere outside `~/.kestrel`
- Phone home. There is nowhere to phone.

## Status

v1 complete: **M0** skeleton, **M1** ask, **M2** dictate + Codex, **M3** polish.
**M4** draw-on-screen walkthroughs complete.
Next: **M5** circle-a-region context, **M6** MCP agent tasks.
See `CHANGELOG.md`.
