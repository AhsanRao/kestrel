# Kestrel — a personal AI assistant for your Mac

**Ask. Look. Point. Do.** A voice-first, screen-aware AI assistant for macOS that runs on *your own*
Claude Pro/Max or ChatGPT Plus/Pro subscription — a personal Claude for the desktop, with hands.

Hold a key and talk. Kestrel looks at what is on your screen and answers out loud, draws on the
thing it is talking about, types what you dictate into any app, and carries out what you ask —
"open Chrome and search for owls", "reply to this", "close these tabs" — checking with you before
anything it can't undo. Speech-to-text is on-device. There is no Kestrel backend, no account and
no telemetry: what leaves your Mac is the transcribed question and one screenshot, sent by the
vendors' own CLIs, only while you are holding the key — and, if you turn on [Jev](#deciding-faster-with-jev),
the words alone.

| | |
|---|---|
| **Ask** | Hold `⌘⌥` and speak. Kestrel hears you as you talk, screenshots the front window, asks Claude or Codex at the first pause, then shows and speaks the answer. Keep talking and the next thing you say is the next question. |
| **Dictate** | Tap `⌃⌘K` and talk. The words appear in the frontmost app as you say them, a phrase at a time, and the take ends itself once you have been quiet for a couple of seconds — or on another tap. Newlines are collapsed in terminals so dictation can never run a command. |
| **Show** | Kestrel draws on the real screen while it talks — a pencil rings the thing the answer is about, one mark after another. Ask *"how do I upload a file?"* and the button gets circled while the sentence is spoken. Esc clears it. |
| **Write** | Ask for a reply, an email or a paragraph and you get it as text with a **Copy** button, not read aloud. |
| **Point** | Circle something with the mouse while holding the ask key, then ask about it. |
| **Do** | Ask it to open an app, run a search, close some tabs — it acts, checks the result, and asks before anything it can't undo. Small jobs are done in seconds without a model; what the model works out is remembered for next time. |
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
| Accessibility | the `⌘⌥` hotkey, reading the screen's contents, circling a region, pasting dictation | required for the default hotkey |
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

- **Ask:** hold `⌘⌥`, say *"what is this window for?"* or *"how could this page look better?"*.
  You do not have to let go: the question is heard as you say it and goes off at the first pause,
  so *"open Spotify"* is opening while you draw breath for *"and play something"* — which is asked
  next, in turn. Say "yes" or "no" the same way when it asks before doing something. The island
  opens out of the notch and the answer is spoken — and a pencil draws on the
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
- **Do something:** *"open Safari and search for kestrels"*, *"close these tabs"* — Kestrel carries
  it out, taking a fresh look after each step, and asks before anything it can't undo. See below.
- Both hotkeys are rebindable in Settings ▸ Shortcuts.

**Why these keys.** Asking is held down for as long as you are talking, so it is a bare chord —
`⌘⌥` is one shape the hand already makes, macOS claims nothing on it, and with no letter it cannot
collide with an app's shortcut. It fires after a short dwell so `⌘⌥` on its way to some other
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
| `claudeActModel` | `null` | a different model for requests that act, e.g. `"sonnet"`; `null` uses `claudeModel` |
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
| `liveAsk` | `true` | hear the question as it is said and send it at the first pause, without waiting for the key |
| `askSilenceSeconds` | `1.0` | the pause that sends a phrase off |
| `injectMode` | `"paste"` | `"type"` for apps that reject synthetic ⌘V |
| `hotkeys.ask` / `hotkeys.dictate` | `⌘⌥` / `⌃⌘K` | `{keyCode, modifiers}`; omit `keyCode` for a bare chord |
| `answerAnnotations` | `true` | draw on what a spoken answer is pointing at |
| `followUpSeconds` | `90` | how long a conversation stays warm; 0 disables |
| `sounds` | `true` | short cues for each state change |
| `spatialContext` | `true` | circle a region while holding the ask key |
| `captureMode` | `"window"` | `"display"` to send the whole screen instead |
| `agentTools` | `true` | let Kestrel act on the Mac, not just answer; `false` leaves only "open an app" |
| `maxAgentSteps` | `10` | tool calls one request may make before it gives up |
| `shellAllowlist` | read-only tools | executables `run_shell` may start; extend it here |
| `sensitivePatterns` | delete, send, pay… | words that make an action ask you first |
| `acknowledgeWhileThinking` | `true` | say "one sec" while the model reads the screen |
| `allowMCPServers` | `false` | leave off: MCP discovery added ~10 s to every question |
| `voicePitch` | `0.98` | |
| `transcriptionHint` | `null` | names, Roman Urdu words and jargon to expect |
| `panelAutoHideSeconds` | `20` | hovering the panel pauses the timer |
| `screenshotMaxEdge` | `2048` | smaller is faster and cheaper |
| `apiKeys.anthropic` / `apiKeys.openai` | `null` | pay-as-you-go override |
| `jev.apiKey` | `null` | a Vercel AI Gateway key; turns on Jev, below |
| `jev.endpoint` / `jev.model` | Vercel's TypeSafe endpoint / `typesafe-ai/jev` | to point at TypeSafe directly, or a local model, later |

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

## Doing things

Ask it to *do* something and it does it: "open Safari and search for kestrels", "reply to this email",
"close these tabs". It has six tools — open an app, run an AppleScript, run a shell command, click,
type, press a key — and after each step it takes a fresh look at the screen and decides the next one,
until the job is done or it runs out of steps (ten by default). It prefers AppleScript and named apps
over clicking pixels, because names do not move when a window does.

**It asks before anything it can't take back.** Deleting a file, sending a message, paying for
something, anything typed into a terminal — Kestrel says what it is about to do and waits. Tap the
hotkey to go ahead, or hold it and say "no". A shell command has to be on a short allowlist of
read-only tools, and nothing is ever run as administrator. Every action it takes is written to
`~/.kestrel/logs/actions.jsonl` — menu bar ▸ Open the action log — so you can see afterwards exactly
what happened while you were looking somewhere else.

Turn it off with menu bar ▸ **Act on the Mac**, or `agentTools: false` in the config. With it off,
"open Spotify" still opens Spotify — one verb, nothing to undo — and anything more is described
rather than done. A plain question about the screen is answered the same either way.

## Deciding faster, with Jev

Before any of that, Kestrel has to decide what kind of request it heard: open an app, do something,
or just answer. It used to guess from word lists — "open …" was a launch, "reply" wanted a draft —
and offered the tools to every question just in case. With a key in `jev.apiKey`, that decision
goes to [Jev](https://docs.typesafe.ai/), TypeSafe AI's decision model, through Vercel's AI Gateway:
it is asked a few typed questions about the sentence and answers each with a probability in about
half a second, for a hundredth of a cent. "Can you pull up Finder for me" opens Finder with no model
involved; "open Chrome and search for owls" opens Chrome itself and hands the model the rest with
Chrome already in front; "what does this button do" is answered without the tools attached, which
makes it faster and means it cannot act by mistake; "go to the Extensions tab" is one click and
"search for barn owls" is a new tab, the words and return — and when Jev is sure of the shape, the
control and the words, it is done in a few seconds with no model at all, through the same checks
and the same action log as anything the model does. When the model does have to work a job out,
the steps it took are written under *Recipes* in that app's file in `~/.kestrel/skills/`, so next
time it starts from the route. It also makes the two calls the word lists used to
make while Kestrel acts: whether a step is worth asking you about first ("Sort by order" no longer
stops for the word *order*; Send, Delete and Publish still do) and whether what you said back was a
yes ("yes but not the second one" is now, correctly, a no). Only the words go — the transcript, the name of the app
in front, the labels of the controls on screen — never a screenshot. Without a key nothing changes;
the word lists carry on.

Get a key at [vercel.com/ai-gateway](https://vercel.com/ai-gateway) (a card on file is required,
even for the free credits) and put it in the config:

```json
{ "jev": { "apiKey": "vck_…" } }
```

## Teaching it your own vocabulary

Drop a markdown file in `~/.kestrel/skills/`. `default.md` is sent with every question;
`<bundle id>.md` only while that app is in front. Menu bar ▸ Open skills folder.

## What Kestrel never does

- Read, store, or forward OAuth tokens from `~/.claude`, `~/.codex`, or the Keychain
- Call `api.anthropic.com` or `api.openai.com` directly (unless *you* set an API key)
- Send a screenshot anywhere but the CLI you chose. Jev, when you turn it on, gets words only
- Capture the screen or the microphone unless a hotkey is held
- Write anywhere outside `~/.kestrel`
- Phone home. There is nowhere to phone.

## Status

Working and in daily use by its author. See [`docs/CHANGELOG.md`](docs/CHANGELOG.md) for what has
changed and, more usefully, why.

## Licence

[MIT](LICENSE). Kestrel drives the Claude Code and Codex CLIs; it does not bundle them, and their
own licences and terms of service are yours to keep to — in particular, the single-user note above.
