# Kestrel — instructions for Claude Code

Kestrel is a native macOS (14+, Apple Silicon) voice-first, screen-aware assistant that runs on the
owner's Claude Pro/Max and ChatGPT Plus/Pro subscriptions by shelling out to `claude -p` and
`codex exec`. Single user. Local speech-to-text. No backend, no telemetry.

## First thing to do
Read `docs/SPEC.md` end to end before writing any code. It defines scope, architecture, folder
layout and module contracts. Follow it; propose changes in conversation rather than silently
deviating — and when a change lands, update the spec in the same commit. A spec that describes
code that no longer exists is worse than no spec.

## How we work
- One change at a time. Stop after each and report the build output and a manual test summary.
- Every change ends with `make test` green, the README and `docs/SPEC.md` corrected where they
  now describe something untrue, a `docs/CHANGELOG.md` entry, and a commit.
- The changelog records the shipped product, not the road to it. If something is built and later
  taken out, take its entry out too — nobody reading it needs to know it existed.
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
- `make build` → `swift build -c release` + assemble `Kestrel.app`
- `make run` → build and `open Kestrel.app`
- `make test` → `swift test`
- `make icon` → regenerate `AppIcon.icns` from `assets/kestrel-logo.svg`
- `scripts/check-deps.sh` → verify `claude`, `codex`, `whisper-cli`, model file
- `scripts/make-signing-cert.sh` → run once; without it every rebuild silently revokes the
  Accessibility and Screen Recording grants, because an ad-hoc signature changes with the binary

## Agent skills
`skills-lock.json` records the skills this project expects, by source repo and SHA-256 of each
`SKILL.md`. The skill bodies are not committed — `.claude/` is ignored — so a fresh clone has the
manifest but no skills, and each has to be installed once:

```
/plugin marketplace add DietrichGebert/ponytail
/plugin install ponytail@ponytail
```

`/ponytail` enforces the laziest working solution, `/ponytail-audit` scans the tree for
over-engineering, `/ponytail-review` does the same for a diff. The other three collections in the
lock file (`swiftui-expert-skill`, `ui-ux-pro-max`, `apple-design`) install the same way from the
sources named there.

Note the name collision: "skills" in `README.md` and spec §16 means Kestrel's own per-app notes in
`~/.kestrel/skills/`, which have nothing to do with these.

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
