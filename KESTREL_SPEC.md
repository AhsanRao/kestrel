# Kestrel — Implementation Specification

**Version:** 0.1 (handoff draft) · **Date:** 2026-09-06 · **Owner:** 0xash
**Platform:** macOS 14+ (Apple Silicon), native Swift · **Status:** approved for build

---

## 1. One-paragraph brief

Kestrel is a personal, voice-first, screen-aware assistant for macOS. Hold a hotkey, ask a question about what is on screen, and hear the answer. Toggle another hotkey to dictate into any app. Later, Kestrel draws on the screen to walk the user through unfamiliar software, and runs background agent tasks through MCP connectors. It runs entirely on the user's existing **Claude Pro/Max** and/or **ChatGPT Plus/Pro** subscriptions by delegating to the vendors' own CLIs (`claude -p`, `codex exec`), which is the sanctioned way to use those plans programmatically. Speech-to-text is local. There is no Kestrel backend, no accounts, no telemetry.

Kestrel is inspired by HeyClicky but is a single-user tool: everything that exists in HeyClicky to serve thousands of users (auth, billing, routing servers, proactive tracking) is intentionally absent.

---

## 2. Principles

| Principle | Consequence |
|---|---|
| **Subscription-native, policy-safe** | Never touch OAuth tokens. Never call vendor REST APIs with subscription credentials. Only spawn the official CLIs as subprocesses. |
| **Local by default** | Audio never leaves the Mac. Only the transcribed question and a screenshot go to the chosen provider, only when the user presses the hotkey. |
| **Hotkey-triggered, never watching** | No always-on screen capture, no accessibility scraping, no activity logging. Kestrel is inert until a key is pressed. |
| **Native and light** | Swift + AppKit/SwiftUI, no Electron, no Node runtime in the app. Idle CPU near zero. |
| **Provider-agnostic** | A `Backend` protocol isolates vendor differences. Switching Claude ↔ Codex is one menu click. |
| **Ship vertically** | Each milestone is a complete, usable slice. M1 is usable on day one. |

---

## 3. Subscription and licensing constraints

| Plan | Mechanism | Notes |
|---|---|---|
| Claude Pro / Max | `claude -p` (headless Claude Code), which is Agent SDK usage | Since 2026-06-15, Pro/Max users claim a separate monthly **Agent SDK credit**; `claude -p` bills against it, not interactive limits. Must be claimed in account settings. Ref: https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan |
| ChatGPT Plus / Pro | `codex exec` with ChatGPT sign-in (`codex login`) | Same approach HeyClicky uses. Rate limits are set by OpenAI; verify current limits in Codex docs before relying on them. |
| Either | API key mode | Optional fallback: if the user sets an API key in config, the same CLIs accept `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` env vars. Pay-as-you-go. |

**Hard rule for the build:** Kestrel is single-user. If it is ever shared with another person, it must use API keys. The code should make this obvious in comments and README.

**Not covered by subscriptions:** realtime speech-to-speech APIs. Kestrel therefore uses a turn-based loop (record → transcribe → think → speak), not a live conversation. Target end-to-end latency: under 5 s for a simple screen question on an M4.

---

## 4. Scope

### v1 (Milestones M1–M3) — "Ask and dictate"
- Push-to-talk screen Q&A with spoken + written answer
- Dictation into any app, with optional LLM cleanup
- Claude / Codex switch
- Memory file loaded by both backends
- Menu bar presence, floating status panel, settings window

### v2 (M4–M5) — "Show me"
- Draw-on-screen walkthroughs: model returns step coordinates, overlay renders them, advances on click
- Spatial context: user draws a circle on screen before asking; region is cropped and sent as focus

### v3 (M6) — "Do it"
- Agent tasks via MCP connectors (Gmail, Calendar, Drive, Notion, Linear) using the CLIs' native MCP support
- Agent HUD with cancel/retry, confirmation on destructive actions

### Explicitly out of scope
- Realtime streaming voice, wake word, always-on listening
- Proactive suggestions or any background activity tracking
- Multi-user, teams, cloud sync, mobile
- Windows/Linux

---

## 5. System architecture

### 5.1 Component map

```
┌──────────────────────────── Kestrel.app (Swift) ─────────────────────────────┐
│                                                                              │
│  Input layer            Core                         Output layer            │
│  ┌───────────────┐      ┌──────────────────┐         ┌──────────────────┐    │
│  │ HotkeyService │─────▶│ SessionCoordinator│────────▶│ PanelWindow      │    │
│  │ (Carbon)      │      │ (state machine)   │         │ (SwiftUI)        │    │
│  ├───────────────┤      │                  │         ├──────────────────┤    │
│  │ AudioCapture  │─────▶│  ┌────────────┐  │────────▶│ SpeechOutput     │    │
│  │ (AVAudioEngine)│     │  │ Transcriber │  │         │ (AVSpeechSynth)  │    │
│  ├───────────────┤      │  │ (whisper)   │  │         ├──────────────────┤    │
│  │ ScreenGrabber │─────▶│  └────────────┘  │────────▶│ TextInjector     │    │
│  │ (screencapture)│     │  ┌────────────┐  │         │ (paste + restore)│    │
│  └───────────────┘      │  │ Backend    │  │         ├──────────────────┤    │
│                         │  │ Router     │  │────────▶│ OverlayWindow    │ v2 │
│  ┌───────────────┐      │  └─────┬──────┘  │         │ (annotations)    │    │
│  │ MemoryStore   │─────▶│        │         │         └──────────────────┘    │
│  │ (KESTREL.md)  │      └────────┼─────────┘                                 │
│  └───────────────┘               │                                            │
└──────────────────────────────────┼────────────────────────────────────────────┘
                                   │ subprocess, cwd = ~/.kestrel
                    ┌──────────────┴───────────────┐
                    ▼                              ▼
             claude -p                       codex exec
          (Claude Pro/Max)                (ChatGPT Plus/Pro)
                    │                              │
                    └──────── MCP servers (v3) ────┘
```

### 5.2 Request flow — screen question (v1)

1. User presses and holds `⌃⌥Space`. `HotkeyService` emits `pressed(.ask)`.
2. `SessionCoordinator` moves `idle → listening`, starts `AudioCapture`, shows `PanelWindow` at top-center.
3. User releases. Coordinator immediately calls `ScreenGrabber.capture()` (before the panel can change what's on screen), stops audio, moves to `transcribing`.
4. `Transcriber` runs whisper.cpp on the WAV. Empty result → `error("Didn't catch that")`.
5. Coordinator moves to `thinking`, builds a `Query { text, screenshotURL, focusRegion? }`, calls `BackendRouter.ask(query)`.
6. Selected backend spawns its CLI with cwd `~/.kestrel` (so memory files are loaded), passes the screenshot, waits for the result.
7. Coordinator moves to `answering`: panel shows text, `SpeechOutput` speaks it (if enabled). Temp files deleted.
8. Panel auto-hides after a configurable delay. Another hotkey press interrupts speech.

### 5.3 Request flow — dictation (v1)

1. `⌃⌥D` toggles `dictating`. Panel shows a red indicator.
2. Second `⌃⌥D` stops capture, transcribes.
3. If `cleanupDictation` is on: backend is asked to fix punctuation/grammar with a strict "return only the text" prompt. If it fails or times out, fall back to the raw transcript.
4. `TextInjector` writes to the pasteboard, sends ⌘V to the focused app, restores the previous pasteboard after ~400 ms. Falls back to typing via CGEvent key events if paste is rejected (terminals, some Electron apps).

### 5.4 State machine

```
idle ──ask.press──▶ listening ──ask.release──▶ transcribing ──▶ thinking ──▶ answering ──timeout──▶ idle
 │                                                                              │
 ├──dict.press──▶ dictating ──dict.press──▶ transcribing ──▶ (cleanup) ──▶ injecting ──▶ idle
 │                                                                              │
 └──── any failure ──▶ error ──▶ idle (after 8 s)      any ask.press while answering ──▶ stop speech, listening
```

Rules: only one session at a time; a hotkey during `transcribing`/`thinking` is ignored (with a subtle panel pulse); `dictating` and `listening` are mutually exclusive.

---

## 6. Technology decisions

| Concern | Choice | Alternatives rejected and why |
|---|---|---|
| Language / UI | Swift 5.9, AppKit shell with SwiftUI views | Electron/Tauri: heavier, worse permission story, not "native" |
| Build system | Swift Package Manager + `build.sh` to assemble the `.app` bundle; Xcode project added only if needed for signing/notarization later | Xcode project first: slower to iterate, harder for Claude Code to edit |
| Global hotkeys | Carbon `RegisterEventHotKey` | `CGEventTap`: needs Accessibility just to hear keys; Carbon delivers press **and** release with no permission |
| Audio capture | `AVAudioEngine` with `AVAudioConverter` to 16 kHz mono Int16 WAV | Raw Core Audio: more code for no gain |
| Speech-to-text | whisper.cpp CLI (`brew install whisper-cpp`), model `ggml-base.en` default, `small` for multilingual | Apple `SFSpeechRecognizer`: weaker accuracy, language-limited on-device; cloud STT: violates local-first |
| Screenshot | `/usr/sbin/screencapture -x` | ScreenCaptureKit: more control, but more code; revisit in v2 for region crops |
| Text-to-speech | `AVSpeechSynthesizer`, prefer premium/enhanced voice if installed | Cloud TTS: not covered by subscriptions, adds latency |
| LLM access | Subprocess to `claude` / `codex` CLIs | Direct API + OAuth: prohibited. Agent SDK library: fine for Claude but Codex has no equivalent; the CLI boundary keeps both symmetrical |
| Config | JSON at `~/.kestrel/config.json` | `UserDefaults`: hard to hand-edit and version |
| Memory | Markdown `~/.kestrel/KESTREL.md`, symlinked as `CLAUDE.md` and `AGENTS.md` | Both CLIs auto-load their file from cwd, so one file serves both |
| Logging | `os.Logger` with subsystem `dev.0xash.kestrel`; optional file log at `~/.kestrel/logs/` | |
| Tests | `swift test` for pure modules (transcript parsing, backend output parsing, state machine); manual checklist for UI/permissions | |

---

## 7. Repository layout

```
kestrel/
├── CLAUDE.md                     # instructions for Claude Code (see §17)
├── KESTREL_SPEC.md               # this document
├── README.md                     # user-facing setup and usage
├── Package.swift
├── build.sh                      # swift build → Kestrel.app, ad-hoc codesign
├── Makefile                      # make build / run / test / clean / icon
├── .gitignore
├── assets/
│   ├── kestrel-logo.svg          # app icon source
│   ├── kestrel-menubar-template.svg  # monochrome template icon
│   └── AppIcon.iconset/          # generated PNG sizes (script in scripts/)
├── scripts/
│   ├── make-icon.sh              # svg → iconset → .icns
│   ├── download-whisper-model.sh
│   └── check-deps.sh             # verifies claude, codex, whisper-cli, model
├── Resources/
│   ├── Info.plist.template
│   ├── DefaultMemory.md          # seeded into ~/.kestrel/KESTREL.md on first run
│   └── Prompts/
│       ├── ask.txt               # system framing for screen questions
│       ├── dictation-cleanup.txt
│       └── walkthrough.txt       # v2: JSON step schema instructions
├── Sources/
│   └── Kestrel/
│       ├── App/
│       │   ├── main.swift
│       │   ├── AppDelegate.swift
│       │   └── StatusMenu.swift
│       ├── Core/
│       │   ├── SessionCoordinator.swift   # state machine + orchestration
│       │   ├── SessionState.swift
│       │   ├── Query.swift                # Query, Answer, Step models
│       │   └── Errors.swift
│       ├── Input/
│       │   ├── HotkeyService.swift
│       │   ├── AudioCapture.swift
│       │   └── ScreenGrabber.swift
│       ├── Speech/
│       │   ├── Transcriber.swift          # protocol
│       │   ├── WhisperTranscriber.swift
│       │   └── SpeechOutput.swift
│       ├── Backends/
│       │   ├── Backend.swift              # protocol + Query/Answer contract
│       │   ├── BackendRouter.swift
│       │   ├── ClaudeBackend.swift
│       │   ├── CodexBackend.swift
│       │   └── CLIRunner.swift            # Process wrapper, PATH, timeouts, cancellation
│       ├── Output/
│       │   ├── TextInjector.swift
│       │   ├── PanelWindow.swift
│       │   ├── PanelView.swift
│       │   └── OverlayWindow.swift        # v2
│       ├── Storage/
│       │   ├── Config.swift
│       │   ├── MemoryStore.swift
│       │   └── Paths.swift                # ~/.kestrel/* constants
│       └── Settings/
│           ├── SettingsWindow.swift
│           └── SettingsView.swift
└── Tests/
    └── KestrelTests/
        ├── SessionStateTests.swift
        ├── WhisperOutputParsingTests.swift
        ├── BackendOutputParsingTests.swift
        └── ConfigTests.swift
```

User data directory (created on first launch):

```
~/.kestrel/
├── config.json
├── KESTREL.md              # memory: profile + current project
├── CLAUDE.md -> KESTREL.md
├── AGENTS.md -> KESTREL.md
├── models/ggml-base.en.bin
├── skills/                 # v2: per-app markdown snippets injected by bundle id
└── logs/
```

---

## 8. Module specifications

Each module lists responsibility, interface (described, not coded), and edge cases Claude Code must handle.

### 8.1 HotkeyService
- Registers two global hotkeys with Carbon; delivers `pressed`/`released` events on the main thread.
- Defaults: `⌃⌥Space` = ask (hold), `⌃⌥D` = dictation (toggle). Configurable via `config.json` (key code + modifiers). Settings UI in M3.
- Edge cases: re-register on config change; ignore auto-repeat; Caps Lock must not break modifiers; if registration fails (conflict), surface a panel error naming the conflicting combo.

### 8.2 AudioCapture
- Starts/stops recording from the default input to a temp 16 kHz mono Int16 WAV.
- Edge cases: input device disappears mid-record (AirPods dropping) → stop gracefully and keep what was captured; sample-rate mismatch (pro interfaces at 44.1/96 kHz) → converter handles; zero-length recording (< 300 ms) → treat as accidental press, do nothing; max duration 10 min for dictation, 60 s for ask.

### 8.3 ScreenGrabber
- Captures the display containing the mouse cursor (not all displays) as PNG. Downscale to max 2048 px on the long edge before sending to keep tokens and latency down.
- v2: accept a focus rect and produce both the full frame and a crop.
- Edge cases: Screen Recording permission missing → error with a deep link to the Privacy pane; multiple displays; the Kestrel panel itself must be hidden or excluded from the capture (capture before showing, or order the panel out for the grab).

### 8.4 Transcriber (WhisperTranscriber)
- Runs `whisper-cli -m <model> -f <wav> -nt -np --no-prints -l <lang|auto>` and parses stdout into a single string.
- Strips timestamps, `[BLANK_AUDIO]`, and stray brackets. Language from config; `auto` default.
- Edge cases: binary or model missing → actionable error with the exact install commands; hallucinated filler on silence (whisper emits "Thank you." on empty audio) → drop results under 3 characters or matching a small blocklist; Urdu/mixed-language dictation → recommend `small` model in README.

### 8.5 Backend protocol
- Input `Query`: `text`, optional `screenshot` path, optional `focusCrop` path, `mode` (`ask` | `dictationCleanup` | `walkthrough`), `maxTokens` hint.
- Output `Answer`: `text`, `raw` (full CLI output for debugging), `durationMs`, optional `steps` (v2).
- Requirements: cancellable (kill the subprocess), timeouts (ask 120 s, cleanup 30 s), never throws on non-zero exit without including stderr in the error.

### 8.6 ClaudeBackend
- Command contract (verify against `claude --help` at build time; flags drift):
  `claude -p "<prompt>" --output-format json --allowedTools Read [--model <m>]`, cwd `~/.kestrel`.
- Screenshot is passed by instructing the model to `Read` the PNG path; Claude Code's Read tool handles images.
- Parse the JSON envelope's `result` field; fall back to raw stdout.
- Prompt framing lives in `Resources/Prompts/ask.txt` and is prepended to the user's question. Memory is loaded automatically from `CLAUDE.md` in cwd.
- v3: widen `--allowedTools` to include MCP tools; add `--permission-mode` handling.

### 8.7 CodexBackend
- Command contract (verify against `codex exec --help`):
  `codex exec --sandbox read-only --skip-git-repo-check --output-last-message <file> [--image <png>] [--model <m>] "<prompt>"`, cwd `~/.kestrel`.
- Read the answer from the last-message file; fall back to stdout.
- Memory loaded from `AGENTS.md` automatically.
- v3: switch sandbox to `workspace-write` and enable MCP servers from `~/.codex/config.toml`.

### 8.8 BackendRouter
- v1: returns the backend named in config. Exposes `switch(to:)` and `current`.
- v2 option (config flag `autoRoute`): a cheap heuristic picks Codex for short factual questions and Claude for screen-heavy/deep ones, mirroring HeyClicky's router. Off by default.

### 8.9 SpeechOutput
- Speaks `Answer.text` with a configurable rate (0.3–0.7) and voice identifier. Strips markdown (code fences, bullets, headers) before speaking; the panel keeps the formatted text.
- Interruptible: any new hotkey press stops speech immediately.
- If system output is muted, skip speech and show a "muted, answer on screen" note.

### 8.10 TextInjector
- Pasteboard + synthetic ⌘V, restore previous pasteboard contents after the target app consumes the paste.
- Fallback: per-character CGEvent typing when paste is rejected or when config `injectMode = type`.
- Safety: collapse newlines when the frontmost app is a terminal (Terminal, iTerm2, Warp, Ghostty bundle ids) so dictated text can never execute as commands.
- Requires Accessibility permission; prompt once and explain why.

### 8.11 PanelWindow / PanelView
- Non-activating floating `NSPanel`, top-center of the active display, width 420, material background, draggable.
- Shows: state dot + label, backend badge, transcript (secondary), answer (selectable, scrollable, markdown-lite), hotkey hint.
- Auto-hide timers: 20 s after answer, 3 s after dictation, 8 s after error. Hover pauses the timer.
- Must be excluded from screenshots (see 8.3).

### 8.12 StatusMenu
- Menu bar item using the monochrome template icon. Items: backend picker (radio), Speak answers (toggle), Cleanup dictation (toggle), Open memory file, Open settings, Check dependencies, Quit.

### 8.13 Config
- JSON schema (all keys optional, defaults applied):

| Key | Type | Default | Notes |
|---|---|---|---|
| `backend` | `"claude" \| "codex"` | `"claude"` | |
| `claudeModel` / `codexModel` | string or null | null | CLI default when null |
| `autoRoute` | bool | false | v2 |
| `whisperBinary` | path | `/opt/homebrew/bin/whisper-cli` | |
| `whisperModel` | path | `~/.kestrel/models/ggml-base.en.bin` | |
| `language` | string | `"auto"` | whisper language code |
| `speakAnswers` | bool | true | |
| `voiceIdentifier` | string or null | null | premium voice if present |
| `voiceRate` | float | 0.52 | |
| `cleanupDictation` | bool | true | |
| `injectMode` | `"paste" \| "type"` | `"paste"` | |
| `hotkeys.ask` / `hotkeys.dictate` | `{keyCode, modifiers}` | ⌃⌥Space / ⌃⌥D | |
| `panelAutoHideSeconds` | int | 20 | |
| `screenshotMaxEdge` | int | 2048 | |
| `apiKeys.anthropic` / `apiKeys.openai` | string or null | null | optional pay-as-you-go override |

- Reload on file change (FSEvents/DispatchSource) so hand edits apply without relaunch.

### 8.14 MemoryStore
- Seeds `KESTREL.md` from `Resources/DefaultMemory.md` on first launch; creates the two symlinks.
- Provides "Open memory" action. v2: an "update memory" command where the assistant proposes a one-line addition and the user approves it in the panel (never silent writes).

### 8.15 OverlayWindow (v2)
- Full-screen transparent, click-through `NSWindow` at `.screenSaver` level per display.
- Renders steps from the walkthrough JSON: hand-drawn-style rounded rect or circle at `{x,y,w,h}`, numbered label, short instruction. Coordinates are in screenshot pixel space; convert using the capture scale factor.
- Advances when a global click lands inside the current target (CGEventTap listen-only for mouse clicks, which needs Accessibility, already granted for dictation). Clears on Esc or when the walkthrough completes.
- Walkthrough prompt (`Resources/Prompts/walkthrough.txt`) instructs the model to return strict JSON: `{ "goal": "...", "steps": [ { "n": 1, "instruction": "...", "target": {"x":..,"y":..,"w":..,"h":..}, "shape": "rect|circle" } ] }`, max 15 steps. Parse defensively; if invalid, fall back to spoken/text steps with no drawing.

### 8.16 Spatial context (v2)
- While holding the ask hotkey, the user may drag with the mouse; the overlay shows a paint trail. On release, the bounding box becomes `focusCrop` and is sent alongside the full screenshot with the instruction "the user circled this region."

### 8.17 Agents (v3)
- Reuse the CLIs' MCP support. Kestrel's job: connector setup UI (which writes `claude mcp add` / Codex config), an agent HUD with live status from the CLI's streaming JSON output, cancel/retry, and a confirmation prompt before any tool call that sends, deletes, or pays.
- Intent detection: the ask prompt asks the model to reply with either an answer or `{"agent_task": "..."}`; the coordinator spawns a longer-running session for the latter.

---

## 9. Prompts (content, not code)

**ask.txt** — "You are Kestrel, a concise assistant on the user's Mac. A screenshot path is provided; read it first. Answer in 2–4 spoken-friendly sentences unless asked for detail. Refer to on-screen elements by their visible labels. If the question needs steps, give numbered steps. Never describe the screenshot unless asked."

**dictation-cleanup.txt** — "Return only the cleaned version of the dictated text: fix punctuation, capitalization, and obvious speech-to-text errors; keep the speaker's words, tone, and language; no em dashes; no additions; no quotes around the output."

**walkthrough.txt** — the JSON schema in §8.15 plus: "Coordinates are pixels in the provided screenshot. Prefer fewer, larger targets. If the goal cannot be completed on the current screen, return the first step only and set `needs_more: true`."

---

## 10. Permissions, packaging, distribution

| Permission | Needed by | When prompted |
|---|---|---|
| Microphone | AudioCapture | first hotkey press |
| Screen Recording | ScreenGrabber | first ask; requires relaunch after grant |
| Accessibility | TextInjector, v2 click detection | first dictation |

- `Info.plist`: `LSUIElement = true` (menu bar only), usage-description strings for microphone and Apple events, bundle id `dev.0xash.kestrel`.
- Ad-hoc codesign for personal use. TCC grants are tied to the bundle id + signature, so keep the signing identity stable across builds (ad-hoc is fine as long as the bundle id does not change).
- Icon: `scripts/make-icon.sh` converts `assets/kestrel-logo.svg` into `AppIcon.icns` (1024→16 px set). Menu bar uses the template SVG rendered as a 36×36 @2x PDF or PNG with `isTemplate = true`.
- Launch at login via `SMAppService` (M3).

---

## 11. Milestones and acceptance criteria

| # | Milestone | Deliverable | Done when |
|---|---|---|---|
| **M0** | Skeleton | Package builds, menu bar icon appears, `scripts/check-deps.sh` reports status of claude/codex/whisper | `make build && open Kestrel.app` shows the icon; quitting works |
| **M1** | Ask | Hotkey → record → whisper → screenshot → Claude → panel + speech | Ask "what app is this?" about any window and get a correct spoken answer in < 6 s; errors are readable in the panel |
| **M2** | Dictate + Codex | Dictation into TextEdit, Slack, VS Code, Terminal (newline-safe); Codex backend selectable; clipboard restored | Dictate a 30-second paragraph into three apps with no lost text; switch backend and repeat M1 |
| **M3** | Polish | Settings window, hotkey rebinding, voice picker, launch at login, config hot-reload, app icon, README | A fresh Mac can follow README and reach M1 without reading code |
| **M4** | Walkthroughs | Overlay draws steps, advances on click, Esc clears | "How do I export as PDF in this app?" produces ≥2 drawn steps that land on the right controls |
| **M5** | Spatial context | Drag-to-circle while holding the hotkey; crop sent with the query | Circling one of several buttons and asking "what does this do?" answers about the circled one |
| **M6** | Agents | MCP connector setup, agent HUD, confirmations | "Add a Linear ticket for the bug on screen" creates the ticket after one confirmation |

Each milestone ends with: tests green, `README` updated, a short `CHANGELOG.md` entry.

---

## 12. Testing plan

- **Unit (swift test):** state machine transitions incl. interruptions; whisper stdout parsing (timestamps, blank audio, multiline); Claude JSON envelope parsing incl. malformed output; Codex last-message fallback; config defaults and partial files; markdown stripping for speech.
- **Integration (manual, scripted checklist in `Tests/MANUAL.md`):** permissions flow on a clean user account; Bluetooth device switch mid-recording; muted output; no-network behavior (clear error, no hang); each backend missing; 10-minute dictation.
- **Latency budget (log and assert in debug builds):** capture stop → transcript ≤ 800 ms (base.en); transcript → CLI exit ≤ 4 s typical; speech starts ≤ 200 ms after answer.

---

## 13. Risks and mitigations

| Risk | Mitigation |
|---|---|
| CLI flags change between releases | Isolate all invocations in `ClaudeBackend`/`CodexBackend`; `check-deps.sh` runs `--help` and greps for expected flags; README documents how to adjust |
| Subscription policy changes again | Backends accept API keys as a drop-in; README states the single-user rule plainly |
| Agent SDK credit exhausted mid-month | Detect the CLI's quota error string and show "credit exhausted, switch to Codex or API key" |
| Whisper accuracy for Urdu/mixed speech | Ship instructions for `small`/`medium` models; language override in settings |
| Screen Recording permission confusion | First-run checklist in the panel with buttons that deep-link to each Privacy pane |
| `claude -p` cold start latency | Keep `~/.kestrel` minimal (no large files); consider `--max-turns 1`; measure and document |
| Panel captured in screenshots | Capture before showing the panel; verify in M1 |
| Terminal command injection via dictation | Newline collapsing when frontmost app is a terminal (8.10) |

---

## 14. Open questions for the owner

1. Default hotkeys OK (`⌃⌥Space`, `⌃⌥D`), or prefer Fn-based like HeyClicky? (Fn requires CGEventTap + Accessibility.)
2. Should dictation cleanup default **on** (better text, +1–2 s) or **off** (instant)?
3. Whisper model default: `base.en` (fast, English) or `small` (multilingual, ~2× slower)?
4. Is a Settings window required for v1, or is editing `config.json` acceptable until M3?

---

## 15. Brand

| Element | Spec |
|---|---|
| Name | **Kestrel** — a bird that hovers in place, watching the ground below. Kestrel hovers over your screen, sees, and acts. |
| Tagline | "Hover. Ask. Do." |
| App icon | `assets/kestrel-logo.svg`: cream kestrel silhouette hovering above a blue focus ring with an amber center point, on deep navy squircle |
| Menu bar icon | `assets/kestrel-menubar-template.svg`, monochrome template so it adapts to light/dark menu bars |
| Palette | Navy `#0F1B2D` (background) · Ring blue `#2E5C8A` · Cream `#F5F1E8` (bird, primary text on navy) · Amber `#F2B233` (focus/accent, listening indicator) |
| Panel states | idle gray · listening amber pulse · thinking blue · answering cream · error coral `#D85A30` |
| Typography | SF Pro (system). Panel: 13 pt body, 11 pt secondary. Never below 10 pt |
| Voice | Concise, friendly, no filler. Answers sound like a colleague looking over your shoulder |

---

## 16. Reference: what Kestrel borrows from HeyClicky and what it drops

| HeyClicky | Kestrel |
|---|---|
| Notch UI | Floating panel + menu bar (notch-docking is a v3 nicety) |
| Bundled Codex agent harness | Same idea, but the CLIs stay external and user-installed so they update independently |
| Backend model router | Local config switch; optional heuristic router in v2 |
| PROFILE.md + VOLATILE.md | Single `KESTREL.md` with two sections, loaded natively by both CLIs |
| Skills library | `~/.kestrel/skills/*.md` injected by frontmost bundle id (v2) |
| Realtime voice | Turn-based; deliberate trade-off |
| Proactive agents / activity tracking | Never |
| Accounts, billing, teams | None |

---

## 17. Handoff instructions for Claude Code

Place `CLAUDE.md` (provided alongside this spec) at the repo root. Start with:

> "Read KESTREL_SPEC.md fully. Implement milestone M0, then stop and show me the build output. Do not implement later milestones until I approve each one."

Working agreement for the build:
- One milestone per session; each ends with `make test` green and a commit.
- Before writing any CLI invocation, run `claude --help` and `codex exec --help` and paste the relevant flags into the code comments.
- Never store or read OAuth tokens; never call `api.anthropic.com` or `api.openai.com` directly unless an API key is explicitly configured.
- Prefer small files (< 200 lines) mirroring §7; do not introduce third-party Swift packages without asking.
- When a macOS API is uncertain, write the smallest possible spike, build it, and report before integrating.
