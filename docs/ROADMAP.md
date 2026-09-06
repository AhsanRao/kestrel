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

## T1 — Follow-up turns ✅

Every hotkey press is currently a fresh `claude -p --no-session-persistence`, so the user cannot say
"no, the *other* one". Keep the last exchange for a short window and continue it.

- [x] Carry the previous question and answer into the next prompt while a conversation is warm
- [x] Expire after `followUpSeconds` (default 90) or when the frontmost app changes
- [x] ~~A follow-up reuses the previous screenshot unless the screen has changed~~ — dropped.
      There is no cheap, reliable "has the screen changed" test, and the capture now runs in
      parallel with transcription, so a fresh one costs almost nothing and can never be stale.
- [x] Panel shows that a question is a follow-up
- [x] Tests: window expiry, app-change invalidation, prompt assembly, retention limit

## T2 — Per-app skills ✅

Spec §16 designs `~/.kestrel/skills/*.md` injected by frontmost bundle id; it was never built.
HeyClicky ships 28 of these (`imessage.md`, `linear.md`, `notion.md`, `obsidian.md`, `spotify.md`,
`github-pr-workflow.md`, …).

- [x] Load `~/.kestrel/skills/<bundle-id>.md`, plus a `default.md`, for the frontmost app
- [x] Seed `README.md` and `default.md` on first run, explaining the format and how to find a
      bundle id
- [x] Cache keyed on modification date, so a saved edit applies at once and an unchanged file is
      never re-read
- [x] 6 000-character cap per send, because every question pays for this
- [x] Menu bar ▸ Open skills folder
- [x] Tests: combination order, missing files, comment-only files, truncation, cache invalidation

## T3 — Sound design ✅

HeyClicky cues every state change (`agent-launch.m4a`, `agent-done.m4a`, `clicky-text-send.wav`).
Kestrel is silent apart from speech, which makes it feel unresponsive.

- [x] Five cues: listening, heard, answered, inserted, failed
- [x] Synthesised in code — no audio files in the repo, nothing to license, and the shape of each
      cue is testable
- [x] Respect system mute and the `sounds` flag; toggle in Settings ▸ Speech
- [x] Tests: length, level, fade envelopes, rising vs falling, distinctness, mute and flag

## T4 — Desktop awareness ✅

`list_apps`, `list_windows`, `get_window_state`, `get_desktop_state` in HeyClicky. Kestrel only has
a screenshot, so it cannot answer "what else is open" or act on another app.

- [x] Enumerate running apps and on-screen windows with titles, frames and bundle ids
- [x] Gathered only when the question is about the desktop — "what else is open", "switch to…" —
      so ordinary screen questions pay nothing for it
- [x] Palettes, tooltips and non-zero window layers filtered out; frontmost first, then biggest
- [x] Tests: layer and size filtering, ordering, capping, missing titles, malformed entries,
      detector phrasing

## T5 — Actuator: let Kestrel act ✅

The core gap. HeyClicky's policy constrains every input tool to `delivery_mode: background` — it
clicks without stealing the cursor or focus. `AXUIElementPerformAction` is background by
construction, and M4's `AXElementScanner` already knows where every control is.

- [x] `Actuator`: press, set value, focus, scroll and launch, through Accessibility — the real
      cursor never moves and focus is not stolen, which is what makes acting tolerable to sit next to
- [x] `postToPid` fallback for controls that expose no press action, still delivered to the owning
      process rather than the global event stream
- [x] Policy in `~/.kestrel/policy.json`, `confirm` by default and **terminals denied outright**,
      because typing into one is arbitrary command execution
- [x] Anything reading as irreversible is confirmed even in an allowed app, matched on whole words
      and their inflections so "Deleting the row" counts and "the sender column" does not
- [x] `ActionRunner` stops on a refusal, a decline or a failure rather than half-applying a plan
- [x] Every action appended to `~/.kestrel/logs/actions.jsonl`
- [x] Tests: policy decisions, verb inflections, partial and malformed policy files, confirmation
      gating, abort paths, plan capping

## T6 — Agent cursor and action log ✅

HeyClicky draws a fake cursor so automation is legible. Kestrel already has an overlay window.

- [x] A ring on the control being touched, an agent pointer dot, the action in words, and a step
      counter — automation that happens invisibly is the same as automation you cannot trust
- [x] `EscapeWatcher`: Esc stops a run from wherever the user is, through a listen-only tap that
      never swallows the key
- [x] Tests: step counting and clamping, coordinate flipping, second-display offsets, targetless
      actions, reset

## T7 — Agent tasks (spec M6)

- [ ] Multi-step plans: model proposes actions, Kestrel executes them under policy
- [ ] HUD with live status, cancel and retry
- [ ] Tests: plan parsing, step failure handling, cancellation

## T8 — Projects and artifacts

HeyClicky writes task output into per-task project folders (it had generated a PDF and an HTML page).

- [ ] `~/.kestrel/projects/<slug>/` as the working directory for a task
- [ ] Panel offers to reveal what was produced
- [ ] Tests: slugging, collision handling, path containment

## T9 — MCP connectors

`--strict-mcp-config` currently saves ~10 s per question by skipping connector discovery. Agent
tasks are the one case where connectors are worth that cost.

- [ ] Opt in per task rather than globally, so plain questions stay fast
- [ ] Tests: flag assembly for both paths

## Not doing

- **Sparkle auto-update** — a third-party dependency, and CLAUDE.md forbids adding one without
  asking. Revisit if the owner wants it.
- **Telemetry** — HeyClicky ships Sentry and PostHog. Kestrel never will (spec §2).
- **A hosted model backend** — the reason Kestrel exists is to avoid one.
