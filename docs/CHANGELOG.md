# Changelog

All notable changes to Kestrel. Milestones follow `docs/SPEC.md` §11.

## [Unreleased]

### Documentation

- **`docs/INTERACTIONS.md`** — the complete reference for acting on the system: the five action
  kinds, the Accessibility scan and its bounds, the act-vs-explain decision, the JSON contract with
  the model, the policy decision order, the actuator's mechanics and fallbacks, the overlay and Esc,
  the audit log format, task folders, and an explicit list of what Kestrel deliberately cannot do.
- **`docs/VS-HEYCLICKY.md`** — feature-by-feature comparison against the installed HeyClicky build,
  tool by tool, with the remaining gaps ranked by what they cost to close.
- Markdown moved out of the repository root into `docs/`: `KESTREL_SPEC.md` → `docs/SPEC.md`,
  `CHANGELOG.md` → `docs/CHANGELOG.md`, joined by `docs/README.md` as an index. Only `README.md` and
  `CLAUDE.md` stay at the root, both because tooling reads them there. `build.sh` reads the version
  from the new path.

### Fixed

- **The panel's top edge.** It was a `.titled` window with the titlebar hidden, and AppKit still
  installs a titlebar view above the content — with a clear window background and a rounded card
  inside, that showed as a broken strip across the top. It is now genuinely borderless, with a
  `canBecomeKey` override so the answer text stays selectable and the permission button clickable.
- The card's SwiftUI shadow was clipped by the window bounds; the window's own shadow does it
  properly instead.
- `KESTREL_PREVIEW_PANEL` photographs the real panel on the real desktop, which is how both of
  those were found — and how a 1×0-point panel was caught before it shipped.

### Interface pass

- **The waveform is now the user's actual voice.** `AudioCapture` meters the input and the panel's
  bars follow it, on a decibel scale with a fast attack and slow release — the shape that reads as
  speech rather than as noise. Previously it was a canned two-frame animation.
- The header indicator changes shape with the session rather than only colour: bars while
  listening, an orbiting sweep while working, a dot with one expanding ring when an answer lands.
- The panel falls a few points into place when it appears and fades when it leaves, instead of
  blinking. Streamed sentences crossfade in rather than replacing the block.
- A wash of the state colour behind the material, so the panel reads before a word of it does. Error
  text wraps instead of truncating — it names the command that fixes the problem.
- **The menu bar icon breathes** while Kestrel is listening or working, quickly for recording and
  slowly for thinking, so state is visible even behind a full-screen window.
- The agent's pointer and ring keep their identity between steps, so moving to the next control is
  a glide across the screen. Watching it travel is what makes a run legible.
- Circling a region snaps to the box that is actually being sent and holds it for a beat, so the
  user sees what their scribble became.
- Setup rows arrive in sequence rather than all at once.

### T8 — Projects, T9 — connectors per task

- Each agent task gets `~/.kestrel/projects/<slug>/` as its working directory, with the memory file
  symlinked in so nothing is forgotten by running there. Names are slugged from speech and cannot
  resolve outside the projects folder. Menu bar ▸ Open projects folder.
- `mcpForTasks` turns MCP connectors on for agent tasks only. Ordinary questions keep
  `--strict-mcp-config` and the ~11 seconds it saves.
- Claude's flag assembly is now a pure function with tests, rather than something discovered in
  the field when a flag drifts.

### T7 — Agent tasks

- "Archive this", "open Slack", "set the title to Quarterly" are now carried out rather than
  explained. "How do I archive this?" still explains — and when the phrasing is ambiguous Kestrel
  answers, because the wrong answer costs a sentence and the wrong action costs an email.
- The model plans against the real controls it was shown; every step passes the policy, anything
  irreversible is confirmed, and the run stops on the first refusal or failure.
- The overlay names the goal, counts the steps, pauses briefly between them so the run can be
  watched, and Esc stops it from anywhere.

### T5 — Kestrel can act

- New `Actuator` performs press, set-value, focus, scroll and launch through Accessibility.
  `AXUIElementPerformAction` goes straight to the control, so the real cursor never moves and focus
  is not stolen — you can keep typing while it works. Controls with no press action fall back to a
  click posted to the owning process, not to the global event stream.
- `~/.kestrel/policy.json` decides what is permitted. It ships as **confirm by default** with
  terminals denied outright, and anything irreversible — send, delete, buy, post, publish, submit —
  is confirmed even in an app you have allowed.
- `ActionRunner` runs a plan step by step and stops on the first refusal, decline or failure rather
  than leaving a sequence half-applied.
- Every action is appended to `~/.kestrel/logs/actions.jsonl`, one JSON object per line.

### T4 — Desktop awareness

- "What else is open?" and "switch to Slack" now get a list of open windows and running apps.
- Gathered only for questions that are actually about the desktop; ordinary screen questions send
  nothing extra and stay fast.
- Palettes, tooltips and overlay layers are filtered out, and the window in front is listed first.

### T3 — Sound cues

- Five short tones mark listening, heard, answered, inserted and failed, so Kestrel feels
  responsive before it has said anything.
- Synthesised in code rather than shipped as audio files: nothing to license, no blobs in the repo,
  and each cue's envelope is unit-tested — a fade at both ends is what stops a tone clicking.
- Silent when the Mac is muted or `sounds` is off.

### T2 — Per-app skills

- `~/.kestrel/skills/<bundle-id>.md` is sent with every question asked while that app is frontmost,
  and `default.md` is sent always — the way to teach Kestrel your own vocabulary without editing
  prompts. Seeded with a README explaining the format.
- Re-read the moment a file is saved; capped at 6 000 characters, since every question pays for it.
- Menu bar ▸ Open skills folder.

### T1 — Follow-up turns

- A question asked within 90 seconds, in the same app, continues the last one, so "no, the other
  one" and "what about that?" resolve. `followUpSeconds` sets the window; 0 turns it off.
- Switching app ends the thread: a different app is a different subject.
- At most three earlier turns are carried, and the panel marks a question as a follow-up.

## [0.5.0] - 2026-09-06 — M5 Spatial context, and a serious pass on latency, voice and accuracy

**Latency.** A question took 16.9 s end to end; it now takes about 7 s. Almost all of the
difference was `claude` discovering the user's MCP connectors on every single launch, which
`--strict-mcp-config` skips (measured 16.9 s → 5.2 s on a bare prompt). Config key
`allowMCPServers` turns it back on for the v3 agent work.

- The screenshot is now taken while whisper transcribes, rather than before it.
- Answers stream: `--output-format stream-json --include-partial-messages`, parsed into whole
  sentences and spoken as they arrive, so the reply starts out loud before the model has finished.
- Kestrel says a short "let me take a look" the moment it starts thinking, so the wait is not
  silent. Toggle: `acknowledgeWhileThinking`.

**Voice.** Ranked voice selection that prefers the neural premium and enhanced voices and skips
the robotic compact ones, at a slightly slower rate and marginally lower pitch, with a beat between
sentences. Settings shows each voice's tier and offers to open the download pane when only compact
voices are installed.

**Answers sound human.** The ask prompt was rewritten for speech: two or three sentences,
contractions, no markdown, no preamble. It is also now forbidden to mention the screenshot, its
resolution, or to ask the user to zoom in.

**Screenshots.** Kestrel captures the frontmost window rather than the whole desktop. A 5K display
squeezed into the ~1568 px a vision model receives turns labels to mush, which is what made the
model ask to zoom in; one window spends the same budget on the part that matters. `captureMode`
switches back to the whole screen.

**Transcription.** Every take is normalised before whisper sees it — quiet input was the biggest
cause of misheard words — and silence below the noise floor is dropped rather than transcribed into
an invented sentence. whisper now runs with all but two cores, no cross-segment context and
non-speech tokens suppressed, plus an optional vocabulary hint for names and jargon. A configured
model that has gone missing falls back to the best one installed.

**Walkthroughs point at real controls.** The vision model was consistently a button or two out,
because locating a small control in a resized screenshot is genuinely hard for it. Kestrel now
reads the frontmost app's controls from the Accessibility tree and offers the model a numbered
list to choose from; the ring is drawn on the frame macOS reported, which is exact. Apps with no
usable tree still fall back to the gridded screenshot and its estimated coordinates.

**M5 — spatial context.** Drag while holding the ask key to circle part of the screen. The trail is
drawn as you go, the region is cropped out of the screenshot and sent alongside the full frame.
Global mouse monitors need no permission, so this works out of the box. Toggle: `spatialContext`.

**Interface.** The panel is rebuilt on one spring: the indicator changes shape with the session
rather than only colour — waveform bars while listening, a sweep while thinking — the border
brightens while recording, and streamed sentences fade in as they arrive. The setup window gained a
progress bar and a tick that lands with a bounce.

## [0.4.0] - 2026-09-06 — M4 Walkthroughs

- First-run setup window: every permission and tool in one checklist, each with what it is for and
  a button that requests it. Polls while open, so granting something in System Settings ticks the
  row live; offers the relaunch that Screen Recording needs. Reopens from the menu bar, and comes
  back by itself if something required goes missing later.
- `DependencyCheck` became the single source of truth for "can Kestrel work right now", shared by
  the setup window and the menu bar report, and knows which pieces are optional (Codex,
  Accessibility) and which are not.

- Hotkeys are now `⌃⌘A` (ask) and `⌃⌘K` (dictate): free in the quietest modifier pair macOS has,
  so nothing needs to be turned off, and both are plain Carbon hotkeys needing no permission.
- Modifier-only hotkeys (holding `⌥⌘` on its own) are supported but no longer the default: they
  need an event tap and therefore Accessibility, and they arm on the way into any shortkey starting
  with the same modifiers. `ModifierChordDetector` waits out a dwell and cancels on any key press,
  so they are usable when chosen deliberately in Settings.
- `keyCode` is optional in `config.json`: omit it for a bare chord.

- Ask "how do I …?" and Kestrel draws the answer on screen instead of only speaking it:
  a ring around the control to click, its number, and the instruction.
- The overlay is a click-through, full-screen window above everything on the captured display; the
  app underneath still receives the click. Excluded from screen capture like the panel.
- Advances when a click lands on the current target, watched through one listen-only `CGEventTap`;
  Esc clears; asking or dictating again clears it too.
- Coordinates are mapped from downscaled top-left screenshot pixels to bottom-left screen points,
  including multi-display offsets (`ScreenCapture`).
- Steps whose coordinates are implausible — off-image, zero-sized, or covering the whole screen —
  are dropped; if none survive, or Accessibility is not granted, the steps are read out instead.
- `WalkthroughParser` reads the model's JSON through code fences and surrounding prose, renumbers
  steps, caps them at 15, and gives up cleanly rather than drawing nonsense.
- The screenshot sent for a walkthrough gets a labelled 0-1000 grid drawn around it, in a margin so
  no part of the interface is covered, and the model reports which grid it measured in. Without
  this, coordinates come back in the model's own downscaled frame and land nowhere near the control.
- Targeting is still only as good as the model's eye. The ring is therefore forgiving: clicks
  within a generous margin count, and after two clicks that miss it the overlay offers to advance
  on the next click anywhere. Every step also names its control in words.
- `walkthroughs` config flag, plus toggles in the menu bar and Settings.

## [0.3.0] - 2026-09-06 — M3 Polish

- Settings window: backend, hotkey rebinding, voice picker and rate preview, whisper paths and
  language, inject mode, panel timings, optional API keys.
- Hotkey recorder: click a field, press a combination; bare keys are refused.
- Config hot-reload — hand edits to `~/.kestrel/config.json` apply without relaunching.
- Launch at login via `SMAppService`.
- App icon and monochrome menu bar icon generated from SVG by `scripts/make-icon.sh`.
- `Check dependencies…` in the menu bar, mirroring `scripts/check-deps.sh`.
- README rewritten as a from-scratch setup guide; `Tests/MANUAL.md` checklist added.

## [0.2.0] - 2026-09-06 — M2 Dictate + Codex

- Dictation: toggle hotkey, transcribe, optional model cleanup, paste into the frontmost app.
- Pasteboard is restored after the paste; per-character typing fallback for apps that reject ⌘V.
- Newlines are collapsed when the frontmost app is a terminal, so dictation cannot run a command.
- Codex backend (`codex exec`) selectable from the menu bar, with `--output-last-message` parsing
  and a stdout fallback.
- Optional `autoRoute` heuristic (off by default).

## [0.1.0] - 2026-09-06 — M1 Ask

- Hold the ask hotkey: record, transcribe locally with whisper.cpp, capture the display under the mouse,
  ask Claude, show the answer in a floating panel and speak it.
- Panel is excluded from screen capture, auto-hides, and pauses its timer on hover.
- Claude backend over `claude -p --output-format json`, cancellable, with timeouts.
- Readable errors for every failure, with deep links to the right Privacy pane.

## [0.0.1] - 2026-09-06 — M0 Skeleton

- Swift package, `build.sh` app bundle assembly, ad-hoc codesign, Makefile.
- Menu bar item, `~/.kestrel` bootstrap, config and memory files, dependency checker.
