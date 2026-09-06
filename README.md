# Kestrel

**Hover. Ask. Do.** — a voice-first, screen-aware assistant for macOS that runs on *your* Claude and
ChatGPT subscriptions.

Hold a key, ask about what is on screen, hear the answer. Tap another key to dictate into any app.
Speech-to-text is local. There is no Kestrel backend, no account, and no telemetry: the only things
that leave your Mac are the transcribed question and one screenshot, sent by the vendors' own CLIs,
only while you are holding the key.

| | |
|---|---|
| **Ask** | Hold `⌃⌘A`, speak, release. Kestrel screenshots the display your mouse is on, transcribes locally with whisper.cpp, asks Claude or Codex, then shows and speaks the answer. |
| **Dictate** | Tap `⌃⌘K`, speak, tap again. The text is cleaned up by the model and pasted into whatever app is frontmost. Newlines are collapsed in terminals so dictation can never run a command. |
| **Show** | Ask *"how do I export as PDF?"* and Kestrel draws numbered steps over the real UI, advancing each time you click the highlighted control. Esc stops it. |
| **Point** | Circle something with the mouse while holding the ask key, then ask about it. |
| **Do** | Say "archive this" or "open Slack" and Kestrel does it — under a policy that asks first. |
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

# 2. Local speech to text
brew install whisper-cpp

# 3. Kestrel
git clone <this repo> && cd kestrel
./scripts/download-whisper-model.sh            # ~148 MB into ~/.kestrel/models
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
| Accessibility | pasting dictation, following clicks in a walkthrough | optional; ask works without it |
| whisper-cli + model | local speech to text | required |
| Claude Code CLI | answering | required |
| Codex CLI | second backend | optional |

The window lets you skip and finish later; Kestrel's error panel also links straight to the right
Privacy pane whenever something turns out to be missing mid-use.

## Using it

- **Ask:** hold `⌃⌘A`, say *"what is this window for?"*, release. The panel shows the answer and
  speaks it. Press the hotkey again to interrupt.
- **Dictate:** tap `⌃⌘K`, speak, tap again. Text lands in the focused app.
- **Be shown:** ask a *"how do I…"*, *"where is…"* or *"show me how…"* question and the answer is
  drawn on screen: click each highlighted control to advance, Esc to stop. Needs Accessibility;
  without it Kestrel reads the steps out instead.

> Where the ring lands is only as good as the model's eye for a screenshot, and that is the weak
> part of this feature — on a toolbar of near-identical buttons it can be a button or two out.
> Each step also names its control, clicks near the ring count, and after two misses the overlay
> lets you advance with a click anywhere.
- Both hotkeys are rebindable in Settings.

`⌃⌘` is the quietest modifier pair on macOS — the system claims only `⌃⌘Space` (Emoji & Symbols),
`⌃⌘D` (Look Up), `⌃⌘F` (Full Screen) and `⌃⌘Q` (Lock Screen), and almost no app uses it. `A` and `K`
are free, so **nothing has to be turned off for Kestrel to work**.

Both are ordinary keyed hotkeys registered through Carbon: no permission needed, press and release
delivered exactly, and no chance of being mistaken for the start of another shortcut.

Rebind either in Settings ▸ General. A modifier-only hotkey (holding `⌥⌘` on its own, say) is also
supported there — hold two or more modifiers and release without pressing a key — but it has to be
watched through an event tap, so it costs an Accessibility grant and briefly arms whenever you use
any shortcut starting with those modifiers. The keyed defaults avoid both problems.

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
| `hotkeys.ask` / `hotkeys.dictate` | `⌃⌘A` / `⌃⌘K` | `{keyCode, modifiers}`; omit `keyCode` for a bare chord |
| `walkthroughs` | `true` | draw steps for "how do I…" questions |
| `agentActions` | `true` | carry out instructions, gated by `policy.json` |
| `followUpSeconds` | `90` | how long a conversation stays warm; 0 disables |
| `sounds` | `true` | short cues for each state change |
| `mcpForTasks` | `false` | MCP connectors for agent tasks only |
| `spatialContext` | `true` | circle a region while holding the ask key |
| `captureMode` | `"window"` | `"display"` to send the whole screen instead |
| `acknowledgeWhileThinking` | `true` | say "one sec" while the model reads the screen |
| `allowMCPServers` | `false` | leave off: MCP discovery added ~10 s to every question |
| `voicePitch` | `0.98` | |
| `transcriptionHint` | `null` | names and jargon to expect, passed to whisper |
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

- [`docs/`](docs/) holds everything: [`SPEC.md`](docs/SPEC.md) is the design of record,
  [`INTERACTIONS.md`](docs/INTERACTIONS.md) documents what Kestrel can do to your Mac,
  [`VS-HEYCLICKY.md`](docs/VS-HEYCLICKY.md) is the feature comparison. `CLAUDE.md` holds the
  working rules.
- **Seeing the real panel.** Offscreen SwiftUI renders cannot show window chrome, materials or
  shadows, which is where panel bugs actually live. To photograph the real thing:

      KESTREL_PREVIEW_PANEL=1 KESTREL_PREVIEW_STATE=listening \
        KESTREL_PREVIEW_OUT=/tmp/panel.png Kestrel.app/Contents/MacOS/Kestrel

  States: `listening`, `thinking`, `answer`, `error`. Without the env vars nothing changes.
- `Tests/MANUAL.md` is the checklist for everything unit tests cannot reach.
- Icons are generated from the original logo by `scripts/icon-tool.swift`; nothing is redrawn.
- **CLI flags drift between releases.** Every invocation is confined to
  `Sources/Kestrel/Backends/ClaudeBackend.swift` and `CodexBackend.swift`, with the verified flags
  in a comment above it. `scripts/check-deps.sh` re-checks them against `--help` and warns on drift.

## Letting Kestrel act

Say what you want done — "archive this", "set the title to Quarterly", "open Slack" — and Kestrel
plans it against the app's real controls and carries it out. Asking *how* to do something still
gets an explanation; when the phrasing is ambiguous it answers rather than acts.

Actions go through Accessibility, so the real cursor never moves and focus is not stolen: you can
keep typing while it works. An overlay names each step, counts them, and Esc stops the run.

**Nothing happens without permission.** `~/.kestrel/policy.json` decides:

```json
{
  "fallback": "confirm",
  "apps": { "com.apple.Terminal": "deny", "com.apple.Safari": "allow" },
  "confirmDestructive": true,
  "blockedKinds": []
}
```

- `fallback` — what to do when no rule matches: `allow`, `confirm` or `deny`. Ships as `confirm`.
- `apps` — per bundle id. Terminals ship denied: typing into one is arbitrary command execution.
- `confirmDestructive` — anything that sends, deletes, buys, posts or overwrites is confirmed even
  in an app you have allowed.

Every action is appended to `~/.kestrel/logs/actions.jsonl`, one JSON object per line.

The complete reference — every action kind, how controls are found, the decision order, the actuator's
fallbacks, and what it deliberately cannot do — is [`docs/INTERACTIONS.md`](docs/INTERACTIONS.md).

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

**M0**–**M6** complete: skeleton, ask, dictate + Codex, polish, walkthroughs, spatial context, and
agent tasks. [`docs/ROADMAP.md`](docs/ROADMAP.md) records what was closed against HeyClicky, and
[`docs/VS-HEYCLICKY.md`](docs/VS-HEYCLICKY.md) compares the two apps feature by feature.
See [`docs/CHANGELOG.md`](docs/CHANGELOG.md).
