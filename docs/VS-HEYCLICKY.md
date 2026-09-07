# Kestrel vs HeyClicky — what we have, what we don't

Read from the installed copy at `/Applications/HeyClicky.app` (build of 2026-08-25): its
`ClickyModelInstructions.md`, the `cua-driver` skill that defines its computer-use tool surface, its
16 bundled skills, its 28 per-app skill files, and its binary's own strings. Updated 2026-09-06.

**The two apps are not the same shape.** HeyClicky is 598 MB: it bundles its own Codex runtime,
proxies to its own backend (`api.heyclicky.com`), authenticates through Supabase, charges a
subscription, and ships Sentry + PostHog telemetry. Kestrel is ~1.4 MB, runs on your own Claude and
ChatGPT logins, and has no backend to phone. That difference is the point of the project (spec §2),
so **only the product surface is a target — never the plumbing.**

Legend: ✅ have · 🟡 partial · ❌ missing · 🚫 deliberately not doing

---

## 1. Acting on the system

The closest comparison, and the one that matters most. HeyClicky exposes a local `computer-use` MCP
server (Cua Driver) with these tools; Kestrel has five action kinds.

| HeyClicky tool | Kestrel | Notes |
|---|---|---|
| `click` (by `element_token`) | ✅ `press` | Same idea, same background delivery |
| `set_value` | ✅ `setValue` | Ours **replaces** the field; theirs too |
| `scroll` | ✅ `scroll` | 6 lines, or 30 for a page |
| `launch_app` | ✅ `launchApp` | Theirs also takes `urls:` to open a link in a background window |
| `get_window_state` | ✅ `AXElementScanner` | AX snapshot + screenshot; ours is the numbered control list |
| `list_windows` / `get_app_state` | ✅ `DesktopSurvey` | Ours is gathered only when the question needs it |
| `check_permissions` | ✅ onboarding window | Ours re-checks live while open |
| Agent cursor overlay | ✅ `AgentOverlay` | Ours names the step and counts `n of m` |
| `right_click` | ✅ `rightClick` | `kAXShowMenuAction`, with a pid-posted right button pair as fallback |
| `type_text` | ✅ `typeText` | Types alongside existing text; element optional |
| `press_key` | ✅ `key` | `"return"`, `"tab"`, `"escape"`, arrows, F-keys |
| `hotkey` | ✅ `key` | Same kind: `"cmd+s"`, `"cmd+shift+p"` |
| `page` | ✅ `scroll` | `"page up"` / `"page down"` — 30 lines rather than 6 |
| `activate` / window focus by id | 🟡 `focus`, `launchApp` | `launchApp` on a running app brings it forward, so this is covered in practice; there is no "focus that window id" |
| Window-scoped pixel click when AX misses | 🟡 | We fall back to a pid-posted click, but only at a known element's frame — never at model-chosen coordinates |
| `move_cursor`, `drag`, `double_click` | ❌ | **Not shipped by HeyClicky either** — parity |
| Trajectory recording / replay / zoom | ❌ | Not shipped by HeyClicky either |

### The deeper difference: one plan vs a loop

HeyClicky's contract is **snapshot → act → re-snapshot → verify**, repeated, with the invariant
stated as "not optional". Kestrel scans once, plans once, then runs the plan. Consequences:

- A dialog that appears mid-run is not adapted to — our step fails and the run stops.
- `needs_more: true` ends the run and asks you to speak again; theirs continues in the same thread.
- We cannot verify an action landed, only that the AX call returned success.

This is the single largest capability gap, and it is architectural rather than a missing tool.

### Where Kestrel is ahead on acting

| | HeyClicky | Kestrel |
|---|---|---|
| Approval default | `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`; "the user's instruction IS the approval" | `fallback: "confirm"` — deny-by-default policy file |
| Irreversible steps | Model is *told* to stop before sends/deletes/purchases | Enforced in code: 41 destructive verbs, whole-word + inflection matched, outranks an `allow` |
| Terminals | No special case | 10 terminal bundle ids denied out of the box |
| Audit | Telemetry to PostHog | `~/.kestrel/logs/actions.jsonl`, local, one JSON object per line |
| Stopping a run | Close the HUD | Esc, seen through a listen-only tap wherever you are |


---

## 2. Voice

| | HeyClicky | Kestrel |
|---|---|---|
| Speech to text | OpenAI **Realtime** API over a WebSocket | ✅ whisper.cpp, **local**, nothing leaves the Mac |
| Streaming / barge-in | ✅ session stays warm, interruptible mid-sentence | 🟡 answer speech streams sentence-by-sentence; hotkey interrupts |
| Always-on mode | ✅ (plus push-to-talk) | 🚫 spec §2 forbids always-on capture |
| Voices | 10 Realtime voices (alloy, ash, ballad, cedar, coral, echo, marin, sage, shimmer, verse) + 13 style presets | 🟡 macOS system voices; premium ones preferred when installed |
| Spoken acknowledgement while thinking | ✅ | ✅ |
| Spoken task-finished summary | ✅ | ✅ |

Realtime voice would mean streaming microphone audio straight to `api.openai.com`, which CLAUDE.md
forbids outright, and would end the "speech never leaves your Mac" property. The realistic ceiling
for us is better local voices and faster whisper — not their architecture. 🚫

---

## 3. Input modes

| Mode | HeyClicky | Kestrel |
|---|---|---|
| Voice | ✅ | ✅ hold `⌃⌥` |
| Dictation into any app | ✅ | ✅ tap `⌃⌘K`, model-cleaned, terminals newline-collapsed |
| Drawing on screen | ✅ | ✅ the answer marks what it names, Esc clears |
| Agents | ✅ | ✅ |
| **Text mode** (type instead of speak) | ✅ | ❌ every request must be spoken |
| Spatial / circle a region | ✅ | ✅ |
| Notch HUD | ✅ | ❌ floating panel near the mouse instead |

Text mode is the cheapest real gap on this list: a text field on the existing panel, feeding the
same `runAsk` path that a transcript feeds. It also makes the app usable in a quiet room.

---

## 4. Knowledge, skills and integrations

| | HeyClicky | Kestrel |
|---|---|---|
| Per-app skills | ✅ 28 shipped (`imessage.md`, `linear.md`, `notion.md`, `obsidian.md`, `spotify.md`, `github-pr-workflow.md`, `airtable.md`, `blender.md`, `maps.md`, `polymarket.md`, …) | ✅ mechanism identical; **we ship none** |
| Workflow skills | ✅ 8 (`clicky-research-report`, `clicky-repo-operator`, `clicky-email-assistant`, `clicky-dev-setup-doctor`, `clicky-build-preview`, `clicky-creative-studio`, `clicky-artifacts`, `clicky-google-workspace`) | ❌ |
| Capability skills | ✅ PDF, DOCX, spreadsheet, frontend-design, obsidian, vercel-deploy | ❌ |
| Account integrations | ✅ Composio MCP: Gmail, Calendar, Drive, Docs, Sheets, Notion, Linear, GitHub, Slack — with a Settings ▸ Integrations UI | 🟡 any MCP server the user has configured in their own CLI, via `mcpForTasks` — no UI, no OAuth flow |
| Persistent memory | ✅ `AGENTS.md` | ✅ `~/.kestrel/KESTREL.md`, symlinked as `CLAUDE.md`/`AGENTS.md` |
| Reads documents beyond the screen | ✅ Desktop/Documents/Downloads entitlements + an OCR skill | ❌ we only ever see a screenshot |

Their integrations run through *their* worker and *their* Composio account. Ours would be the user's
own MCP servers — a Settings pane that lists what the CLI already has connected is the honest
equivalent, and is worth building. The 28 app skills are pure content and could be matched in an
afternoon each.

---

## 5. Sessions, output and shell

| | HeyClicky | Kestrel |
|---|---|---|
| Follow-up turns | ✅ threads | ✅ 90 s window, same-app |
| **History** | ✅ a History tab of past responses | ❌ nothing is kept after the panel hides |
| **Multiple concurrent agent threads** | ✅ background threads, resumable | ❌ one run at a time, foreground only |
| Per-task project folder | ✅ | ✅ `~/.kestrel/projects/<slug>/` |
| Artifact management (open / reveal / rename / export) | ✅ `clicky-artifacts` | 🟡 menu bar ▸ Open projects folder |
| Sound design | ✅ recorded cues | ✅ five synthesised cues |
| Onboarding | ✅ videos + a demo that points at real controls | ✅ permission checklist that re-checks live |
| Auto-update | ✅ Sparkle | 🚫 third-party dependency (CLAUDE.md) — ask first |
| Scheduled / recurring tasks | ❌ strings exist; their own instructions say not shipped | ❌ |
| Telemetry, crash reporting, paywall, auth | ✅ PostHog, Sentry, Supabase, subscription | 🚫 never (spec §2) |

---

## 6. What is worth building next, ranked

Effort is rough: **S** ≈ an evening, **M** ≈ a day, **L** ≈ several.

**Done since this list was written:** `press_key`, `hotkey`, `type_text`, `right_click` and `page`
all shipped as the `key`, `typeText`, `rightClick` and `scroll` kinds. What is left:

| # | Gap | Why it matters | Effort |
|---|---|---|---|
| 1 | **Text mode** | Every request must currently be spoken. A field on the panel reuses the whole existing pipeline. | S |
| 2 | **Snapshot → act → verify loop** | The architectural gap. Re-scan between steps, confirm the effect, continue on `needs_more`. Turns a fixed plan into an agent. | L |
| 3 | **History** | Answers vanish when the panel hides. A searchable list of past exchanges is table stakes and needs no new permissions. | M |
| 4 | **Ship per-app skills** | The mechanism exists and is empty. Five good files (Mail, Safari, Slack, Xcode, Finder) would be felt immediately. | M |
| 5 | **Integrations pane** | Show what MCP servers the user's CLI already has, and let them be enabled per-task. Honest version of Composio. | M |
| 6 | **Window-scoped pixel click fallback** | For apps whose AX tree is thin. Needs care: it reopens the coordinate-accuracy problem AX was chosen to solve. | M |
| 7 | **Background / concurrent runs** | Their multi-thread model. Large, and in tension with "one hotkey, one thing". | L |
| 8 | **Document reading beyond the screen** | Answer about a whole PDF rather than the visible page. New entitlements, new privacy surface. | L |

Not doing, and why: Realtime voice (would send audio to OpenAI directly — forbidden), always-on
listening (spec §2), telemetry, a hosted backend, a paywall, Sparkle without asking first.

---

## 7. Summary

Kestrel matches HeyClicky on **seeing** (AX snapshot, window survey, screenshots, spatial context),
on **showing** (marks drawn while it talks), on **dictation**, on **memory and per-app skills as a
mechanism**, on **project folders**, and on **sound and overlay feedback** — at 0.2% of the download
size and with no backend.

The action vocabulary now matches theirs tool for tool, minus the ones they do not ship either
(drag, double-click, cursor movement). It is still behind on **iterating** (one plan versus
snapshot-act-verify) and on **product surface around the core** (history, text input, shipped
skills, an integrations UI).

It is ahead, deliberately, on **safety** (deny-by-default, enforced destructive-verb confirmation,
terminals denied, local audit log, Esc abort) and on **privacy** (local speech-to-text, no telemetry,
no backend, the user's own subscriptions).
