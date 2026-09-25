> Part of `docs/presentation.md`. Engine 0.25.0.

## Channels — which screen a rider sees at all

Every rule in this file is written for the app; **docs/channels.md** says which of the three
channels a given screen is in, and it is the single source for that — the website's "what is
coming" list, the app's own Beta section and the store texts are written from it. Release is
the App Store build (no compile flags, iPhone, no watch app or widgets); beta adds `BETA`
(GPX/TCX, the dedicated **Garmin export ZIP…** door with its Export-Your-Data walkthrough —
the ZIP itself is read in every channel through *FIT or ZIP…*, docs/channels.md — Apple
Health, the Apple Watch app and widgets, the session
video, the library's grouping and filter controls, the Beta section and its update
reminder); dev adds `DEV` and
`TUNING` on top (the Garmin link and its Settings section, windsurf and the per-discipline
sets, the Tuning section below, iPad).

Two rules follow for everything written here. **One wording per metric across every channel:**
a label does not change because a build is a beta, and nothing in this file is allowed to have
a channel-specific spelling. **A gated door is gone, not greyed out:** a channel that lacks a
feature has no row for it, no document type, no usage string and no entitlement — the one
exception being Settings → "Coming in a future release", which is the app naming the doors one
channel up, on purpose, in one place.

A third rule, from the release walkthrough of 14 September 2026: **the release never calls
itself a beta and never names a door it lacks.** Not in a help topic, not in a footer, not in
the subject of the mail it writes. Where a sentence is about a feature that lives one channel
up, it is written as a *fact about where the feature is* ("in the public beta"), never as a
promise and never as the answer to the reader's question — the answer a release reader gets
is a door his build actually has.

**The help catalogue follows the same rule, and it is the one place the kit had to be told.**
The catalogue is pure data and compiles whole in every build, so every `HelpTopic` carries a
`channel: HelpChannel` — the lowest channel that has the door it explains, `.release` for
almost all of them — and the app hands its own channel in (`ChannelFeatures.channel`). The
index lists and searches `HelpCatalog.indexTopics(channel:windsurfEnabled:)`; a topic page's
"See also" renders `HelpCatalog.relatedTopics(of:channel:)`, so a visible page never offers a
chevron onto a hidden one. `HelpCatalog.topic(_:channel:)` is **not** filtered and stays
total: a `?` on a card the build actually draws always opens, and its `channel` — `.release`
by default, the strictest reader — decides only what the page *says*.

**A topic's items may depend on the channel, and one topic's do** (Jan, dev 65). The
catalogue is a static array of `let`s and cannot ask which build is reading it, so a topic
whose items are the *ways in* — Getting started, whose five routes include two beta doors —
was declared with the release's list and served it to every channel: the beta's own Apple
Watch app and Health import were named on no page a rider would look for them on.
`HelpCatalog.topic(_:channel:)` now rebuilds the items for the asking channel
(`resolved(_:channel:)`, `HelpTopic.withItems`), `HelpTopicSheet` passes `AppChannel.channel`,
and `indexTopics`, `relatedTopics` and `search(_:channel:)` resolve through the same seam —
so every entry point to a page (the menu row, the index, a card's `?`, a "see also" chevron,
the Settings deep links) is the one channel-aware path. Nothing else about a topic branches:
title, summary, body and `related` are the same sentences in every build.

**A ladder is items on one page, not a page per rung** (Jan, dev 65: *"do we really need
separate pages to describe each distance?"*). *Speed records* was eight topics — the set,
`Best 2 s`, `Best 10 s`, `5 × 10 s`, `Best 500 m`, `Best 1 NM`, `Alpha 500` and
*"Uncertified"* — of two sentences each, which is a table of contents wearing chevrons. It is
one topic now (`HelpTopicID.speedRecords`, the whole of section `.records`): the body says
what the set is and how it is computed, and the windows are its **items**, one line each,
with *"Uncertified"* last because it is about the recording rather than about a window. Three
of those lines are `MetricGlossary`'s — `speedRecords` is the summary, `best5x10s` and
`alpha500` are their own items — so the help and the session page cannot spell the same
metric two ways. The seven retired ids are **gone, not aliased**: the session page's two `?`
buttons (the speed chart, the records card) point at `.speedRecords`, and `HelpCatalog.search`
already indexed item *terms*, which is what keeps "2 s", "500 m", "alpha" and "uncertified"
finding the page (`PresentationTests`). Bound today: *Recording with the Apple
Workout app* (beta) and *Windsurf (experimental)* (dev, and also behind its own switch). Where
one sentence serves two channels the release wording names the beta as the place a door is —
"GPX and TCX files are read by the CleanJibe beta; a FIT is read by every build" — rather than
describing a door this build does not have. docs/channels.md is the source for which is which.

**One topic is generated rather than written here: *Getting started*.** Its framing, its
routes and their steps, and the two Settings captions live in `docs/guide/getting-started.json`,
and `web/tools/make_start.py` writes both the kit's `Help/GettingStartedGuide.swift` and the
guide block of `web/start/index.html` from it — the app showing each route's title and
summary, the web adding the numbered steps. Each route in the source carries its own
`channels` list, which is the same rule one level down: `GettingStartedGuide.items(for:)`
filters on it, the catalogue is declared with `.release` and the lookup rebuilds it for the
channel the app hands in, and the two Apple routes are `.beta` — items on the beta and the
dev, `related` topics the release drops. See "The library menu", item 2.

Settings → About and the library menu's last line carry the channel after the version —
nothing for the release, " · beta", " · dev" — because "which build is this" is the first
question of every report that comes back from TestFlight.

## Tuning — the thresholds on sliders, in the dev build, on one phone

**What it is.** Settings → Tuning puts 28 of the docs/algorithms.md parameters on controls so
a threshold can be tried against a real library in a minute instead of an afternoon: turn
detection and scoring (`turnMinAngle`, `turnClassifyMinAngle`, `turnAxisBeforeDeg`,
`turnAxisAfterDeg`, `turnCleanQuietS`, `turnMaxDuration`,
`turnPeakRate`, `turnContinueRate`, `turnMinArc`, `turnMinRadius`, `entrySpeedWindow`,
`minSpeedLag`, `turnSuccessPct`), the stop ladder (`turnStopSpeedFloor`,
`turnTouchdownMaxStop`, `turnFallStop`, `turnOutcomeLookahead`,
`turnOutcomeLookaheadNotRecovered`, `turnRecoverPct`,
`turnRecoverHold`, `turnOutcomeWindow`, `turnPumpedOutIsTouchdown`,
`turnPumpedMarginalSpeed`) and flight hysteresis
(`foilEntrySpeed`, `foilExitSpeed`, `entryHold`, `exitHold`, `minFlightDuration`). `nil` means
the published default; setting a control back to the default clears the override rather than
storing it.

**How a row reads** (7 Sep 2026, Jan: "review all descriptions on the new tuning page for
clarity"). Each row is named in the rider's words — "Fall: shortest stop", "Flying again
at", "Quiet tail after the sweep, for clean" — with the docs/algorithms.md name printed
small under it, so the page reads on its own *and* lines up with the parameter table. The
caption under the slider is "default N · what moving it does to what you see", written as
an effect, never a mechanism: "a stop longer than this is a fall", not "fall threshold".
Where a verdict word has its threshold, the caption says what the word means there. The
three group footers say what a rider will watch change (more or fewer turns; verdicts
shifting between touchdown and fall; foil time and flight counts). **One tail, not two:**
`turnOutcomeWindow` has equalled `turnOutcomeLookahead` since 0.13.0 and the lookahead
slider moves both, so the window has no row of its own (`TuningParameterSpec.hidden`) — an
explicit override stored by an earlier dev build is still applied and still wins.

**The tail has a second length, and it gets its own row** (engine 0.24.0, ADR-032).
`turnOutcomeLookaheadNotRecovered` follows the row above it, reading *"…and how long if you
never got going again"* — default 30 s, *"the same tail, followed this far while you are still
not flying again; set it to the lookahead to switch the rule off"*. The two caps are what the
rule is made of, so they are two controls rather than one: tying them together would leave
nothing to compare, and putting the rule on the lookahead's slider would hide the very number
the rule turns on.

**One row is a switch** (`TuningParameterSpec.kind`, engine 0.18.0). `turnPumpedOutIsTouchdown`
is a rule that is either applied or not, and a slider from 0 to 1 would be a lie about the
question, so the Outcomes group draws it as a `Toggle`: title *"Pumped out below min foil speed
is a touchdown"*, the code name small under it like every other row, and the caption *"default
on · with no sample off the foil, a pump burst that dropped below the flight-end speed still
counts as a touchdown when on; off, it flew through and the chip says it pumped out"*. The
value is still a `Double` in the override map (0 = off, 1 = on), so the fingerprint, the clamp,
the reset and the drop-if-default rule all keep working unchanged — the switch is a *rendering*
fact and nothing else. It prints "on"/"off" and never "1"/"0", and the row shows no value
beside the control, because the control already says which way it is set.

**And the slider under it is the one that moves the number.** `turnPumpedMarginalSpeed`
(4…20 km/h, step 0.5, default **8**) is the speed the switch's rung corroborates against, and
at its default the rung cannot fire at all — so a rider who wants the old rule back raises this
rather than touching the switch. Title *"Pumped out below this speed is a touchdown"*, caption
*"default 8.0 km/h · when the switch above is on and no sample was off the foil, a pump burst
that dropped below this speed still counts as a touchdown; at the flight-end speed it can never
fire, raise it to revive the rule"*. The two rows sit together in Outcomes and read as one
question and its answer: whether the rung is asked, and what it asks. Moving the speed moves
nothing else — flight segmentation reads `foilExitSpeed` and never this — which is why it is
its own knob and not pushed onto the flight hysteresis the way the shared thresholds are.

**One set per discipline** (13 Sep 2026, Jan: *"for the windsurf analysis, we need to be able
to set other parameters (min planing speed, etc) than for wingfoil. Is that possible on the
settings/details page?"*). The page opens with a segmented picker — **Tuning for: Wingfoil ·
Windsurf foil · Windsurf fin** — and everything under it belongs to the rig it names: the
values, the "default N" captions, the per-row reset, "Reset all", the chip's count and the
fingerprint in the footer. A fin board planes at 20 km/h where a foil flies at 12, so one
`foilEntrySpeed` slider was always wrong for one of them.

- **Each set stands against its own preset, not the published wingfoil numbers.** On the fin
  set the flight rows read *default 20.0 km/h* and *default 15.0 km/h* (docs/algorithms/disciplines.md,
  "Disciplines"), dragging one home clears the override rather than storing a number that only
  repeats the preset, and a fin slider set to wingfoil's 12.0 is a real override that is kept.
  Only the three thresholds a preset moves differ; every other row is the parameter table.
- **The pump rows are shown disabled on the windsurf sets**, captioned *"off for windsurf —
  there is no pump channel to corroborate against, so the rung is refused rather than merely
  unreachable"*. Disabled rather than hidden so the page does not change length when the picker
  moves; and an override of one is dropped rather than stored, so no count or fingerprint ever
  carries a knob that moves nothing.
- **Applying to a session: the preset first, then that session's discipline's overrides on
  top.** The other order would let a preset stomp a slider the rider has just moved. The two
  speeds still travel in all four configs together, tuned or not.
- **Each set is its own staleness key.** The fingerprint rides *inside* that discipline's stamp
  — `0.19.0+disc.windsurfFin+tuned.2.a1b2c3d4` — so moving a fin threshold re-derives fin
  sessions and leaves every wingfoil session on the numbers it was already analysed with. "Re-
  analyse stale sessions now" is that same per-row sweep taken immediately, which after a move
  on this screen is the selected discipline's sessions and no others. The session page's chip,
  the turn page's "Measured at" line and the workbench's what-if all read the session's own
  discipline set; the Records and Trends chips count **every** set, because they are aggregates
  over a library that may hold more than one rig.
- **Stored under the key the single set used to live at** (`tuningOverrides.v1`), now as
  `{"wingfoil": {…}, "windsurfFin": {…}}`. The migration is one rule: **a stored flat map
  becomes the wingfoil set** — its values were wingfoil's by construction, since the presets
  did not exist while the single set did — and the other two start empty, so nothing re-derives
  because of the upgrade.

**Phone-only, and dev-build-only.** The watch computes live on the wrist with no way to be
told, and the web reads documents the phone wrote — neither follows a slider, and neither is
asked to. And the whole feature is compiled out of the app external testers get: it lives
behind `#if TUNING`, which only the "WingFoil Dev" scheme defines (docs/testing.md, "Two
TestFlight variants"). In the public build `SessionIngestor.tuning` is never assigned, so the
engine can only run the published defaults, and a `tuningOverrides.v1` left in UserDefaults
by a dev build installed over the same bundle id is not even read.

**What changing one does.** Everything. Foil time, flight count, turn counts, scores,
outcomes, clean jibes, records, trends, periods and the share card are all derived from the
same analysis. So a moved slider marks the whole library stale by the mechanism an engine
bump already uses: the overrides' fingerprint rides in the analysis' `engineVersion` as
`0.19.0+tuned.<n>.<hash8>` (`TuningStamp`), which is the string `reanalyzeStale()`,
`SessionArchive.analysis(for:)` and `SessionStore.detail(for:)` already compare on. Sessions
re-derive lazily on open and in bulk at the next launch; "Re-analyse all sessions now" is the
same trip taken immediately, and leaving the page takes it automatically.

**The mark, and where it must appear.** A tuned number may never be shown unmarked:

| surface | mark | read from |
|---|---|---|
| session header, beside the discipline badge | `tuned · N` chip | that session's stored `engineVersion` |
| session page, in the divergence banner's slot | "Analysed with N tuned thresholds · Settings → Tuning" | that session's analysis |
| Records header, Trends header | `tuned thresholds · N` chip | the *current* setting, summed over every discipline's set — these are aggregates over a library that may hold more than one rig |
| Settings → About | `0.19.0 · dev` | the build variant itself |
| turn detail footnote | "Measured at: turnSuccessPct 70 % · minSpeedLag 2 s · turnOutcomeLookahead 12 s" | the analysis' own `config` echo |

### Dev strips and window — the detectors, drawn

Three things on the two detail pages are compiled out of the public build with the tuning page
itself, and for one reason: they are pictures of **detectors**, not of the ride. A rider does
not ask what his rate of turn was in degrees per second; somebody moving `turnPeakRate` asks
nothing else.

**The window control.** Two sliders above the drawing — **lead-in 5…20 s**, **run-out
8…60 s** — remembered per phone in `@AppStorage`, and the drawing, the strip and the extra
strips are all cut to them. The pads were one constant, `TurnSlice.defaultPadS = 8`, which is
a good default and a bad only-option: eight seconds cannot hold the clean jibe's **quiet
tail**, which closes ten seconds after the sweep, so the strip's `quiet` rule was drawn "only
when it fits" and in practice never fitted; and it cannot show what a fall actually did, where
the interesting part is the half-minute of swimming `turnOutcomeWindow` is measured over. The two
ranges differ because the two ends do different work: the lead-in only has to hold
`entrySpeedWindow` plus an approach, and every second added to it pushes the sweep to the
right of the frame, while the run-out has to reach the quiet tail and the recovery. A note
under the sliders says whether the run-out is yet wide enough to draw the `quiet` rule, which
is the main reason to touch them. The engine's own windows stay marked inside the wider span —
`entry`, `sweep`, `outcome`, the recovery and `quiet` are drawn to the same numbers, and only
the frame around them moves.

**Not in the public build**, deliberately. "The drawing is 8 s either side of the sweep" is a
sentence in the footnote and a promise that two turns are drawn at one scale in time; a
control that broke it silently, on the screen a rider reads to compare his jibes, would cost
more than it gives. The public footnote's number is the constant; the dev footnote prints
whatever the sliders are at.

**The heading strip**, under the speed strip and on its clock. The speed strip says what the
turn cost; it cannot say why *this* stretch of track is a turn and the stretch either side of
it is not, and that is a heading question from end to end. It draws:

| mark | what it is |
|---|---|
| the heavy line | **TWA** where the wind is known — 0 = head to wind, ±180 = dead downwind — and the compass **heading** where it is not, said in the strip's own title so the two are never confused |
| — | **unwrapped**: consecutive angles are moved by whole turns so each step is the shortest one, anchored on the first vertex. A sweep through north is a straight climb rather than a 350° cliff and a 10° recovery, and a jibe carries *through* ±180 instead of folding back |
| a dashed horizontal rule | the **axis** the maneuver is named by: ±180 for a jibe's downwind, 0 for a tack's head-to-wind, captioned above its left end. **Absent on a heading series** — a compass 0 is north, and a rule there would invent a fact |
| a light second line, right axis | the **rate of turn** in °/s, signed |
| four thin rules | `turnPeakRate` and `turnContinueRate`, at **±** each. Four and not two because the rate is signed: a jibe spun to port clears the same bar as one to starboard, and drawing only the positive half would make half the turns on the page look like they never did |
| a dotted rule at 0 | where the board stopped turning, which is what trims the sweep's two ends |

Both series share one y scale — Swift Charts gives a plot one domain — with the rate mapped
onto the angle's range and the right-hand ticks labelled with the inverse, so the secondary
line has real units. Two stacked plots would have cost the one thing the strip is for: seeing
the rate cross its threshold **at** the moment the line steepens.

**The barometer strip**, third. `submerged` is one rule against one threshold — a sample
counts as underwater when the pressure altitude reads `turnBaroDrop` below the **local
baseline**, the line the altimeter had settled on just before (engine 0.22.0, ADR-029) — and it
is the evidence that promotes a touchdown to a fall. Until this strip the only thing any screen
showed of it was a chip saying yes or no: a dunk that grazed the line and one that went forty
metres under looked identical, and "is 25 m the right number" had no picture to be answered
from. Everything is drawn in **metres relative to that baseline** (`BaroReference.session`
builds the engine's own line once per session and `.at(ts)` hands each drawn window the value
in force at its own start, rather than spelling the rule a second time), which puts the
wrist-under rule at a fixed −`turnBaroDrop` and makes two maneuvers comparable — on the water
the absolute altitude is a pressure reading and means nothing, and on a watch that re-anchors
mid-session a median of the afternoon would put the rule in the wrong place on every picture
after the step. The submerged samples are
marked and their **episodes** shaded, read from `analysis.submersions` rather than by
re-applying the threshold here: one rounding apart from the stored document and the picture
would quietly disagree with the chip above it. A session with no barometer gets **one line**
saying so, never a flat trace at zero — "nobody was looking" and "the wrist stayed up" are
different facts and only the strip can tell them apart.

**Pump strokes on the speed strip** are the one addition that is *not* dev-only, because they
answer a rider's question: the page already says whether he pumped out and how many strokes it
took, and could not say **when** — which on a touchdown is most of it, since a rider who pumps
the instant he lands and one who drifts six seconds first wear the same chip. They are drawn
as a low band along the floor of the plot with the count on it, and **a span rather than one
tick per stroke**, because that is what the engine stores: a `PumpEpisodeRecord` carries the
first stroke, the last and how many were between them, and individual stroke times are never
persisted. A tick per stroke would be an invention. Nothing is drawn where no episode names or
overlaps the window, which is the same absence the chip already handles.

**All four strips are one picture.** One clock, one scrub, one playhead, the same bands in the
same ink under the same words — which is a contract between views, and a contract four views
each implemented privately would last until the next edit. It lives in `StripChrome`: the
bands, the rules, the captions, the caption-collision gap, the playhead and the scrub surface.
What stays with each strip is the only thing that differs, which is what it plots.

The session-level marks read the *analysis*, not the current setting, because a session
analysed under tuned thresholds stays tuned until it is re-derived — that is the only honest
answer, and it is why the chip survives a "Reset all" until the sweep has run. The chip is
neutral rather than a warning: a tuned analysis is not wrong, it is measured against
different thresholds. What it may never be is absent.

### Tuning this turn — five tools that show the working

A slider moves a threshold; it does not say what the threshold *did*. The dev build therefore
carries five tools that answer the questions a moved slider actually raises, all of them
**presentation** — computed on the fly from the stored `SessionAnalysis` and the session's own
samples, storing nothing, changing no verdict, and compiled out of the public build with
everything else behind `#if TUNING`. The pure halves live in the kit
(`Presentation/Dev/`, no `#if` there) so a test can hold them; the app gates their use. Two of
them are one insertion each on the turn page and the Turns tab, so the files they land in stay
readable.

**It is a screen, with a title** (19 September 2026, pattern A). Four of the five tools were a
heading called *Dev workbench* stacked under the turn page's own content — this file named it
as if it were a screen and the app never did. The turn page now carries one row,
**Tuning this turn**, which pushes them onto a page of that name. Not plain *Tuning*: Settings
→ **Tuning** is the 27 sliders, and two screens with one name is the thing pattern A removes.
This one is those sliders applied to the turn in front of you.

**1. "Why this verdict" — the outcome ladder's working.** On the turn's page, a panel with one
row per rung the ladder took, each timed in **seconds from the sweep's start** — the same clock
as the strip above, so a finger can be put on the sample being talked about. Entry window and
where `entryKn` was read; the sweep's end and the rate that ended it; the low point and how far
past the sweep it was searched; **why the outcome window closed** — recovery at +N s, the
lookahead cap, a recording gap, or the end of the recording; the first off-foil sample; the
longest stop and the floor it was measured against; the pump burst; the wrist-under sample; the
axis crossing with its two angles; what the quiet tail found in its ten seconds; and finally the
two verdicts with the rule that fixed each. Every step is **re-derived** from the same channels
the engine read, with the engine's own primitives, and then compared with the record — and
**where the two disagree the step prints both and is marked in orange**, because that
disagreement is the most informative thing this page can produce. `TurnWorkbenchTests` holds the
other side of that promise: on the 2026-08-07 fixture no step may disagree on any counted turn,
so a mark on Jan's phone means something. Where the stored `config` echo did not carry a field
(several turn parameters were only written down from engine 0.14.0) the published default is
assumed and **named** in its own note rather than guessed at in silence.

**2. The evidence table — one row per sample.** Under the trace, ten seconds before the sweep to
thirty after: `t` on the turn's clock, Doppler kn, the manoeuvre channel kn, heading, turn rate,
TWA where the wind is known, and the four flags the ladder reads — flying, stopped, wrist under,
pump strokes in that second. Monospaced, horizontally scrollable, capped in height, and tinted
by the window each row falls in (entry / sweep / min-lag / outcome / quiet tail), one band per
row with the most specific winning. **Gaps are shown, not closed up**: a row the far side of a
recording hole is marked `⌁`, because every window in the engine stops at one and a table that
hid them would make the ladder's short windows look arbitrary. A share button hands the same
table out as CSV (`<session>-turn<N>.csv`) through the system share sheet — the file and the
screen are the one function, so they cannot say different things.

**3. Ground-truth labels — what the rider says happened.** A three-way control on every counted
turn — *I flew · I touched · I fell*, plus clear — in the first person, because it is his claim
about his own afternoon and not a second opinion about the engine's. A label is **never part of
the analysis**: it lives in the app's own preferences as a small Codable sheet per session
(`turnLabels.v1`, keyed by session id then turn index), so it survives every re-derivation the
engine or the tuning forces, and so the thing being judged cannot see it. **Settings → Tuning →
Labels** scores them against the analyses currently stored: agreement count and percentage, a
confusion table (flew / touched / fell × the engine's verdict, agreement on the diagonal), and
the disagreements listed newest session first, each one a tap from that turn's own page. Labels
that no longer pair — the turn they were left on is not in the current analysis any more — are
**counted and reported**, not silently dropped, so a tuning that dissolves half the corpus is
visible rather than flattering. The page exports the labels as CSV (docs/testing.md,
"Ground-truth labels").

**4. What-if on one turn.** Also on the turn's page, and only where something is actually tuned:
two columns — the verdict, the clean flag, the score, in/low/out and the outcome window under the
**current tuning** against the same six under the **published defaults**. It is not a
re-analysis of the library: the session alone is analysed a second time in memory with default
configs, cached on `DevWorkbench` under the analysis' own stamped `engineVersion` (which already
carries the tuning fingerprint, so a moved slider invalidates the cache for exactly the reason it
makes the library stale). Turns are matched between the two runs by **start time, ±1 s** — index
matching would report the whole rest of a session as changed the moment one extra turn was found.
A turn the default run never found gets no second column and says so: the tuning is what
*discovered* that maneuver, and a column of dashes would read as "the defaults said nothing
happened".

**5. The session's tuning diff.** On the Turns tab, above the map, from the same cached default
analysis: *"Tuned vs default: +3 jibes, −2 clean, 4 verdicts changed"*, printing only the clauses
that are not zero. Expanded, it lists the turns that actually moved — added, removed, verdict
changed, clean changed — in time order, each opening its own page through the tab's existing
`TurnDetailRequest` sheet. A **removed** turn is the one row that cannot be opened, because the
tuned run does not have it; it is inert and labelled `default only` rather than opening whichever
maneuver inherited the index. The whole block is absent when nothing is tuned: with no override
the two runs are the same run, and "nothing changed" on every session would be noise on the one
page that is about maneuvers.

