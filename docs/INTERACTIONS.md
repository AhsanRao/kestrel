# System interaction — what Kestrel can do to your Mac, and how

Kestrel does not only answer questions about the screen. Say *"archive this"*, *"open Slack"*,
*"set the title to Quarterly"* and it plans the steps against the app's **real controls** and carries
them out. This document is the complete reference for that subsystem: what it can do, how it decides,
what stops it, and where the limits are.

Two properties shape every decision below:

1. **Actions are delivered in the background.** They go through Accessibility, straight to the
   control. The real cursor never moves, focus is not stolen, and you can keep typing while Kestrel
   works. (HeyClicky gets this from its driver's `delivery_mode: background` constraint; Kestrel gets
   it by never synthesising a global click in the first place.)
2. **Nothing happens without permission.** The shipped policy is `confirm` — useful, but never
   silent. HeyClicky's driver runs `approval_policy = "never"` with `sandbox_mode =
   "danger-full-access"`. Kestrel takes the opposite default deliberately.

---

## 1. The action vocabulary

Five kinds, defined in [Action.swift](../Sources/Kestrel/Core/Action.swift). The set is deliberately
small: everything here is expressible through Accessibility, which is what makes background delivery
possible.

| Kind | What it does | `element` | `value` |
|---|---|---|---|
| `press` | Clicks a button, menu item, checkbox, radio button, link, row | required | — |
| `setValue` | Types into a field, **replacing** what is there | required | the text |
| `focus` | Raises the control's window and selects it | required | — |
| `scroll` | Scrolls the control by 6 lines | required | `"up"` / `"down"` |
| `launchApp` | Opens an application and activates it | — | bundle id |

Each action also carries `describe` — the sentence you are shown before it happens ("Click Send",
"Type the title into Subject"). That string is not cosmetic: it is what the confirmation dialog
shows, what the overlay names, what the destructive-verb check reads, and what lands in the audit log.

A model returns an **`ActionPlan`**: a `goal`, up to **12** actions, and `needs_more` when it ran out
of controls before finishing.

---

## 2. The pipeline

```
hotkey held → speech → whisper (local) → transcript
                                            │
                            AgentDetector.wantsAction?
                    ┌───────────────────────┼───────────────────────┐
                   no                      yes                   "how do I…"
                    │                       │                       │
                 answer            AXElementScanner            walkthrough
                                     (real controls)          (draws on screen)
                                            │
                                  no controls? → answer instead
                                            │
                              Query(mode: .agent) → claude -p / codex exec
                                            │
                                 ActionPlanParser (strict JSON)
                                            │
                                     ActionRunner
                             ┌──────────────┼──────────────┐
                          policy       confirm dialog     Esc
                             │              │              │
                          Actuator ── Accessibility ── target app
                             │
                    ~/.kestrel/logs/actions.jsonl
```

State machine ([SessionState.swift](../Sources/Kestrel/Core/SessionState.swift)):
`thinking --actionsReady--> acting --actionsFinished--> idle`. Pressing a hotkey while `acting`
pulses the panel and is refused rather than starting a second run.

---

## 3. Deciding: do it, show it, or say it

[AgentDetector.swift](../Sources/Kestrel/Core/AgentDetector.swift). The distinction matters more than
usual, because one branch answers a question and the other touches your Mac. **When it is not clearly
an instruction, Kestrel answers** — the wrong answer costs a sentence, the wrong action costs an email.

**Never an action** (checked first, and they win over any verb that follows):

- Ends with `?`
- Starts with: `how do i`, `how do you`, `how can i`, `how would i`, `how to`, `what is`, `what's`,
  `where is`, `where do i`, `why`, `can you explain`, `show me how`, `what does`

**An action** when the text *is*, or *begins with*, one of these — also after `please `, or after a
comma mid-sentence:

> open · launch · click · press · select · choose · switch · close · quit · type · write · fill ·
> enter · set · rename · create · add · insert · send · reply · forward · archive · delete · remove ·
> move · copy · paste · scroll · search for · go to · turn on · turn off · enable · disable · save ·
> export · print · share · start · stop · run · check · mark

Matched as a leading **phrase**, not a word, so both `open Slack` and `turn on dark mode` count.

So: *"How do I archive this?"* → a drawn walkthrough. *"Archive this"* → an action.

Turn the whole branch off with `agentActions: false` in `~/.kestrel/config.json`.

---

## 4. Seeing: the Accessibility tree

[AXElementScanner.swift](../Sources/Kestrel/Input/AXElementScanner.swift).

Asking a vision model for pixel coordinates was the wrong instrument — it landed a button or two off,
because locating a small control in a resized screenshot is genuinely hard. macOS already knows
exactly where every button is. So the model gets a **numbered list of real controls** and only has to
pick one, and the frame it acts on is exact by construction.

**Roles offered** — things a user can actually click:

`AXButton` · `AXMenuItem` · `AXMenuBarItem` · `AXCheckBox` · `AXRadioButton` · `AXPopUpButton` ·
`AXLink` · `AXTabGroup` · `AXTextField` · `AXTextArea` · `AXSlider` · `AXComboBox` · `AXIncrementor` ·
`AXDisclosureTriangle` · `AXToolbar` · `AXRow` · `AXCell` · `AXImage`

**Bounds on the walk** — some apps have enormous trees and Kestrel is on your clock:

| | |
|---|---|
| Max depth | 14 for windows, **3** for the menu bar |
| Max elements | 220 |
| Menu bar | walked **first** — "how do I…" so often starts with a menu |
| Frame filter | ≥ 8 × 8 pt, < 3000 × 2000 pt |
| Label | first non-empty of title → description → value → help, ≤ 60 chars |
| Dedupe | on `role\|label\|x,y`, so repeated rows collapse |

Frames arrive from Accessibility in top-left screen coordinates and are converted to AppKit
bottom-left points, ready to hand to the overlay without a second conversion.

The model sees one line per control:

```
3. Export  (button)
12. File  (menu)
30. Subject  (textfield)
```

**If the scan returns nothing** — an app that exposes no Accessibility tree, or the permission is not
granted — Kestrel does **not** guess at coordinates. It answers the question instead
([SessionCoordinator+Acting.swift](../Sources/Kestrel/Core/SessionCoordinator+Acting.swift)).

### Desktop awareness

[DesktopSurvey.swift](../Sources/Kestrel/Input/DesktopSurvey.swift) enumerates running apps and
on-screen windows with titles, frames and bundle ids — the equivalent of HeyClicky's `list_apps` /
`list_windows` / `get_desktop_state`.

It is gathered **only when the question needs it**, because every extra line costs tokens and latency
on the questions that do not. Triggered by: *what else is open · what's open · which apps · what apps ·
other window(s) · switch to · running · my windows · open apps · on my desktop · other tab ·
what am i running*.

Windows smaller than 200 × 120 pt are dropped (palettes, tooltips, shadows); at most 18 are listed.

---

## 5. Planning: the contract with the model

[Resources/Prompts/agent.txt](../Resources/Prompts/agent.txt) — editable without a rebuild. The model
gets the screenshot, the numbered control list, any per-app skills, and must return **strict JSON,
no prose, no code fence**:

```json
{
  "goal": "what you are about to do, in the user's words",
  "needs_more": false,
  "actions": [
    { "kind": "press",    "element": 12, "describe": "Click the File menu" },
    { "kind": "setValue", "element": 30, "value": "Quarterly report", "describe": "Type the title" }
  ]
}
```

Rules the prompt imposes:

- At most 12 actions; prefer the fewest that actually work.
- `describe` must be honest — if a step sends, deletes, buys or posts, say so **in those words**.
  (The destructive check reads this string, so understating it is what the policy is defending
  against; the control's own label is checked alongside it.)
- If the needed control is not in the list: stop and set `needs_more: true` rather than guessing a number.
- If it cannot be done from this screen at all: empty `actions`, reason in `goal` — Kestrel speaks
  that reason instead of acting.

`ActionPlanParser` then re-checks everything on the way back in — fences, prose and missing fields
must never reach the actuator. Steps pointing at nothing, or describing nothing you could judge, are
dropped; the list is truncated to 12.

**Connectors.** Questions run with `--strict-mcp-config` (MCP discovery cost ~10 s per question).
Agent tasks are the one case where connectors may be worth it: `mcpForTasks: true`.

---

## 6. Permission: `~/.kestrel/policy.json`

[ActionPolicy.swift](../Sources/Kestrel/Core/ActionPolicy.swift). Written on first run, never
overwritten. Malformed or partial files decode field by field and fall back per field, so a typo
cannot silently disarm the whole policy.

```json
{
  "fallback": "confirm",
  "apps": { "com.apple.Terminal": "deny", "com.apple.Safari": "allow" },
  "blockedKinds": [],
  "confirmDestructive": true
}
```

| Field | Meaning |
|---|---|
| `fallback` | `allow` · `confirm` · `deny`, when no rule matches. **Ships as `confirm`.** |
| `apps` | Per bundle id. Ten terminals ship **denied** — see below. |
| `blockedKinds` | Kinds never performed anywhere, e.g. `["setValue"]` |
| `confirmDestructive` | Confirm anything irreversible even in an allowed app. Default `true`. |

**Decision order** — first match wins:

1. `blockedKinds` contains the kind → **deny**
2. `apps[bundleID] == deny` → **deny**
3. `confirmDestructive` and the text reads as irreversible → **confirm** *(this outranks an `allow`)*
4. `apps[bundleID]` if present → its decision
5. `fallback`

### Terminals are denied out of the box

`com.apple.Terminal` · `com.googlecode.iterm2` · `dev.warp.Warp` · `dev.warp.Warp-Stable` ·
`com.mitchellh.ghostty` · `net.kovidgoyal.kitty` · `io.alacritty` · `org.alacritty` · `co.zeit.hyper` ·
`com.github.wez.wezterm`

Typing into a terminal is arbitrary command execution, and no amount of confirmation text makes that
a good default. (The same list drives newline-collapsing for dictation, so dictated text can never
run a command either.)

### Destructive verbs

Checked against `describe` + the control's label + any `setValue` text, on **whole words and their
ordinary inflections** — never substrings. "Deleting the row" counts; "the sender column" does not.

> send · delete · remove · discard · trash · erase · wipe · clear · buy · purchase · pay · checkout ·
> order · subscribe · transfer · post · publish · tweet · submit · reply · share · invite · archive ·
> overwrite · replace · merge · deploy · release · sign out · log out · quit · shut down · restart ·
> format · reset · confirm · accept · approve · decline · cancel subscription · unsubscribe

### The confirmation

Modal, and deliberately so — this is the one moment you have to be in the loop. Kestrel activates,
shows the step's own `describe` as the message, names the app, and offers **Do it** / **Stop**.
Declining stops the whole run: *"Stopped, nothing was changed."*

---

## 7. Doing: the actuator

[Actuator.swift](../Sources/Kestrel/Input/Actuator.swift). Every action first requires
`AXIsProcessTrusted()`; without Accessibility it throws before touching anything.

| Kind | Mechanism | Fallback |
|---|---|---|
| `press` | `AXUIElementPerformAction(kAXPressAction)` | mouse down/up **posted to the owning pid** at the control's centre — still background, cursor stays put |
| `setValue` | set `kAXFocusedAttribute`, then `kAXValueAttribute` | none — fails loudly |
| `focus` | `kAXRaiseAction`, then `kAXFocusedAttribute` | none |
| `scroll` | `CGEvent(scrollWheelEvent2Source:)`, ±6 lines, `postToPid` | global `.cghidEventTap` only when no element handle exists |
| `launchApp` | `NSWorkspace.openApplication(activates: true)` | none |

Synthetic events are never posted to the global event stream when a target pid is known. That single
choice is what keeps the run non-disruptive.

`setValue` **replaces** a field's contents rather than appending — worth knowing when asking Kestrel
to "set" something that already has text in it.

---

## 8. Watching it, and stopping it

- **Overlay** ([AgentOverlay.swift](../Sources/Kestrel/Output/AgentOverlay.swift)) — a full-screen,
  click-through layer naming the goal, the current step, and `n of m`. A pointer glides between
  controls; the selection snaps to the target's bounding box. The ask panel hides first so it is
  never in a screenshot or in the way.
- **Pacing** — 0.45 s between steps. Not throttling: you have to be able to see what is happening.
- **Esc** ([EscapeWatcher.swift](../Sources/Kestrel/Input/EscapeWatcher.swift)) — a **listen-only**
  event tap, so it sees the key wherever you are and never swallows it from the app underneath.
  Anything that acts on its own needs a stop that does not require finding a window first.
- **Sequential and abortive** — a step that is denied, declined or fails stops the rest. A plan is an
  ordered thing; carrying on would leave a half-done state.

Afterwards the panel shows and speaks one line:

| Outcome | Summary |
|---|---|
| All steps ran | `Done.` / `Done — 4 steps.` |
| Policy refused | `Stopped: not allowed here` |
| You pressed Stop | `Stopped, nothing was changed.` |
| A control did not respond | `Stopped after 2: Could not press Send — the control did not respond` |

---

## 9. The audit log

Every attempted action appends one JSON object to `~/.kestrel/logs/actions.jsonl`
([ActionLog.swift](../Sources/Kestrel/Core/ActionLog.swift)). An assistant that can click things has
to be auditable after the fact. One object per line, so it reads live with `tail -f`:

```json
{"app":"com.apple.Mail","at":"2026-09-06T18:22:41Z","confirmed":true,"decision":"confirm","describe":"Click Archive","kind":"press","succeeded":true}
```

| Field | |
|---|---|
| `at` | ISO 8601 |
| `kind` / `describe` | the action, and what you were told it would do |
| `app` | frontmost bundle id |
| `decision` | `allow` · `confirm` · `deny` — what the policy said |
| `confirmed` | whether you were actually asked |
| `succeeded` / `detail` | outcome, and the failure message if any |

Steps refused by policy or declined by you stop the run before the actuator, so the log records what
was *performed*; the panel summary records why the rest was not.

## 10. Task folders

A task that produces something needs somewhere to put it. Each agent run gets
`~/.kestrel/projects/<slug-of-what-you-said>/` as the CLI's working directory
([ProjectStore.swift](../Sources/Kestrel/Storage/ProjectStore.swift)):

- Slugged from speech — lowercase, hyphenated, ASCII, ≤ 48 chars, `-2`, `-3` on collision.
- Can never resolve outside the projects folder, whatever was said.
- `CLAUDE.md` and `AGENTS.md` symlinked in, so a task run there still loads your memory file.
- Menu bar ▸ **Open projects folder**.

---

## 11. Limits — what it deliberately cannot do

- **No shell.** Kestrel never runs a command on your behalf. Terminals are denied.
- **No drag, no gestures, no arbitrary keystrokes.** Five kinds, all Accessibility-expressible.
- **12 actions per request.** A longer job comes back with `needs_more` and you ask again.
- **One app per run.** The scan is of the frontmost app; `launchApp` can bring another forward, but
  the plan was made against the controls that were visible when you spoke.
- **The plan is made once**, from one screenshot and one scan. Kestrel does not re-scan between steps,
  so a dialog appearing mid-run is not adapted to — the step fails and the run stops.
- **Apps with no Accessibility tree cannot be acted on.** Kestrel answers instead of guessing.
- **Nothing runs unattended.** Every run is one hotkey press by you.

## 12. Extending it

**Teach it your vocabulary.** Drop a markdown file in `~/.kestrel/skills/`. `default.md` is sent with
every request; `<bundle-id>.md` only while that app is in front — the place to record that "archive"
means the third toolbar button, or that your ticket ids look like `KES-123`. Menu bar ▸ **Open skills
folder**.

**Loosen or tighten the policy.** Edit `~/.kestrel/policy.json`; it is read fresh at the start of
every run, so no relaunch is needed.

**Add an action kind.** Four edits, in this order:
1. `Action.Kind` — the case.
2. `Actuator.perform` — the Accessibility call, and a background-safe fallback.
3. `agent.txt` — the kind, its `value` shape, and what `describe` should say for it.
4. `ActionPlanParser.sanitize` — which fields make it valid.

Then a test in `ActionRunnerTests` for the policy path and one in `AgentTests` for parsing.

## 13. Tests

Unit-tested: `ActionPolicyTests` (decision order, terminal denial, destructive matching and its
inflections, tolerant decoding), `ActionRunnerTests` (sequencing, abort on deny/decline/fail, step
cap, cancellation, summaries), `AgentTests` (act-vs-explain detection, plan parsing, sanitising),
`AgentOverlayTests`, `DesktopSurveyTests`, `TargetingTests`, `ProjectStoreTests` (slugging,
collisions, path-escape attempts).

Everything that needs a real Accessibility grant is in [Tests/MANUAL.md](../Tests/MANUAL.md) §5e–5f —
in particular: the real cursor not moving during a run, Terminal being refused, and declining a
confirmation leaving nothing changed.
