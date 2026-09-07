# Changelog

What Kestrel does, and when each part of it arrived. Newest first.

This is a record of the shipped product, not of the road to it: features that were built,
tried and taken out again are not listed, because nothing in the code depends on them and
nobody reading this needs to know they existed. Where a decision is not obvious from the
code, the reason for it is given here.

---

## [1.0.0] — 2026-09-07 — First public release

### Answers that point at things

The answer names what it is talking about on a trailing `MARK:` line, and Kestrel draws on the
real screen with a pencil while the sentence is spoken — a ring around a control, a shaded area
around a block of content, one mark after another. Numbers come from a list of real controls and
content regions read out of the Accessibility tree, so a frame is exact rather than estimated,
and it is re-read at the moment of drawing in case anything moved.

The prompt forbids describing where something is. "In the top right" makes the user do the
pointing; naming the thing and marking it does not.

An answer is two sentences by default. If the model names something without marking it, Kestrel
searches the answer for the visible names of things on screen and marks the best match itself —
but only when it could actually read the screen's content, because guessing among a browser's
own toolbar buttons puts a confident mark on the wrong thing.

**One question, one answer.** Nothing waits for a click and nothing takes a second screenshot.
Do the thing, and ask again if you want the next part; that question gets a fresh look at the
new screen.

### Drafts you can copy

"Write me a reply to this" is a different kind of question — the answer is not something to hear
and not something to point at, it is something to take away. The model replies with one spoken
line and the draft beneath it. The draft lands in its own card: selectable, monospaced, scrolling
when long, with a **Copy** button that puts subject and body on the clipboard. It is never read
aloud. The split is made as the answer streams, because speech starts before the whole answer
exists.

### Hold ⌃⌥ to ask

Asking is held down for as long as you are talking, so it is a bare modifier chord rather than a
chord plus a letter — one shape the hand already makes. macOS claims nothing on ⌃⌥, and with no
letter it cannot collide with an app's shortcut. It fires after a short dwell, so ⌃⌥ on its way
to another shortcut is not mistaken for a question, and any key pressed while it is held cancels
it.

Dictation stays `⌃⌘K`: it is a tap rather than a hold, so it remains an ordinary keyed hotkey
needing no permission of its own. Both are rebindable.

### A build that keeps its permissions

`scripts/make-signing-cert.sh` creates a self-signed code-signing certificate, once, and
`build.sh` uses it when present.

This matters more than it sounds. An ad-hoc signature is a hash of the binary, so without a
stable certificate every rebuild is a different application as far as macOS is concerned: it
stops honouring Accessibility and Screen Recording while leaving the checkbox ticked in System
Settings. Nothing reports an error. Until this landed, the screen-reading code had never once run
against a real app, because the grant was revoked by the very build that was meant to test it.

### Marks that land on the right thing

- Names are matched on **whole words**. "home" is a word in "home page" and is not one in
  "homepage"; without that distinction an answer about a hero section marked the Home button.
- Matching is **scored**, not first-past-the-post. The control list is offered menu bar first, so
  taking the first label containing the name quietly meant "prefer the menu bar" — an answer
  about a pricing table was marked on the Table menu above it. The tightest label wins, wherever
  it sits in the list.
- **Nothing filling the window is offered as a section of itself.** A browser nests the window
  group and the web area as near-identical rectangles that both carry the page title; marking
  either shaded the whole screen.
- Marks are de-duplicated on the whole rectangle rather than the top-left corner. A cell and the
  text inside it share a corner throughout an Accessibility tree, and keying on the corner meant
  an answer that named two things drew one mark.

### Reading web pages

Chromium does not build its renderer's Accessibility tree until an assistive client asks for it.
Until it does, a browser offers its own toolbar, tab strip and bookmarks bar and nothing at all
from the page — measured on a real window: 268 elements, not one of them the page. Kestrel now
asks. When a browser still refuses, the answer is given from the screenshot and nothing is marked,
rather than pointing at a toolbar button that has nothing to do with the question.

Chrome also reports the page address on the window's `AXDocument` and sets no `AXURL`, so the
model was being told "the open document is dashboard" — the last path component of a URL —
instead of where the user actually was.

### Circling a region

Holding the ask hotkey and dragging draws a trail; the bounding box is cropped and sent alongside
the full screenshot. The drag is **swallowed** rather than observed, so it never reaches the app
underneath: circling a paragraph used to select it, circling a link used to follow it, and because
the hotkey holds Control — the secondary click on macOS — circling anything opened the context
menu over the thing being asked about.

### Opening an app

"Open Spotify" opens Spotify. One verb, nothing to undo, no confirmation. Anything after that
("and play something") is not done, and Kestrel says so rather than half-doing it. This is the
only thing Kestrel does *to* the Mac.

### Memory that fills itself in

Onboarding ends with four questions that become `~/.kestrel/KESTREL.md`. After that, a
first-person statement in a question — "I'm working on the billing rewrite", "I prefer short
answers" — is filed under its own heading, deduplicated, newest first, capped at fourteen lines,
because that file is sent with every single request. Nothing read off the screen is stored: what
you are looking at is not a fact about you.

---

## [0.2.0] — 2026-09-06 — Seeing the screen

### Reading the screen, not just its buttons

`AXContentReader` walks the front window's Accessibility tree for *content* — headings, cards,
images, table rows, paragraphs — and hands the model a numbered list of them beside the clickable
controls, along with the text on screen in reading order and the page or document it belongs to.
This is what "how could this page look better?" needed: the answer had nothing to point at,
because a card is not a button. Only what is visible is read.

### Context

- **Follow-up turns.** A question asked within 90 seconds, in the same app, continues the previous
  one, so "no, the *other* one" works. Expires on time or when the frontmost app changes.
- **Per-app skills.** Markdown in `~/.kestrel/skills/`: `default.md` is sent with every question,
  `<bundle-id>.md` only while that app is in front. Cached on modification date, so a saved edit
  applies at once. Capped, because every question pays for it.
- **Desktop awareness.** Questions about what else is open get a survey of the other windows;
  everything else does not pay for it.

### Interface

- The panel is an island docked to the notch, opening only when there is something to read.
- Sound cues on hotkey down, release, answer and error, following system mute.
- A setup window listing every permission and tool, what each is for, and a button that asks for
  it. It re-checks itself while open, so a switch flipped in System Settings ticks the row without
  coming back to press anything.

---

## [0.1.0] — 2026-09-06 — Ask and dictate

The foundation, and the constraint the whole project is built around: Kestrel runs on the owner's
own **Claude Pro/Max** and **ChatGPT Plus/Pro** subscriptions by shelling out to the vendors' own
CLIs (`claude -p`, `codex exec`), which is the sanctioned way to use those plans programmatically.
There is no Kestrel backend, no account and no telemetry. Speech-to-text is local. The only things
that leave the Mac are the transcribed question and one screenshot, sent by the vendors' own tools,
only while a hotkey is held.

- **Ask.** Hold the hotkey, speak, release. Kestrel screenshots the display the mouse is on,
  transcribes locally with whisper.cpp, asks the backend, then shows and speaks the answer. The
  answer begins being spoken before it has finished arriving.
- **Dictate.** Tap, speak, tap again. The text is cleaned up by the model and pasted into whatever
  app is frontmost; the clipboard is restored afterwards. Newlines are collapsed in terminals, so
  dictation can never run a command. A cleanup failure falls back to the raw transcript rather than
  costing the user their words.
- **Two backends,** switchable from the menu bar, with an optional heuristic router.
- **Memory.** `~/.kestrel/KESTREL.md`, loaded natively by both CLIs on every request.
- **Menu bar presence,** floating panel, settings window, and `~/.kestrel/config.json` hot-reloaded
  on save.
- **Errors that say what to do:** "whisper-cli not found — run: brew install whisper-cpp", with a
  link straight to the right Privacy pane when a permission is missing.
