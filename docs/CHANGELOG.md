# Changelog

All notable changes to Kestrel. Milestones follow `docs/SPEC.md` §11.

## [Unreleased]

### Removed

- **Driving apps.** Pressing buttons, filling fields, keystrokes, scrolling, the twelve-step plans
  and the permission policy behind them are gone — `Action`, `ActionRunner`, `ActionPolicy`,
  `ActionLog`, `AgentDetector`, `Actuator`, the agent overlay, `ProjectStore`, `agent.txt`,
  `INTERACTIONS.md` and about 900 lines of tests with them. Every plan went stale the moment
  anything moved, every step needed a confirmation, and the confirmations became something to click
  through rather than read. What made Kestrel worth having was never that it could press Send.
- **Kept**: opening an app. "Open Spotify" opens Spotify — one verb, nothing to undo, no
  confirmation theatre. Anything after that is not done, and Kestrel says so rather than half-doing
  it.

### Added

- **Kestrel reads the screen, not just its buttons.** A new `AXContentReader` walks the front
  window's Accessibility tree for *content* — headings, cards, images, table rows, paragraphs — and
  hands the model a numbered list of them alongside the clickable controls, plus the text of what is
  on screen in reading order and the page or document it belongs to. This is what "how could this
  page look better?" needed: the answer used to have nothing to point at, because a card is not a
  button. Only what is visible is read; anything below the fold is described rather than drawn on.
- **It always points at something.** The marker line is now `MARK:` and covers content as well as
  controls, and when the model names nothing, Kestrel searches the answer for the visible names of
  things on screen and marks the best match itself. An answer that says "tighten the card spacing"
  and highlights nothing has handed the user a puzzle.
- **A section is shaded, not ringed**, with its name attached — a hairline circle around a quarter
  of the screen reads as a bug.
- **Kestrel draws with a pencil.** The pointer glyph is gone. A pencil says plainly that what is
  happening is drawing rather than clicking, which is the whole distinction now.
- **Memory that fills itself in.** Onboarding ends with four questions — name, what you do, what you
  are working on, how you want to be answered — which become `KESTREL.md`. After that, a first-person
  statement in a question ("I'm working on the billing rewrite", "I prefer short answers") is filed
  under its own heading, deduplicated, newest first, capped at fourteen lines. Nothing read off the
  screen is ever stored: what you are looking at is not a fact about you.
- **A new voice.** `ask.txt` is now a person rather than a rule sheet: someone sitting next to you
  who points while they talk, will have an opinion, and is forbidden from describing where anything
  is.
- **Kestrel has a cursor, and it draws with it.** Marks are no longer stroked on by an invisible
  hand: Kestrel's own pointer — cyan, glowing, unmistakably not the system one — travels to the
  control, draws the arrow, then loops the control, and rests there. The user's real pointer is
  never moved, borrowed or hidden. Only one cursor is ever on screen: each stroke hands it to the
  next, and the loop begins on the side the arrow arrived at so the hand never jumps.
- **The island is a proper Dynamic Island.** Pure black, because the camera housing is pure black
  and anything else draws a seam across the middle of it; a top row exactly as tall as the housing,
  so the housing has nothing to stick out of; state to the left of it, the live level or the
  backend to the right, and a gap between them the exact width of the notch. It opens downward when
  there is something to read and closes to a bar when there is not.
- **"Always allow this app."** The confirmation has three answers now instead of two, and saying
  yes once covers the rest of that run in that app. A step that sends, deletes, buys or posts still
  asks every single time, whatever the app is allowed to do.
- **Kestrel points at things.** A plain spoken answer can now circle what it is talking about on the
  real screen. The model ends its reply with a `POINT:` line naming controls from the Accessibility
  list it was given; Kestrel strips that line out of what is spoken, then draws a loop and an arrow
  on each control while the sentence is being said. The ask prompt forbids describing a location at
  all — "in the top-right", "the third icon along" — because pointing is the thing that makes this
  an assistant looking at your screen rather than a chatbot describing a photograph of it.
  Off with `answerAnnotations: false`; Esc takes the marks away.
- **The drawing is drawn.** Rings, boxes and arrows are stroked on with `trim`, in a hand-drawn path
  that is slightly out of round and carries past where it started, so a mark reads as a gesture
  being made rather than a rectangle being pasted. Arrows run from the instruction to the control
  and their heads land last. Reduce Motion gets the finished mark without watching it made.
- **The panel hangs from the notch.** It is flush with the top edge of the display, centred on the
  camera housing with the state on one side of it and the backend on the other, and it opens
  downward only when there is something to read — a Dynamic Island rather than a floating card.
  On a display without a notch the same shape slides out of the top edge.
- `KESTREL_PREVIEW_OVERLAY=walkthrough|annotation` photographs the drawing on a live screen, the
  way `KESTREL_PREVIEW_PANEL` already does for the panel. It caught a real bug on its first run.

- **Kestrel can use the keyboard.** Three new action kinds and a richer `scroll`, closing the action
  surface against HeyClicky's computer-use driver tool for tool:
  - `key` — one keystroke or chord, parsed from `"return"`, `"cmd+s"`, `"cmd+shift+p"`, `"option-left"`.
    Often the shortest path there is: ⌘S is one step where File ▸ Save is two.
  - `typeText` — types **alongside** what is already there, where `setValue` replaces a field
    wholesale. The element is optional; without one it types into whatever has focus.
  - `rightClick` — context menus, through `kAXShowMenuAction` with a pid-posted fallback.
  - `scroll` now understands `"page up"` / `"page down"`, matched on whole words so "stop" is not
    read as "top".
- Every one of them is posted to a single process, so the property that made acting tolerable —
  your cursor stays put, your focus is not stolen — holds for keystrokes too.
- **A chord is judged on what the key does, not on how the step was described.** `return`, `delete`
  and ⌘Q/⌘W/⌘Delete are confirmed even in an app the policy allows: "Press Return" is how a message
  gets sent.
- **The target process is pinned when the plan is made.** A confirmation dialog makes Kestrel
  frontmost, so a keystroke that asked for "the frontmost app" at execution time would have gone to
  the alert that just closed. Answering a confirmation now also puts you back in the app you were in.
- `KESTREL_PROBE_ACTIONS=1` runs the actuator against TextEdit from another app and reports whether
  the text landed and whether the frontmost app changed — the background-delivery property, checked
  rather than asserted.

### Fixed

- **The arrowhead was drawn inside the box it pointed at.** The ring is inset ten points beyond the
  control, but the arrow stopped three points short of the *control*, which put its head well inside
  the ring. Arrows now stand off the drawn edge by more than the head is long.
- **"It opens Spotify but never plays anything."** Three faults, one after another:
  - `launchApp` returned the instant the request was filed — several seconds before a cold-starting
    app has a window, a menu bar or anything in its Accessibility tree. It now waits for the app to
    actually be there.
  - Everything planned after a launch pointed at controls in the app the user *was* in: element
    numbers only mean anything in the scan they came from. A launch now ends the plan, and the
    newly-opened app is scanned fresh and asked what to do next, with what has already happened
    spelled out. `agent.txt` says so too, so the model stops trying to plan through the gap.
  - The control list stopped at menu *titles*, so Playback ▸ Next was never on offer. Acting now
    reads the items inside the menus, on a budget of half the scan so they cannot crowd out the
    window's own controls.
  - `play`, `pause`, `skip`, `shuffle`, `put on` and friends were not in the imperative list at all,
    so "play something on Spotify" was answered rather than done.
- **Every step asked for permission separately.** A four-step task in one app was four identical
  alerts, which is how a confirmation stops being read. The policy now says *why* it wants to ask,
  and the two reasons are treated differently: "this app is not vouched for" is a question the user
  answers once, "this step sends something" is asked every time.
- **The island grew upward off the screen.** AppKit measures a window from its bottom-left corner,
  so letting it size itself around growing content pushed the top edge past the top of the display.
  The window now follows the island's own measured size, pinned to the screen edge and animated.
  The answer text also sat in a `ScrollView`, which takes whatever height it is offered — here, the
  height that measurement was still deciding. It lays out at full height instead.
- **A walkthrough no longer dies at its first click.** Three things were wrong at once:
  - Steps whose control could not be located were thrown away, so "File ▸ Export" collapsed to a
    single step — the menu item does not exist in the Accessibility tree until the menu is open —
    and clicking File therefore *completed* the walkthrough. Steps are now kept, planned by name,
    and looked up again in a fresh scan at the moment the user reaches them, retried a few times
    because menus open with an animation. A step that still cannot be found is described instead of
    drawn, and any click advances it.
  - The overlay window covered only what was photographed, which is usually the front window. The
    first step of a route is very often in the menu bar — outside it — so exactly the mark that
    mattered most was clipped. It now spans every display.
  - `needs_more` ended the run silently. Kestrel now photographs the new screen and asks for the
    rest of the route, up to three times.
- **The ring could be animated off the screen and never come back.** The overlay's window frame was
  set after its view was built, so the first layout put every mark far off screen; the correction
  then arrived on the same render pass as the breathing pulse, whose `repeatForever(autoreverses:)`
  animation dutifully carried the ring back and forth between the wrong place and the right one.
  Geometry is now known before the view exists, and the pulse owns nothing but its own scale.
- **"Claude usage limit reached" after a perfectly good answer.** The quota check read the whole of
  stdout, which for `--output-format json` is an envelope of durations, token counts, a cost and two
  hex ids — and the needle list contained a bare `"429"`. Any request whose `duration_ms`,
  `cache_read_input_tokens`, `total_cost_usd`, `session_id` or `uuid` happened to contain those three
  digits was reported as a quota failure, seconds after the answer had been spoken. An answer that
  merely discussed usage limits did it too.
  A quota error is now read only out of text a CLI emitted as a failure — stderr from a non-zero
  exit, or an error envelope's message — and never out of the answer. The needles are phrases, and
  a bare 429 must carry HTTP framing. Same fix in the Codex backend.

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
