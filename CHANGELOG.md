# Changelog

All notable changes to Kestrel. Milestones follow `KESTREL_SPEC.md` §11.

## [0.4.0] - 2026-09-06 — M4 Walkthroughs

- Default hotkeys are now `⌃⌘Space` (ask) and `⌃⌘D` (dictate). Both collide with a stock macOS
  shortcut — Emoji & Symbols and Look Up — so the README says how to free them.

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

- Hold ⌃⌘Space: record, transcribe locally with whisper.cpp, capture the display under the mouse,
  ask Claude, show the answer in a floating panel and speak it.
- Panel is excluded from screen capture, auto-hides, and pauses its timer on hover.
- Claude backend over `claude -p --output-format json`, cancellable, with timeouts.
- Readable errors for every failure, with deep links to the right Privacy pane.

## [0.0.1] - 2026-09-06 — M0 Skeleton

- Swift package, `build.sh` app bundle assembly, ad-hoc codesign, Makefile.
- Menu bar item, `~/.kestrel` bootstrap, config and memory files, dependency checker.
