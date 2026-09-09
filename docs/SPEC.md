# Kestrel — Implementation Specification

The design of record. Where this document and the code disagree, the code is right and this
should be corrected — see `CLAUDE.md`.
**Platform:** macOS 14+ (Apple Silicon), native Swift · **Status:** approved for build

---

## 1. One-paragraph brief

Kestrel is a personal, voice-first, screen-aware assistant for macOS. Hold a hotkey, ask a question about what is on screen, and hear the answer. Toggle another hotkey to dictate into any app. It draws on the real screen while it talks, marking whatever the answer is about, and writes drafts you can copy. It runs entirely on the user's existing **Claude Pro/Max** and/or **ChatGPT Plus/Pro** subscriptions by delegating to the vendors' own CLIs (`claude -p`, `codex exec`), which is the sanctioned way to use those plans programmatically. Speech-to-text is local. There is no Kestrel backend, no accounts, no telemetry.

Kestrel is a single-user tool. Everything a commercial assistant needs in order to serve thousands of people — accounts, billing, a routing backend, telemetry, proactive tracking — is intentionally absent. It runs on the machine, on the owner's own subscriptions, and there is nowhere for it to phone home to.

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
| ChatGPT Plus / Pro | `codex exec` with ChatGPT sign-in (`codex login`) | Rate limits are set by OpenAI; verify current limits in the Codex docs before relying on them. |
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
- Drawing on screen: the answer names what it is talking about and a pencil marks it, one mark after another
- Spatial context: user draws a circle on screen before asking; region is cropped and sent as focus

### v3 — "Do it" — built, then removed
Agent tasks via MCP connectors, an agent HUD, a permission policy and confirmations on destructive
actions were all built and then deleted. Every plan went stale the moment anything on screen moved,
every step needed a confirmation, and the confirmations became something to click through rather
than read. What made Kestrel worth having was never that it could press Send.

Opening an app survives, because it is different in kind: one verb, nothing to undo, no permission
theatre. Anything after that is not done, and Kestrel says so rather than half-doing it.

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
│  ├───────────────┤      │  │ (Apple/wsp) │  │         ├──────────────────┤    │
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
4. `Transcriber` transcribes the WAV on-device. Empty result → `error("Didn't catch that")`.
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
| Global hotkeys | Carbon `RegisterEventHotKey` for a keyed shortcut; `CGEventTap` for a bare modifier chord, which Carbon cannot register | Tap for everything: needs Accessibility just to hear keys. Carbon delivers press **and** release with no permission, so dictation keeps it — but holding ⌃⌥ for the length of a sentence is a better gesture for asking than a chord plus a letter, and that costs the grant. |
| Audio capture | `AVAudioEngine` with `AVAudioConverter` to 16 kHz mono Int16 WAV | Raw Core Audio: more code for no gain |
| Speech-to-text | Apple's `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26+), the system dictation engine, on-device; whisper.cpp CLI as the fallback below macOS 26 and as a config override | `SFSpeechRecognizer`: the old API, weaker and superseded; whisper as the default: ~6× slower on the same clip and a 148 MB model to install; cloud STT: violates local-first |
| Screenshot | `/usr/sbin/screencapture -x` | ScreenCaptureKit: more control, but more code; revisit in v2 for region crops |
| Text-to-speech | Kokoro 82M through sherpa-onnx's CLI, downloaded on first run; `AVSpeechSynthesizer` when it is declined | Cloud TTS: not covered by subscriptions, adds latency. Siri's voices: no API exposes them. Apple's premium voices: audibly worse than Kokoro, which is the whole reason for the download. Python + kokoro-onnx: works, but onboarding would have to install Homebrew Python and a venv |
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
├── README.md                     # user-facing setup and usage
├── docs/
│   ├── SPEC.md                   # this document
│   ├── CHANGELOG.md
│   ├── INTERACTIONS.md           # the system-interaction reference
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
│   ├── download-whisper-model.sh # only needed for the whisper fallback
│   └── check-deps.sh             # verifies claude, codex, and the speech engine
├── Resources/
│   ├── Info.plist.template
│   ├── DefaultMemory.md          # seeded into ~/.kestrel/KESTREL.md on first run
│   └── Prompts/
│       ├── ask.txt               # system framing for screen questions
│       ├── dictation-cleanup.txt
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
│       │   ├── Transcriber.swift          # protocol + RoutingTranscriber
│       │   ├── AppleSpeechTranscriber.swift # SpeechAnalyzer, macOS 26+
│       │   ├── WhisperTranscriber.swift
│       │   ├── Speaker.swift              # protocol behind the two voice engines
│       │   ├── SpeechOutput.swift         # routes to one, strips markdown, checks mute
│       │   ├── SystemSpeaker.swift        # AVSpeechSynthesizer, incl. Personal Voice
│       │   ├── KokoroSpeaker.swift        # sherpa-onnx subprocess, pipelined
│       │   ├── KokoroVoice.swift          # the four offered voices and their speaker ids
│       │   ├── KokoroInstall.swift        # where it lives, and whether it is usable
│       │   └── KokoroDownloader.swift     # the onboarding download
│       ├── Backends/
│       │   ├── Backend.swift              # protocol + Query/Answer contract
│       │   ├── BackendRouter.swift
│       │   ├── ClaudeBackend.swift
│       │   ├── CodexBackend.swift
│       │   └── CLIRunner.swift            # Process wrapper, PATH, timeouts, cancellation
│       ├── Output/
│       │   ├── TextInjector.swift
│       │   ├── PanelWindow.swift
│       │   ├── PanelFrameAnimator.swift   # the window frame, sprung and display-synced
│       │   ├── PanelSpring.swift          # one number on a spring
│       │   ├── PanelView.swift
│       │   └── OverlayWindow.swift        # v2
│       ├── Storage/
│       │   ├── Config.swift
│       │   ├── MemoryStore.swift
│       │   ├── FileDownload.swift         # one file, to one place, with progress
│       │   └── Paths.swift                # ~/.kestrel/* constants
│       └── Settings/
│           ├── SettingsWindow.swift
│           ├── SettingsView.swift
│           ├── OnboardingWindow.swift
│           ├── OnboardingView.swift      # the first-run checklist
│           ├── OnboardingRow.swift
│           ├── OnboardingModel.swift
│           ├── OnboardingMotion.swift    # the window's springs, and Reduce Motion
│           ├── OnboardingInterview.swift # the four questions that seed KESTREL.md
│           ├── KokoroRow.swift
│           └── HotkeyRecorder.swift
└── Tests/
    └── KestrelTests/
        ├── SessionStateTests.swift
        ├── WhisperOutputParsingTests.swift
        ├── AppleSpeechTranscriberTests.swift
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
├── kokoro/                 # optional neural voice: bin/, lib/, model/
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

### 8.4 Transcriber
Kestrel is English-only. Roman Urdu is spoken into an English transcript, which is how it is
written down anyway. `RoutingTranscriber` picks the engine per call from `transcriptionEngine`, so
a config edit applies without a relaunch, and silently uses whisper when Apple's engine cannot run.

**AppleSpeechTranscriber** (default, macOS 26+)
- `SpeechAnalyzer` driving a `SpeechTranscriber(locale: en-US, preset: .transcription)` over the
  recorded WAV; `AnalysisContext.contextualStrings[.general]` carries `transcriptionHint`.
- `AssetInventory.assetInstallationRequest` installs the model on first use — no download to manage,
  nothing in `~/.kestrel/models`. Roughly 0.4 s for 11 s of audio, and silence returns an empty
  string rather than an invented sentence.
- The engine is async and the protocol is blocking; the call is bridged on a semaphore, which is
  safe only because the coordinator calls it from a serial background queue.
- Edge cases: below macOS 26, or `SpeechTranscriber.isAvailable == false` → whisper instead;
  analysis hanging → 120 s timeout; cancellation cancels the task.

**WhisperTranscriber** (fallback and override)
- Runs `whisper-cli -m <model> -f <wav> -nt -np -l en -t N -mc 0 -sns [--prompt <hint>]` and parses
  stdout into a single string.
- Strips timestamps, `[BLANK_AUDIO]`, and stray brackets.
- Edge cases: binary or model missing → actionable error with the exact install commands;
  hallucinated filler on silence (whisper emits "Thank you." on empty audio) → drop results under
  3 characters or matching a small blocklist.

### 8.5 Backend protocol
- Input `Query`: `text`, optional `screenshot` path, optional `focusCrop` path, `mode` (`ask` | `dictationCleanup`), `maxTokens` hint.
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
- v2 option (config flag `autoRoute`): a cheap heuristic picks Codex for short factual questions and Claude for screen-heavy/deep ones. Off by default.

### 8.9 SpeechOutput
- Speaks `Answer.text` with a configurable rate (0.3–0.7) and voice. Strips markdown (code fences,
  bullets, headers) before speaking; the panel keeps the formatted text.
- Interruptible: any new hotkey press stops speech immediately.
- If system output is muted, skip speech and show a "muted, answer on screen" note.
- Two engines behind one `Speaker` protocol, chosen by `voiceEngine`:
  - **Kokoro** (default) — an 82 M-parameter neural model run as a subprocess, the same shape as
    the whisper fallback. Four voices are offered; `af_heart` is the default. Selection is by
    speaker *index*, not name, and the indices come from the model's own `speaker2id` metadata.
  - **System** — `AVSpeechSynthesizer`. Voices are ranked Personal → premium → enhanced → compact,
    with a nudge for the names Apple built for reading long passages and for the listener's own
    region. A Personal Voice reports `.default` quality — the tier the robotic compact voices use —
    so it is ranked on its trait instead, and labelled "Personal" rather than "Compact".
    `requestPersonalVoice()` runs once at launch: a Personal Voice is absent from `speechVoices()`
    until the app has asked for it.
- A missing Kokoro install is not an error. It means the user declined the download, and the system
  voices answer instead — so nothing about speech can ever block first use.
- Kokoro synthesises at roughly 3.6× real time, which is slower than playback is fast, so sentences
  are synthesised on a serial queue *while the previous one plays*. Only the first sentence of an
  answer waits. The model costs about 0.2 s to load and is loaded per sentence, which is cheap
  enough to pay and returns the memory between answers.

### 8.10 TextInjector
- Pasteboard + synthetic ⌘V, restore previous pasteboard contents after the target app consumes the paste.
- Fallback: per-character CGEvent typing when paste is rejected or when config `injectMode = type`.
- Safety: collapse newlines when the frontmost app is a terminal (Terminal, iTerm2, Warp, Ghostty bundle ids) so dictated text can never execute as commands.
- Requires Accessibility permission; prompt once and explain why.

### 8.11 PanelWindow / PanelView
- Non-activating borderless `NSPanel`, hung from the top edge of the display the mouse is on, not
  floating below it: pure black, notch-shaped, so it reads as the camera housing grown wider.
- The collapsed bar is a few points taller than the housing (`NotchMetrics.housingOvershoot`), and
  nothing is drawn over it — no rim, no material — because any edge or lighter value puts a visible
  seam around the notch. It opens downward only when there is something to read.
- Shows: state dot + label, backend badge, transcript (secondary), answer, draft card, hotkey hint.
  Everything is laid out at its full height; nothing scrolls, per §8.17.
- Auto-hide timers: 20 s after answer, 3 s after dictation, 8 s after error, 3 s after "Didn't
  catch that" — nothing was heard, so there is nothing to read. Hover pauses the timer, and the
  session state is cleared on the same clock as the window, not left in `.error` behind it.
- Arrives by unrolling out of the top edge and leaves by rolling back up into it, on the same
  curve reversed — a shape that grows out of the notch has to go back the way it came.
- The window frame follows the island on a spring (`PanelFrameAnimator`, on the same response and
  damping as `PanelView`), not on a fixed curve. A streaming answer resizes the window every
  sentence, and a fixed-duration animation restarted mid-flight jumps; a spring is retargeted from
  where the window actually is, keeping its velocity.
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
| `transcriptionEngine` | `"apple" \| "whisper"` | `"apple"` | `apple` falls back to whisper below macOS 26 |
| `whisperBinary` | path | `/opt/homebrew/bin/whisper-cli` | fallback engine only |
| `whisperModel` | path | `~/.kestrel/models/ggml-base.en.bin` | fallback engine only |
| `speakAnswers` | bool | true | |
| `voiceEngine` | `"kokoro" \| "system"` | `"kokoro"` | falls back to `system` when Kokoro is not installed |
| `kokoroVoice` | string | `"af_heart"` | one of `af_heart`, `af_sarah`, `am_michael`, `am_puck` |
| `voiceIdentifier` | string or null | null | `system` engine only. When null, the best ranked voice: Personal Voice if one exists, else premium |
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

### 8.15 AnnotationOverlay
- Full-screen transparent, click-through `NSWindow` at `.screenSaver` level, spanning every display.
- The answer ends with a `MARK:` line naming targets by number from the list Kestrel offered it, or by
  visible label in quotes. Each becomes one mark, drawn in sequence with a pencil while the sentence
  is spoken: a control is ringed, a block of content is shaded and named. Frames come from the
  Accessibility tree and are re-read at the moment of drawing, so nothing is estimated.
- How many marks depends on the question. One or two for a pointed one; up to six — the ceiling in
  `AnnotationParser.maximumMarks` — when the question is about the whole screen, one per area the
  answer actually names. Marking two areas while talking about five leaves the user hunting for the
  other three, and marking everything is a diagram rather than a gesture.
- Cleared by Esc, by the next question, or by a timer that is measured from the *drawing*, not from
  the answer: marks are made one at a time, so six of them are still being drawn when two would
  have been finished for four seconds (`AnnotationOverlay.lifetime`). Never shorter than the
  panel's own clock plus four seconds.

**Superseded design.** This began as *walkthroughs*: the model returned a numbered route as JSON with
its own coordinates, an overlay drew one step at a time, and a listen-only `CGEventTap` advanced it
each time the user clicked the current target — re-photographing the screen for the next stretch.
Three things were wrong with it. Asking a vision model for coordinates was the wrong instrument (it
landed a button or two off, which is why the Accessibility list replaced it); every plan went stale
the moment anything moved; and taking the drawing away the instant the user clicked meant the answer
vanished exactly when they went to act on it. Kestrel is not driving — the user is. One question, one
answer, marks that stay put.

### 8.16 Spatial context (v2)
- While holding the ask hotkey, the user may drag with the mouse; the overlay shows a paint trail. On release, the bounding box becomes `focusCrop` and is sent alongside the full screenshot with the instruction "the user circled this region."
- The press and release are **swallowed** by a `CGEventTap`, not merely observed. A passive monitor
  cannot consume events, so the gesture also reached the app underneath — selecting text, following
  links, and, because every ask hotkey contains Control and Control-click is the secondary click on
  macOS, opening the context menu over the thing being asked about. Left *and* right buttons are
  watched, since with Control held macOS reports the press as a secondary click.
- The movement between them passes through, and each point is read from the event's own
  coordinates rather than `NSEvent.mouseLocation`. Consuming a drag stops the window server moving
  the pointer: the cursor froze under the hand and every sample came back as the point where the
  press landed, so the trail was a dot, the bounding box fell under `minimumSpan`, and no crop was
  ever sent. An app that sees drags without the press that would have begun them has nothing to
  act on.

### 8.17 Drafts
- "Write me a reply to this" is a different kind of question: the answer is not something to hear and
  not something to point at, it is something to take away. The model answers with one spoken line,
  then `DRAFT:` carrying an optional subject, then the body between `---` fences.
- The body is shown in its own card — selectable, monospaced, laid out at its full height and cut
  off at sixteen lines — with a **Copy** button that puts subject and body on the clipboard. Never
  a scroller: the island's height is decided by measuring its own content, and a scroll view inside
  that measurement collapses to nothing, leaving a card with a copy button and no draft under it.
  It is never spoken: the split is made as the answer streams, so speech stops at the marker rather
  than reading an email aloud.

---

## 9. Prompts (content, not code)

**ask.txt** — Kestrel's voice: someone sitting next to the user who points while they talk. Two
sentences is the normal length. No preamble, no markdown, no describing where things are — name the
thing and mark it. Ends with the `MARK:` contract of §8.15, and the `DRAFT:` contract of §8.17.

**dictation-cleanup.txt** — "Return only the cleaned version of the dictated text: fix punctuation, capitalization, and obvious speech-to-text errors; keep the speaker's words, tone, and language; no em dashes; no additions; no quotes around the output."

---

## 10. Permissions, packaging, distribution

| Permission | Needed by | When prompted |
|---|---|---|
| Microphone | AudioCapture | first hotkey press |
| Screen Recording | ScreenGrabber | first ask; requires relaunch after grant |
| Accessibility | the bare-chord ask hotkey, AXElementScanner, AXContentReader, DragTracker, TextInjector | at launch, because without it the default hotkey cannot fire at all |
| Personal Voice | SpeechOutput, to speak in the user's own voice | at launch; silent when Accessibility ▸ Personal Voice already allows apps to use it |

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
| **M4** | Marks | The answer marks what it names, drawn in sequence, Esc clears | "How do I upload a file here?" answers in a sentence and rings the right control |
| **M5** | Spatial context | Drag-to-circle while holding the hotkey; crop sent with the query | Circling one of several buttons and asking "what does this do?" answers about the circled one |
| **M6** | Agents | Built, then removed — see §3. Only "open an app" remains | — |

Each milestone ends with: tests green, `README` updated, a short `docs/CHANGELOG.md` entry.

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
| Apple's speech engine changing behaviour between macOS releases | `RoutingTranscriber` keeps whisper one config key away, and the dependency check reports which engine is live |
| Screen Recording permission confusion | First-run checklist in the panel with buttons that deep-link to each Privacy pane |
| `claude -p` cold start latency | Keep `~/.kestrel` minimal (no large files); consider `--max-turns 1`; measure and document |
| Panel captured in screenshots | Capture before showing the panel; verify in M1 |
| Terminal command injection via dictation | Newline collapsing when frontmost app is a terminal (8.10) |

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
