# Kestrel — instructions for Claude Code

Kestrel is a native macOS (14+, Apple Silicon) voice-first, screen-aware assistant that runs on the
owner's Claude Pro/Max and ChatGPT Plus/Pro subscriptions by shelling out to `claude -p` and
`codex exec`. Single user. Local speech-to-text. No backend, no telemetry.

## First thing to do
Read `KESTREL_SPEC.md` end to end before writing any code. It defines scope, architecture, folder
layout, module contracts, milestones, and acceptance criteria. Follow it; propose changes in
conversation rather than silently deviating.

## How we work
- Build **one milestone at a time** (M0 → M6, see spec §11). Stop after each and report the build
  output and a manual test summary. Wait for approval before the next milestone.
- Every milestone ends with `make test` green, README updated, a `CHANGELOG.md` entry, and a commit.
- Keep files small (< 200 lines) and in the folders defined in spec §7.
- No third-party Swift packages without asking. Apple frameworks only: AppKit, SwiftUI,
  AVFoundation, Carbon, os.log.
- If a macOS API is uncertain, write the smallest spike, build it, run it, then integrate.

## Hard rules (policy and safety)
- Never read, store, or forward OAuth tokens from `~/.claude`, `~/.codex`, or the Keychain.
- Never call `api.anthropic.com` or `api.openai.com` directly. Only spawn the official CLIs.
  An API key path exists only as an explicit, user-configured override.
- Before writing a CLI invocation, run `claude --help` and `codex exec --help` and record the exact
  flags used in a comment above the call. Flags drift between releases.
- No always-on capture of any kind. Screenshots and audio happen only on a hotkey press.
- Dictated text going to a terminal app must have newlines collapsed (spec §8.10).

## Commands
- `make build` → `swift build -c release` + assemble `Kestrel.app` (ad-hoc signed)
- `make run` → build and `open Kestrel.app`
- `make test` → `swift test`
- `make icon` → regenerate `AppIcon.icns` from `assets/kestrel-logo.svg`
- `scripts/check-deps.sh` → verify `claude`, `codex`, `whisper-cli`, model file

## Environment notes
- Homebrew is at `/opt/homebrew`; add it and `~/.local/bin` to PATH inside spawned processes.
- User data lives in `~/.kestrel/` (config, memory, models, logs). Never write elsewhere.
- Both CLIs are spawned with cwd `~/.kestrel` so they auto-load `CLAUDE.md` / `AGENTS.md`
  (both symlinks to `KESTREL.md`).

## Style
- Swift 5.9, `final class` for services, `struct` for models, protocols for swappable parts
  (`Backend`, `Transcriber`).
- All UI work on the main thread; all subprocess and audio work on a serial background queue.
- Errors are user-readable and actionable ("whisper-cli not found — run: brew install whisper-cpp").
- Log with `os.Logger(subsystem: "dev.0xash.kestrel", category: <module>)`.
