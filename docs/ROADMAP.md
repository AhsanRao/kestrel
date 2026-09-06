# Kestrel roadmap — closing the gap with HeyClicky

Derived from reading the installed HeyClicky app on 2026-09-06: its `cua-driver` helper, its
`cua-driver-policy.yaml`, its bundled skills, and its live `CodexHome/config.toml`.

**What we are not copying.** HeyClicky proxies to its own backend (`api.heyclicky.com`, model
`gpt-5.6-luna`, API-key auth), bundles its own Codex runtime, ships Sentry and PostHog telemetry,
and weighs 598 MB. Kestrel runs on the user's own subscriptions, has no backend and no telemetry,
and weighs about 1.4 MB. That difference is the point of the project (spec §2), so only the product
surface is a target — never the plumbing.

Status: `[ ]` not started · `[~]` in progress · `[x]` done

---

## T1 — Follow-up turns

Every hotkey press is currently a fresh `claude -p --no-session-persistence`, so the user cannot say
"no, the *other* one". Keep the last exchange for a short window and continue it.

- [x] Carry the previous question and answer into the next prompt while a conversation is warm
- [x] Expire after `conversationWindowSeconds` (default 90) or when the frontmost app changes
- [x] A follow-up reuses the previous screenshot unless the screen has changed
- [x] Panel shows that a question is a follow-up
- [x] Tests: window expiry, app-change invalidation, prompt assembly, transcript threading

## T2 — Per-app skills

Spec §16 designs `~/.kestrel/skills/*.md` injected by frontmost bundle id; it was never built.
HeyClicky ships 28 of these (`imessage.md`, `linear.md`, `notion.md`, `obsidian.md`, `spotify.md`,
`github-pr-workflow.md`, …).

- [x] Load `~/.kestrel/skills/<bundle-id>.md`, plus a `default.md`, for the frontmost app
- [x] Seed a starter set on first run and document the format
- [x] Cache with invalidation on file change; never block the ask path on disk
- [x] Tests: resolution order, missing files, oversized files, bundle-id matching

## T3 — Sound design

HeyClicky cues every state change (`agent-launch.m4a`, `agent-done.m4a`, `clicky-text-send.wav`).
Kestrel is silent apart from speech, which makes it feel unresponsive.

- [x] Short cues for: listening started, transcribed, answer ready, dictation inserted, error
- [x] Synthesised at build time — no third-party assets, no binary blobs in the repo
- [x] Respect system mute and a `sounds` config flag
- [x] Tests: cue selection per state, muted behaviour, missing-file tolerance

## T4 — Desktop awareness

`list_apps`, `list_windows`, `get_window_state`, `get_desktop_state` in HeyClicky. Kestrel only has
a screenshot, so it cannot answer "what else is open" or act on another app.

- [x] Enumerate running apps and on-screen windows with titles, frames and bundle ids
- [x] Offer that context to the model on request, not on every question (tokens, latency)
- [x] Tests: window filtering, ordering, off-screen and layered windows

## T5 — Actuator: let Kestrel act

The core gap. HeyClicky's policy constrains every input tool to `delivery_mode: background` — it
clicks without stealing the cursor or focus. `AXUIElementPerformAction` is background by
construction, and M4's `AXElementScanner` already knows where every control is.

- [x] `Actuator`: press, set value, focus, scroll and menu-item invocation through Accessibility
- [x] `CGEventPostToPid` fallback for apps with no usable Accessibility tree
- [x] Policy in `~/.kestrel/policy.json`: allowlist by app and action, deny by default
- [x] Confirmation required before anything that sends, deletes, buys, posts or overwrites
- [x] Every action logged to `~/.kestrel/logs/actions.jsonl`
- [x] Tests: policy evaluation, destructive-verb detection, confirmation gating, dry runs

## T6 — Agent cursor and action log

HeyClicky draws a fake cursor so automation is legible. Kestrel already has an overlay window.

- [x] Visible marker showing what Kestrel is about to touch, with the action named
- [x] Esc aborts the run; the panel lists what was done
- [x] Tests: step sequencing, abort behaviour, completion state

## T7 — Agent tasks (spec M6)

- [x] Multi-step plans: model proposes actions, Kestrel executes them under policy
- [x] HUD with live status, cancel and retry
- [x] Tests: plan parsing, step failure handling, cancellation

## T8 — Projects and artifacts

HeyClicky writes task output into per-task project folders (it had generated a PDF and an HTML page).

- [x] `~/.kestrel/projects/<slug>/` as the working directory for a task
- [x] Panel offers to reveal what was produced
- [x] Tests: slugging, collision handling, path containment

## T9 — MCP connectors

`--strict-mcp-config` currently saves ~10 s per question by skipping connector discovery. Agent
tasks are the one case where connectors are worth that cost.

- [x] Opt in per task rather than globally, so plain questions stay fast
- [x] Tests: flag assembly for both paths

## Not doing

- **Sparkle auto-update** — a third-party dependency, and CLAUDE.md forbids adding one without
  asking. Revisit if the owner wants it.
- **Telemetry** — HeyClicky ships Sentry and PostHog. Kestrel never will (spec §2).
- **A hosted model backend** — the reason Kestrel exists is to avoid one.
