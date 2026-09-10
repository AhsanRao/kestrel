# Changelog

What Kestrel does, and when each part of it arrived. Newest first.

This is a record of the shipped product, not of the road to it: features that were built,
tried and taken out again are not listed, because nothing in the code depends on them and
nobody reading this needs to know they existed. Where a decision is not obvious from the
code, the reason for it is given here.

---

## [1.5.2] — 2026-09-10 — Kestrel's own blue

### The buttons were never Kestrel's colour

Every prominent button took whatever accent colour the Mac happens to be set to, which is why they
were a blue with nothing to do with the logo. Tinting them with the logo's blue only made them a
duller version of the same thing, so the primary action is the mark's actual accent: cyan, with the
logo's navy on top of it, which reads at 11:1 in either theme where white on cyan does not. It is
the pairing the draft card's Copy button has always used. Buttons also respond on the press now
rather than on the release.

### Icons in the menu

Every row in the menu bar dropdown carries one, the two backend rows included — an item without an
image indents its title differently, and a menu that starts half its titles in one column and half
in another reads as a mistake.

### "Open skills folder" said nothing about what it opens

It opens the folder of per-app notes: a file per app that Kestrel reads whenever that app is in
front, plus a default one it always reads. It is called "Open per-app notes" now. "Check
dependencies" is "Check what's installed".

---

## [1.5.1] — 2026-09-10 — Colour with a job, and a name at the bottom

### One palette, named by what each colour is for

`KestrelPalette` had six brand values and nothing else, so views reached for `Color.green` for a
tick here and `Color.secondary.opacity(0.22)` for a track there — two windows, two nearly-identical
greys, no way to change either without hunting. It now names roles: `accent`, `success`, `warning`,
`danger`, `surface`, `surfaceBorder`, `track`. Views ask for the job, never the hue, and the brand
sits underneath in one place. The success green is cooled towards the logo's cyan so a row of ticks
beside the rail reads as one palette rather than two.

### Setup fills its window

Every step laid out from the top, which left the short ones pinned under the rail with the rest of
the window empty below. Content is centred in the room between the rail and the footer now, and
scrolls only when a step genuinely needs more than that.

### The logo, the version, the notice

Both setup and settings carry a quiet strip along the bottom: the mark, the version, and who wrote
it. It says which build you are looking at, and it gives the bottom of a glass window somewhere to
end. The welcome step opens with the app icon.

`make icon` now also writes `assets/KestrelMark.png` — the artwork with its alpha rather than the
plated icon — and `build.sh` ships it as the logo. The plate is right in the Dock and wrong on
glass; the bare mark is the other way round at large sizes, which is why the welcome screen uses
the icon and everything else uses the mark.

---

## [1.5.0] — 2026-09-10 — Made of the same glass

### Setup is five steps, one thing at a time

It was a wall of nine requirements and then a form. It is now welcome, voice, permissions, profile,
ready — one purpose per screen, a rail across the top saying which, and one window size for all of
them so moving between steps is one movement rather than two.

The voice download comes before the permissions on purpose. It is long, it keeps running while you
carry on, and by the time the last switch is flipped it has usually finished by itself.

Only the three macOS grants appear on the permissions step. The CLIs and the speech engine are
somebody else's installer; anything still missing is waiting on the ready step, next to the two
hotkeys worth remembering.

### The windows are made of the menu's glass

Settings and setup were opaque panels that looked like they came from a different app than the menu
bar dropdown. They are backed by the same material the dropdown itself uses — not a blur that
imitates it — so they pick up dark mode and Reduce Transparency without being told, and the desktop
moves behind them.

The island is deliberately not part of this. It is pure black because it has to match the camera
housing, and anything translucent there puts a seam around the notch.

### Kestrel talks like Kestrel

Every line in setup and settings was rewritten. "Configure your profile information" was never how
this thing should sound. "Backend" is "Brain", "Point at what the answer is talking about" is
"Circle what I'm talking about", and the permissions explain themselves in the first person,
because it is Kestrel asking.

### Models are chosen, not typed

The Claude model was a text field you had to know the answer to fill in. It is a menu: whatever the
CLI picks, or Opus, Sonnet or Haiku, described by what they are good at. A model id already set by
hand stays in the list as itself rather than being quietly dropped.

---

## [1.4.1] — 2026-09-10 — A way out of everything

### Esc dismisses whatever is on screen

It used to reach only the marks, and only while they were drawn. An answer the user had finished
with could not be dismissed at all — the only way out was to wait for the clock, and a pointer
resting near the notch stopped even that. Esc now takes the panel, the marks and whatever Kestrel is
saying, from wherever the user is, for as long as anything is showing. The event tap is torn down
the moment nothing is.

### A hover cannot hold the island forever

Hovering pauses the auto-hide, because hovering usually means reading. A pointer parked near the top
of the screen is not reading, and it used to pin the island there for the rest of the session. The
pause now has a limit, and the session's own clock gives up at the same moment the window does
rather than a moment later.

### Clipped text says what was clipped

A long answer stops at fourteen lines and a long draft at sixteen. They stopped silently, so the
last line on screen read as the last line there was — worst on a draft, where the next thing anyone
does is copy it. Both now say how many lines did not fit, and the draft says that the copy has all
of them, which it always did.

### An answer reaches VoiceOver

The panel never takes focus — that is what lets you keep typing while it answers — so a screen
reader had no reason to look at it. An answer that is not being read aloud is announced, and so is
every error, which is never spoken.

### Two labels that were too faint to read

The hotkey hint and the transcript line sat at 35% and 45% white on pure black, which is 3.0:1 and
4.4:1 — under what text needs. They are 55% and 60%.

---

## [1.4.0] — 2026-09-10 — One object, moving

### The window and the island move as one thing

The black shape is drawn by SwiftUI on a spring; the window holding it was resized on a fixed curve
of a different length. Two curves on two objects that are meant to look like one object, and the
seam showed on every open. The window frame is on a spring now, given the island's own response and
damping, integrated a frame at a time in step with the display.

### An answer arriving line by line grows in one movement

This is what the spring is really for. A streaming answer resizes the window once a sentence, and a
window's frame reads as the *target* of an animation the moment that animation starts — so each new
sentence restarted the movement from a place the window had not reached yet, and the island grew in
stutters. A spring is retargeted rather than restarted: it keeps the size and the speed it already
had, and four sentences landing faster than the spring's own response settle into one continuous
growth.

Width and height are separate springs. A single spring on the diagonal desynchronises as soon as
the two axes have different distances to cover, which is most of the time.

### It leaves the way it came

The island unrolled out of the top edge to arrive, then faded where it stood to go — a shape that
grows out of the notch has to go back into it, or the illusion that it *is* the notch goes with it.
It rolls back up now, on the entrance curve reversed. A question asked while it is leaving calls
the exit off instead of letting it finish underneath the answer.

---

## [1.3.3] — 2026-09-10 — One button at a time

### The second way in appears once the first has been tried

Every unmet permission offered two buttons at once — "Allow" and "Open Settings" — which is a choice
between two routes to one thing before either has been tried. macOS shows its own prompt the first
time and never again, so the pane is only worth the space once asking has visibly done nothing.
"Open Settings" now appears under the row after "Allow" has been pressed.

### Copying a command says so

The tool rows put a shell command on the clipboard and gave no sign of it. The button says "Copied"
for a moment afterwards, the same confirmation a copied draft gets.

### The restart notice waits for the grant

Pressing "Allow" on Screen Recording claimed a restart was pending whether or not the permission was
ever given, and went on claiming it. The notice now belongs to the grant landing: Screen Recording
reads as granted the moment it is given, but this process cannot capture anything until it is
restarted, and that is exactly when there is something to say.

### The checks are off the main thread

They stat files and walk `PATH`, and they run every 1.5 seconds under a window that is animating.
They run on their own queue now and hand the result back.

### Small text is readable

The command hints, the ready count and the download caption were 10pt tertiary — grey on grey, below
the contrast a label needs. They are 11pt secondary, and the section headings and step labels are
secondary too.

---

## [1.3.2] — 2026-09-10 — Setup you can walk back through

### Two steps, and a way between them

The checklist and the four questions after it were two screens swapped in place, with the window
resizing under them and no way back. They are steps now, and they say so: each is headed "Step 1 of
2" or "Step 2 of 2", both fill the same window, and moving between them slides one out as the other
comes in. Each half enters and leaves by its own side, so Back retraces the way forward rather than
pushing on in the same direction. Under Reduce Motion the two cross-fade instead.

The second step has a Back button. Skipping a permission no longer means losing the chance to go
and grant it.

### The button says what it does

The checklist's button was labelled "Next" or "Skip for now" depending on what was still missing,
for one action that did the same thing either way. It says "Continue". The line beside it is what
says whether anything is being left behind.

### Closing the window finishes setup

Dismissing it with the red button used to leave the flow unfinished: setup was never marked as seen,
so it opened again on the next launch, and reopening it dropped the user back on whichever step they
had reached rather than at the start. Closing now counts as having seen it, once, and the window
always opens on the checklist. A required permission that is still missing brings it back regardless
— that has not changed, and is the reason marking it seen is safe.

The window is called "Set up Kestrel", which is what its first page has always called it, and is
still true the second time it is opened from the menu.

---

## [1.3.1] — 2026-09-10 — Setup that moves properly

### The checklist reads as one list

The setup window's rows arrive one after another, top to bottom. They always meant to: the delay
was counted over every requirement Kestrel knows about, including the two whisper rows that are not
shown at all on Apple's speech engine, so the cascade skipped beats where a hidden row would have
been. And both sections started their own count from zero, so Permissions and Tools arrived side by
side rather than in sequence. The rows are resolved before the list is laid out, and the second
section continues the first one's count.

The rule line under the last row of a section is gone. The next section's heading is the break, and
two of them together read as a mistake.

### Rows settle instead of snapping

Granting a permission used to make the row jump: the tick bounced in, but the hint line and the two
buttons under it vanished on the same frame and the row snapped to its shorter height. They fade and
scale away now, and the row closes up around the tick on the same spring the rest of the window uses.

### A sound when setup is done

The last required permission is almost always granted in another window — System Settings, over the
top of Kestrel — so the moment everything is in place is a moment the user cannot see. It gets a
short rising cue, the footer line turns green, and the count ticks rather than snapping. Like every
other cue it is off when sounds are off, and silent on a muted Mac.

### Reduce Motion is honoured

The setup window was the one part of Kestrel that ignored it. The progress bar, the row ticks, the
window settling and the arrival cascade are all off under Reduce Motion — the cascade especially,
because a stagger delays content for exactly the person who asked for less movement. All four now
read the same setting, from one place.

---

## [1.3.0] — 2026-09-10 — A voice worth listening to

### Answers are read by Kokoro, not by macOS

Apple's premium voices are the best it will lend an app — Siri's are locked to Siri, and no API
exposes them — and they still sound like a machine reading. Kokoro is an 82 M-parameter neural
model that runs on this Mac, free and offline, and sounds like a person.

It arrives as a download in the setup window, about 370 MB once, and can be declined: skip it and
Kestrel goes on using the best system voice, which is what it always did. Nothing about speech can
block first use.

Four voices are offered, out of the fifty-four the model carries: **Heart** (the default), Sarah,
Michael and Puck. The model selects a voice by index rather than by name, and the indices are not
alphabetical — they are read from the model's own metadata, because guessing them puts a stranger's
voice on your Mac.

The full-precision model is the one downloaded, not the quantized one. On Apple Silicon it is the
*faster* of the two — 3.6× real time against int8's 1.5× — so quantizing would cost quality and
buy nothing but a smaller download.

Synthesis is slower than playback, so sentences are made ready while the previous one is still
being spoken. Only the first sentence of an answer waits.

### A Personal Voice is still there if you want it

The macOS engine did not go away; it moved behind a switch. Settings ▸ Speech chooses between the
two, and with the macOS voices selected a Personal Voice still outranks everything else.

## [1.2.1] — 2026-09-09 — A finer line

The rings and boxes Kestrel draws around what it is talking about were heavy enough to hide the
thing underneath them. The stroke is thinner now, and the glow behind it is tighter, so a mark
points at a control instead of covering it.

## [1.2.0] — 2026-09-09 — Your own voice

### Kestrel can answer in your Personal Voice

macOS trains a Personal Voice on the Mac itself from about fifteen minutes of recorded
prompts — the user's own voice, never uploaded. Kestrel now asks for it once at launch and
ranks it above every installed voice, so an answer comes back in a voice that belongs to the
person who asked rather than a stranger's.

The ranking needed the explicit rule. A Personal Voice reports `.default` quality, the same
tier as the compact voices that sound like a speak-and-spell, so ranking it by quality alone
put the best voice on the machine at the bottom of the list. It is ranked on its trait
instead, labelled "Personal" in the voice picker, and no longer trips the "only compact voices
are installed" warning.

Siri's voices remain unavailable to any app; there is no API for them. Personal Voice is the
one neural voice macOS will lend out.

## [1.1.0] — 2026-09-08 — Speech that needs no download

### Transcription uses macOS's own engine

`SpeechAnalyzer` and `SpeechTranscriber` on macOS 26 are the engine system dictation uses:
on-device, nothing uploaded, and nothing to install. Kestrel uses them by default. whisper.cpp
remains the fallback below macOS 26 and as a config override (`transcriptionEngine`), so the
148 MB model download is no longer part of setting Kestrel up.

The setup window follows suit: when Apple's engine is the one that will run, the whisper binary
and model rows are not shown at all. A checklist that cannot be completed is worse than a short
one. The `transcriptionHint` field still works — it becomes the engine's vocabulary list rather
than a whisper prompt.

### The setup window comes back when a permission does not

Accessibility was still marked optional, from when asking was a keyed Carbon shortcut. It has not
been optional since the ask hotkey became a bare ⌃⌥ chord: Carbon cannot register one, so it is
watched through an event tap, and without the grant the hotkey never fires.

The effect was that revoking Accessibility — or rebuilding without a stable signing certificate,
which does it silently — left Kestrel running, in the menu bar, with no working hotkey and no
setup window either, because nothing "required" was missing. Whether a requirement is required now
depends on the configuration: mandatory for the default chord, still merely recommended when the
ask hotkey is bound to an ordinary keyed shortcut.

### Marks and drafts

- Every area the answer names is marked, not just the first two.
- Marks stay up long enough to be read. They are drawn one at a time, so a fixed lifetime measured
  from the answer gave the last mark of a long answer a fraction of the time the first one got; the
  lifetime is now measured from the drawing itself, with a reading beat after it.
- Marks can reach past the menu bar, and circling a region works again.
- A reply always gets a copy button, and the spoken line above it is worth hearing on its own.
- The draft body is shown rather than clipped, and the panel covers the notch completely.
- "Didn't catch that" takes itself down after three seconds instead of sitting there.

### Fixed

- Multi-segment transcripts kept double spaces. Runs of whitespace were collapsed with a single
  non-overlapping pass, which only ever halved them — and the engine pads both sides of a segment
  boundary, so four spaces became two rather than one.

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

How many marks follows the question. A pointed one — "what does this button do" — gets one or
two. "What's happening on this screen" gets one per area the answer names, up to six, because
marking two of five areas leaves the user hunting for the rest. They stay up on a clock measured
from the drawing rather than from the answer, since the marks are made one at a time and the last
one of six arrives several seconds after the first.

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
line and the draft beneath it. The draft lands in its own card: selectable, monospaced, laid out
at its full height, with a **Copy** button that puts subject and body on the clipboard. It is never
read aloud. The split is made as the answer streams, because speech starts before the whole answer
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

### Speech to text with nothing to install

macOS 26 ships the engine system dictation runs on — `SpeechAnalyzer` and `SpeechTranscriber` —
and Kestrel now uses it by default. On the same eleven-second clip it returned a transcript in
about 0.4 s against whisper's 4.6 s with `large-v3-turbo`, at the same accuracy, and there is no
`brew install` and no 148 MB model to download before Kestrel works. Three seconds of silence
gives back an empty string instead of whisper's confident "you".

whisper.cpp is still there. It runs below macOS 26, and `transcriptionEngine: "whisper"` picks it
deliberately; the engine is chosen per question, so the config edit needs no relaunch. The setup
window shows whichever one is live and stops asking for a binary that is not going to be used.

Kestrel is English-only, which is now stated rather than implied. Apple's engine has no Urdu
locale and whisper's Urdu was never good enough to build on, so both engines run English, and
Roman Urdu is transcribed the way it is written. Words that come out wrong — names, the Urdu you
use most — go in `transcriptionHint`, which reaches whisper as `--prompt` and Apple's engine as
contextual strings.

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

- The panel is an island docked to the notch, opening only when there is something to read. Black,
  and a shade taller than the camera housing, so the housing has no edge left showing.
- The panel takes itself down and clears the session with it: twenty seconds after an answer,
  eight after an error, three after "Didn't catch that" — nothing was heard, so there is nothing
  to read. Hovering pauses the clock.
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
