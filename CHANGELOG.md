# Changelog

All notable changes to Kestrel. Milestones follow `KESTREL_SPEC.md` §11.

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

- Hold ⌃⌥Space: record, transcribe locally with whisper.cpp, capture the display under the mouse,
  ask Claude, show the answer in a floating panel and speak it.
- Panel is excluded from screen capture, auto-hides, and pauses its timer on hover.
- Claude backend over `claude -p --output-format json`, cancellable, with timeouts.
- Readable errors for every failure, with deep links to the right Privacy pane.

## [0.0.1] - 2026-09-06 — M0 Skeleton

- Swift package, `build.sh` app bundle assembly, ad-hoc codesign, Makefile.
- Menu bar item, `~/.kestrel` bootstrap, config and memory files, dependency checker.
