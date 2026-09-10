# Kestrel — Implementation Specification

The design of record. Where this document and the code disagree, the code is right and this
should be corrected — see `CLAUDE.md`.
**Platform:** macOS 14+ (Apple Silicon), native Swift · **Status:** approved for build

---

## 1. One-paragraph brief

Kestrel is a personal, voice-first, screen-aware assistant for macOS. Hold a hotkey, ask a question about what is on screen, and hear the answer. Tap another hotkey and talk, and the words appear in whatever app you are in as you say them, stopping when you do. It draws on the real screen while it talks, marking whatever the answer is about, and writes drafts you can copy. It runs entirely on the user's existing **Claude Pro/Max** and/or **ChatGPT Plus/Pro** subscriptions by delegating to the vendors' own CLIs (`claude -p`, `codex exec`), which is the sanctioned way to use those plans programmatically. Speech-to-text is local. There is no Kestrel backend, no accounts, no telemetry.

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
3. User releases. Three jobs start at once, because all three describe that one moment and none needs the others: `ScreenGrabber.capture()` on `captureQueue`, `ScreenSnapshot.read()` on `scanQueue`, and the transcription on `work`. Coordinator moves to `transcribing`.
4. `Transcriber` transcribes the WAV on-device. Empty result → `error("Didn't catch that")`.
5. Coordinator moves to `thinking` and schedules an `Acknowledgement` — a short spoken line, said only if the answer has not begun within 450 ms. Builds a `Query` from the transcript and the snapshot that is already waiting, calls `BackendRouter.ask(query)`.
6. Selected backend spawns its CLI with cwd `~/.kestrel` (so memory files are loaded), passes the screenshot, waits for the result.
7. Coordinator moves to `answering`: panel shows text, `SpeechOutput` speaks it (if enabled). Temp files deleted.
8. Panel auto-hides after a configurable delay. Another hotkey press interrupts speech.

### 5.3 Request flow — dictation (v1)

Live, where the engine can stream — macOS 26 with Apple's transcriber, which is the default:

1. The hotkey toggles `dictating`. `AppleLiveDictation` starts, feeding the microphone into
   `SpeechAnalyzer` as it is spoken rather than recording a file.
2. Each settled stretch of speech is tidied by `DictationTidy.cleanFragment` and typed straight into
   the app, a phrase at a time, while the sentence is still going. The engine's running guess goes
   on the panel and nowhere else: it is rewritten with every syllable, and nothing that changes
   belongs in the user's document.
3. The take ends on the hotkey again, or on a pause of `dictationSilenceSeconds` — see
   `SilenceWatch` for what counts as a pause.
4. There is no model cleanup pass on this path. It rewrites a finished paragraph, and the paragraph
   is already in the user's document a phrase at a time; `cleanupDictation` still governs the local
   rules, which is what makes a phrase safe to type the moment it lands.

Recorded, under whisper or below macOS 26:

1. The hotkey toggles `dictating`; the second press stops capture and transcribes the WAV.
2. If `cleanupDictation` is on: `DictationTidy` fixes punctuation, capitals, fillers and spoken commands ("comma", "new line") locally, in microseconds. Only text over `DictationTidy.wordsWorthAModel` words then goes to the backend, with the tidied version as the fallback if that fails or times out.
3. `TextInjector` writes to the pasteboard, sends ⌘V to the focused app, restores the previous pasteboard after ~400 ms. Falls back to typing via CGEvent key events if paste is rejected (terminals, some Electron apps).

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
| Global hotkeys | Carbon `RegisterEventHotKey` for a keyed shortcut; `CGEventTap` for a bare modifier chord, which Carbon cannot register | Tap for everything: needs Accessibility just to hear keys. Carbon needs no permission, which is why the keyed shortcut keeps it — but its release event is not dependable: let the modifiers up before the key, as most people do, and `kEventHotKeyReleased` never arrives. Dictation is a toggle and only reads presses, so it does not care; the held ask gesture is a chord for other reasons anyway. |
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
│       │   ├── StatusMenu.swift
│       │   ├── PreviewCapture.swift       # the probes' one screenshot routine
│       │   └── *Preview.swift             # open a window, photograph it, quit
│       ├── Core/
│       │   ├── SessionCoordinator.swift   # state machine + orchestration
│       │   ├── SessionCoordinator+Finishing.swift  # temp files, errors, the panel's clock
│       │   ├── ScreenSnapshot.swift       # controls, regions and text, read as one unit
│       │   ├── SessionState.swift
│       │   ├── Query.swift                # Query, Answer, Step models
│       │   └── Errors.swift
│       ├── Input/
│       │   ├── HotkeyService.swift
│       │   ├── AudioCapture.swift
│       │   └── ScreenGrabber.swift
│       ├── Speech/
│       │   ├── Transcriber.swift          # protocol + RoutingTranscriber
│       │   ├── AppleSpeechTranscriber.swift # SpeechAnalyzer on a finished file, macOS 26+
│       │   ├── LiveDictation.swift        # protocol + what this Mac can actually stream
│       │   ├── AppleLiveDictation.swift   # SpeechAnalyzer on the live microphone
│       │   ├── AppleLiveDictation+Audio.swift # the tap, the format conversion, the level
│       │   ├── SilenceWatch.swift         # the pause that ends a live take
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
│       │   ├── DictationTidy.swift        # punctuation and capitals, without a model
│       │   ├── PanelWindow.swift
│       │   ├── KestrelPalette.swift       # the colours, by the job they do
│       │   ├── PanelFrameAnimator.swift   # the window frame, sprung and display-synced
│       │   ├── PanelSpring.swift          # one number on a spring
│       │   ├── ClippedText.swift          # text cut at a line count, saying how much is left
│       │   ├── TextFit.swift              # how many lines a string needs, via CoreText
│       │   ├── PanelView.swift
│       │   └── OverlayWindow.swift        # v2
│       ├── Storage/
│       │   ├── Config.swift
│       │   ├── MemoryStore.swift
│       │   ├── FileDownload.swift         # one file, to one place, with progress
│       │   └── Paths.swift                # ~/.kestrel/* constants
│       └── Settings/
│           ├── SettingsWindow.swift
│           ├── SettingsView.swift         # the shell: sidebar, page heading, footer
│           ├── SettingsSection.swift      # the eight pages, their names and symbols
│           ├── SettingsPanes.swift        # brain, shortcuts, seeing, typing
│           ├── SettingsPanes+Voice.swift  # voice, hearing, memory, advanced
│           ├── SettingsAbout.swift        # the mark, the version, the notice
│           ├── SettingsControls.swift     # a setting and its explanation, in one row
│           ├── KestrelGlass.swift        # the menu's material, for Kestrel's own windows
│           ├── BrandMark.swift           # the logo, the version, the notice
│           ├── ModelPicker.swift          # choose a model, never type one
│           ├── OnboardingWindow.swift
│           ├── OnboardingView.swift       # the shell: rail, step, footer
│           ├── OnboardingSteps.swift      # the five steps themselves
│           ├── OnboardingRow.swift
│           ├── OnboardingModel.swift
│           ├── OnboardingMotion.swift     # the window's springs, and Reduce Motion
│           ├── OnboardingInterview.swift  # the four questions that seed KESTREL.md
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
- Defaults: `⌃⌥` held = ask, `⌃⌘K` = dictation (toggle). The two must not share modifiers: with dictation on `⌃⌥D` the one gesture fired both, the chord starting a question that the letter then aborted. The letter is K, not D, because macOS reserves `⌃⌘Space`, `⌃⌘D`, `⌃⌘F` and `⌃⌘Q` — `⌃⌘D` is Look Up. Configurable via `config.json` (key code + modifiers). Settings UI in M3.
- Edge cases: re-register on config change; ignore auto-repeat; Caps Lock must not break modifiers; if registration fails (conflict), surface a panel error naming the conflicting combo.
- `HotkeyPressFilter` decides what counts. Auto-repeat is suppressed by time (0.3 s), never by a remembered "still down" flag: Carbon drops the release when the modifiers are let up first, and a flag left stuck down swallows every press after it — which is exactly how dictation used to turn on and refuse to turn off. A release is still paired against a press, so push-to-talk cannot be ended by one it never saw start.

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
- Requirements: cancellable (kill the subprocess), timeouts (ask 75 s, cleanup 20 s — a question still unanswered past that has gone wrong, and a dead island for two minutes is worse than being asked to try again), never throws on non-zero exit without saying what the CLI printed.
- What a failed run says is judged on everything it printed — stderr *and* stdout — because a run that dies on the plan's usage limit exits non-zero with an empty stderr and buries the reason in stream-json. That widening applies to failures only: on a successful run the answer and its token counts are not diagnostics, and reading them as such is what once ended good answers in "usage limit reached".
- Nothing raw reaches the panel. `BackendSupport.readableFailure` keeps the human fields of each JSON object and drops the machinery, so a failure reads as a sentence rather than as `{"type":"system","subtype":"hook_started"…`. A quota refusal carries the reset time the CLI names (`usage limit reached|<epoch>`), because the user's next move depends on whether the wait is twenty minutes or two days.

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
- `spaced:` puts a space in front of the payload. Live dictation types a phrase at a time and something has to keep the words apart, which cannot be a leading space in the text itself — `sanitize` trims that off.
- Fallback: per-character CGEvent typing when paste is rejected or when config `injectMode = type`.
- Safety: collapse newlines when the frontmost app is a terminal (Terminal, iTerm2, Warp, Ghostty bundle ids) so dictated text can never execute as commands.
- Requires Accessibility permission; prompt once and explain why.

### 8.11 PanelWindow / PanelView
- Non-activating borderless `NSPanel`, hung from the top edge of the display the mouse is on, not
  floating below it: pure black, notch-shaped, so it reads as the camera housing grown wider.
- The collapsed bar is a few points taller than the housing (`NotchMetrics.housingOvershoot`), and
  nothing is drawn over it — no rim, no material — because any edge or lighter value puts a visible
  seam around the notch. It opens downward only when there is something to read.
- Width is `notch + 260`, floored at 300 collapsed and 420 opened for a display with no housing.
  The floor is the longest state label: each shoulder is half of what the housing leaves, less the
  inset and the indicator, which on a 179-point notch is 76 points against the 73.8 that
  "Transcribing" measures at `.system(12, .semibold)`. Opened, that leaves 379 points of text —
  about 55 characters a line. Checked by `testEveryStateLabelFitsTheShoulderItIsGiven`, because the
  arithmetic in a comment is what let an earlier, narrower island ship "Transcribin…".
- Shows: state dot + label, backend badge, transcript (secondary), answer, draft card, hotkey hint.
  Everything is laid out at its full height; nothing scrolls, per §8.17. An answer stops at 14 lines
  and a draft body at 16, and both say how many lines did not fit — a clipped last line otherwise
  reads as the last line. The clipboard is never clipped.
- Auto-hide timers: 20 s after answer, 3 s after dictation, 8 s after error, 3 s after "Didn't
  catch that" — nothing was heard, so there is nothing to read. Hover pauses the timer for up to
  `PanelWindow.maximumHold`, and the session state is cleared on the same clock as the window, not
  left in `.error` behind it.
- Esc dismisses whatever is on screen — panel, marks, speech — from wherever the user is, for as
  long as anything is showing. The tap is torn down the moment nothing is.
- Arrives by unrolling out of the top edge and leaves by rolling back up into it, on the same
  curve reversed — a shape that grows out of the notch has to go back the way it came.
- The window frame follows the island on a spring (`PanelFrameAnimator`, on the same response and
  damping as `PanelView`), not on a fixed curve. A streaming answer resizes the window every
  sentence, and a fixed-duration animation restarted mid-flight jumps; a spring is retargeted from
  where the window actually is, keeping its velocity.
- Must be excluded from screenshots (see 8.3).

### 8.11a Setup window
- Five steps, one purpose each: welcome, voice, permissions, profile, ready. A rail across the top
  says which. One window size for all of them — a window that resized between steps would turn a
  step change into two movements.
- The voice download comes *before* the permissions on purpose: it is long, it keeps running in the
  background, and by the time the last switch is flipped it has usually finished on its own.
- Only the three macOS grants appear on the permissions step. Tools — the CLIs, the speech engine —
  are somebody else's installer, and anything still missing is listed on the ready step.
- Both this window and Settings are backed by `NSVisualEffectView` with the `.menu` material: the
  same glass as the menu bar dropdown, not an imitation of it, so it tracks dark mode and Reduce
  Transparency for free. Windows need `applyGlassChrome()` or the strip behind the titlebar keeps
  the window's own background.
- The island is the exception and stays pure black (§8.11). It has to match the camera housing;
  anything translucent there puts a seam around the notch.
- A step's content is centred in the room left between the rail and the footer, and scrolls only
  once it needs more than that.
- `KestrelPalette` is the single source of colour. Views name a role — `accent`, `primaryFill`,
  `success`, `danger`, `surface`, `track` — never a hue; the brand values under them are measured
  off the shipped artwork. Two nearly-identical greens in adjacent windows is what naming by role
  prevents.
- Every role that must survive both themes is a *dynamic* colour, built with
  `NSColor(name:dynamicProvider:)` and resolved against whatever appearance it is drawn into. This
  is not a nicety: aqua on light glass is 1.09:1 and navy on dark glass is 1.18:1, so one fixed
  accent is invisible in one theme whichever of the two is picked. It also means `.tint()`, which
  has no `ColorScheme` to hand, gets the right colour without one being plumbed to it.
- The island is the exception again. Its fill never follows the system theme, so nothing drawn on it
  may either: `accentOnDark`, `dangerOnDark` and the `onHousing*` ladder are fixed values.
- Both windows carry `BrandFooter`: the mark, the version from `CFBundleShortVersionString`, and
  the notice. `build.sh` copies `assets/KestrelMark.png` in as `Logo.png` — the artwork with its
  alpha, not the plated icon, which `make icon` extracts alongside the icon masters. The welcome
  step uses the app icon itself, because most of the bare mark is a navy that disappears on dark
  glass at that size.

### 8.11b Settings window
- A sidebar of nine short pages — Brain, Shortcuts, Seeing, Typing, My voice, Hearing you, Memory,
  Advanced, About — and a page on the right. Three tabs meant every page was a scroll, and a scroll
  is where a setting goes to be lost; a named page each makes the window its own index.
- The two columns are an `HStack`, not a `NavigationSplitView`. The split view brings its own
  sidebar material, which sits opaque in front of the glass, and its own selection highlight, which
  is the Mac's accent colour and not Kestrel's. Neither can be turned off from SwiftUI.
- A setting and the sentence explaining it are one `Form` row, not two: `Setting`, `ToggleSetting`
  and `SettingNote` in `SettingsControls.swift`. A separate row per explanation cost a separator and
  two lots of padding each, which is what made eight controls overflow a 596-point window.
- `SettingsPane.controlWidth` is the one width for every control in the right-hand column, so the
  pages line up with each other.
- The three macOS grants are pinned at the foot of the sidebar as `PermissionStrip`. They are not
  settings — they cannot be flipped from here — but a revoked one is what a window of switches
  otherwise hides. Pressing it opens the setup window, which the delegate hands in as `onOpenSetup`.
- The window has `titleVisibility = .hidden`: the page heading already says where you are, and
  `fullSizeContentView` would otherwise draw the titlebar string on top of it.
- Reset puts the config back to `Config.defaults` behind a confirmation, and deliberately leaves the
  memory file and the downloaded voice alone — neither is a setting.
- About is the one page with no heading above it (the mark and the name are the heading) and no
  `Form` — it carries the icon, version, licence and copyright, and the two actions that are not
  settings: opening setup, and the dependency report.

### 8.12 StatusMenu
- Quit is the only coloured item — `KestrelPalette.dangerColor`, as an attributed title with a
  matching tinted glyph, since an item cannot be both a template and a colour.
- Menu bar item using the monochrome template icon. Items: backend picker (radio), Speak answers
  (toggle), Clean up dictation (toggle), Open what I remember, Open per-app notes, Setup &
  permissions, Check what's installed, Settings, Quit.
- Every row carries a template SF Symbol, the backend rows included: an item without an image
  indents its title differently, so a menu with icons on only some rows starts its titles in two
  different columns.
- "Open per-app notes" opens `~/.kestrel/skills/` (§16). The folder is still called `skills` on
  disk; the menu says what is in it.

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
| `dictationSilenceSeconds` | float | 2.5 | how long a pause ends a live take; `0` means only the hotkey does. Clamped to 1–30 |
| `injectMode` | `"paste" \| "type"` | `"paste"` | |
| `hotkeys.ask` / `hotkeys.dictate` | `{keyCode, modifiers}` | ⌃⌥ held / ⌃⌘K | |
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

The framing is assembled per question by `PromptBuilder.framing(for:)`: the core, plus only the
blocks that question needs. Every token is read before the first word of the answer, so a block that
does not apply is latency spent on nothing.

**ask.txt** — the core, sent always. Kestrel's voice: the friend who knows this stuff, sitting next
to the user and pointing while they talk. Two sentences is the normal length. Answer first, no
preamble, no markdown, no describing where things are — name the thing and mark it. Solve it rather
than describe it. Never talks about itself, its context or its machinery: "I couldn't find a
screenshot" and "I don't have enough information" are banned by name. Carries the `MARK:` contract
of §8.15.

**ask-draft.txt** — appended only when `AskIntent.wantsDraft` matches. The `DRAFT:` contract of
§8.17, a quarter of the old prompt, on the fraction of questions that want it. The matcher is
deliberately generous: a missed draft is worse than the tokens. When it does miss,
`DraftParser.suggestion(forQuestion:in:)` still catches a reply left in quotes.

**ask-browser.txt** — appended only when the content reader came back empty, which is the browser
case: answer from the picture and mark nothing, rather than marking a toolbar button.

**dictation-cleanup.txt** — "Return only the cleaned version of the dictated text: fix punctuation, capitalization, and obvious speech-to-text errors; keep the speaker's words, tone, and language; no em dashes; no additions; no quotes around the output." Reached only for long dictation; §5.3.

Prompt files are read once and cached — three disk reads on the way to every answer is time the
user is waiting.

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
| App icon | `assets/kestrel-logo.svg`: a navy kestrel in flight, its wing drawn as an aqua waveform |
| Menu bar icon | `assets/kestrel-menubar-template.svg`, monochrome template so it adapts to light/dark menu bars |
| Brand | Navy `#021D3D` (the bird) · Aqua `#02F8E6` (the waveform). The only two colours in the artwork, measured off it by pixel histogram; everything else in `KestrelPalette` is derived from them |
| Derived | Teal `#02586F` — the tone the artwork already makes where the waveform crosses the body, and what the aqua has to become to sit on white (7.99:1 there, against the aqua's 1.09:1) · Sky `#67AAF2`, the same family lifted for the island's black |
| Accent | Aqua on dark, teal on light. Dynamic, so `.tint()` and every icon, rail and meter resolve it themselves |
| Primary action | Navy fill with a white label on light (16.9:1); aqua fill with a navy label on dark (12.5:1). Each brand colour on the ground it works on — `primaryFill` / `onPrimaryFill` |
| Semantic | Success `#0E8A63` light / `#34CA98` dark · Warning `#A86A08` / `#F2AD40` · Danger `#B33F1C` / `#E86E43` |
| Panel states | idle gray · listening aqua · transcribing/thinking/answering sky · error `#E86E43`. Fixed, not dynamic: the island is pure black whatever the system theme is |
| Typography | SF Pro (system). Panel: 13 pt body, 11 pt secondary. Never below 10 pt |
| Voice | Concise, friendly, no filler. Answers sound like a colleague looking over your shoulder |
