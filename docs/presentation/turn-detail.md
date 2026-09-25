> Part of `docs/presentation.md`. Engine 0.24.0.

## Turn detail — one maneuver, at the scale of one maneuver

The session map answers "where did I ride". A jibe is thirty metres of water inside two
kilometres of it, and at session scale it is four pixels. **Turn detail** is the drill-in:
tapping a turn's dot on the map (via the callout's "Details" affordance, or the card itself)
or a row in the Turns tab opens a sheet holding that one maneuver.

**The set is every counted turn of the session, in time order, swipeable, with a "3 of 14"
position.** Not the Turns tab's *filtered* set — a filter is a way of looking at the list, not
a claim about which turns exist — and not the course changes either: a bear-away has no
verdict, no score and no entry tack, so the affordance is simply absent on its grey dot
(iOS: `SessionDetail.EventMarker.turnIndex` is nil unless the turn is counted).

**The framing rule.** The drawn window is `[ts − pad, endTs + pad]` with `pad = 8 s`, because
a jibe drawn from its first frame to its last is an arc with no approach and no exit, and the
whole question is what the speed did on either side of it. Geometry is local metres —
equirectangular around the turn's **entry point**, so the entry is the origin — fitted to the
window's own extent, padded by 14 % of the larger side, and never narrower than 20 m. One
scale on both axes; the shape stays honest. The frame is fitted to the turn, so a tight pivot
and a wide arc come out the same width on screen: **a scale bar (10 / 25 / 50 m, the largest
that fits) is mandatory**, and it is the only thing that says which was which.

**Wind up.** The orientation control is `North up | Wind up`. Wind up rotates the frame so the
direction the wind blows **from** points at the top — so a rider running downwind travels
toward the bottom of the page, and a jibe comes down the page, sweeps across and goes back up.
Headings rotate with the points. The wind is the rider's own value first (session dev field 39)
and the engine's estimate second, and **only when the estimate is `usable`** — the same gate
that decides whether turns are named tacks and jibes at all. Below it, wind up is *disabled*
with a footnote saying why; it is never silently drawn north up under a "wind up" label.

**Both references are drawn, in both orientations** (6 Sep 2026). Top right, small, in ink
rather than a hue: a needle labelled `N`, and beside it an arrow labelled `wind` that blows
**from its tail toward its head**. In wind up the wind arrow points straight down the frame
and `N` swings with the rotation; in north up `N` points up the frame and the wind arrow
swings to the direction the wind was going. Before this there was one arrow — north in north
up, the wind in wind up — which made the mark a *label for the control* rather than
information, and answered the question the rider had just asked while hiding the other one.
A jibe is read against both: which way the water was moving, and which way home is. The wind
arrow is **absent, never drawn at a default**, on a session with no wind direction — the same
gate that disables wind up.

**The ink is a speed ramp of its own** (`speed.*` in `design/tokens.json`, five stops,
`TurnSpeedRamp`). The in-turn segment is drawn thick and coloured per vertex:

| speed at the vertex | ramp position | stop |
|---|---|---|
| half the entry speed and below | 0 | `speed.stopped`, the cold end |
| **the turn's entry speed** | **0.5** | **`speed.entry` — the same value as `phase.flying`** |
| 1.3 × entry speed and above | 1 | `speed.fastest`, the hot end (capped) |

The cold end is **half the entry speed, not 0 kn** (Jan, 6 Sep 2026: "not nuanced
enough"). A jibe is ridden between roughly two thirds of its entry speed and the entry
speed, and a ramp that began at 0 kn spent its whole cold half on speeds nobody foils at,
leaving the 8–12 kn a rider actually sees inside one stop. Anchored at half the entry, the
low point of a 66 % jibe sits a full stop below the entry colour and an 81 % jibe's visibly
above it; below half the entry speed the rider is off the foil and the line stays cold.

The anchor is *this turn's* entry speed, which is the number the score is a ratio of — never
the fastest vertex, which would give every turn its own scale and make two jibes
incomparable. The middle stop is deliberately the flying teal, so "he held the speed he came
in with" is drawn in the ink the app already means flying with; the stops either side of it
are clear of the outcome ladder's inks and of the clean-jibe mint, since both are drawn on
this same picture. The stroke still thickens with the cold half of the ramp, so the line
reads without colour. Until 6 Sep 2026 the line was mixed between the off-foil grey and the
flying teal, which could say only "more teal than grey" and drew a turn *accelerated* through
exactly like one that merely held its speed.

**A legend says what the colours are worth**: a small horizontal gradient bar at the foot of
the map card, beside the scale bar, labelled with the cold end (half the entry speed), the
entry speed at its own tick, and the top of the bar in kn. The top is the fastest the rider actually went through this turn,
capped at the ramp's own 1.3 × entry; a turn that never beat its entry speed ends the bar
there and prints two labels rather than three, because the top half of the ramp went unused
and a number nobody rode would be an overclaim.

The padded context track is the off-foil grey at low opacity. Ticks one second apart run
across the line, so the drawing carries time as well as shape. The low point is a hollow
ring; the end of the sweep is the outcome dot in the ladder's ink (`outcome.*`).

**A number every five seconds, on the outside of the curve** (7 Sep 2026). The second ticks
carry *rhythm* — bunched ticks are a rider who stopped — but they cannot carry *position*, and
a reader looking at the strip's "low at 4.2 s" had to count ticks along the arc to find where
on the water that was. On a turn whose ticks bunch exactly where he is counting, that is the
one stretch the counting fails on. So every fifth second of the turn's own clock is printed
small beside the line: `−5`, `5`, `10`. Five, because closer crowds a six-second jibe and
wider leaves a short turn with none at all. **Across the whole drawn span**, unlike the second
ticks, which stop at the sweep: the pads are where the approach and the run-out are, and `−5`
is exactly as much of an answer as `5` to a rider asking where he was before it started. The
sign is kept, and `0` is skipped — the sweep's start already carries three marks and a fourth
saying so would be noise. The number sits on the **outside** of the curve, the side away from
the centre of rotation, so it never lands inside the arc where the ring, the outcome dot and
the ghost are; where the sweep's own rate cannot say which side that is, it goes to the right
of the heading, which is a choice and not a claim. Two patches are reserved and skipped: the
north/wind block top right, and the strip along the foot carrying the scale bar and the ramp.
A number that would print over the `axis` word is skipped too — one unreadable mark is better
than two.

**Tapping the drawing picks the nearest sample.** The drawing had been readable since it was
built and *inert* since it was built: everything on it was something the page had decided to
mark, and the rider's own question — "what was I doing **there**, at the top of the arc" — had
no answer. A tap now picks the nearest recorded vertex within a fingertip of it (about 26 pt,
converted to metres through the frame's own scale, so the tolerance is right at every zoom),
and prints four readings in a small slab top left: **t relative, speed in kn, heading °, and
TWA ° where the wind is known** — the same gate that enables wind up. Nearest *vertex*, never
an interpolation: the callout names one sample that exists, and a position invented between
two would put a real-looking time on a reading nobody took. A tap on open water is outside the
tolerance and picks nothing, which is what lets a reader dismiss it.

Heading is read off the **north-up** vertex even while the wind-up frame is drawn: the
rotation has already subtracted the wind from those headings, so printing one there would say
the TWA twice under two names.

**And the tap moves the shared playhead.** It writes `playheadRt`, which is the same value a
finger on any strip writes — so the drawing's dot, the speed strip's rule and (in the dev
build) the heading and barometer strips' rules are one instant, whichever surface the reader
touched. That is the app's one-playhead rule ("Scrub and zoom"), and the drawing was the last
place it did not hold. The callout therefore appears for a scrub as well as for a tap: two
fingers asking the same question deserve the same answer. It is a **tap** and not a drag,
which the first version was: both detail pages live in a paging `TabView`, and a
zero-distance drag over the drawing swallowed the swipe to the next turn *and* fired as the
pager settled, opening a page with a playhead nobody had asked for.

**The axis crossing is a tick, not a dot** (engine 0.15.0). Jan's definition of a jibe is "a
turn through the wind axis", and the engine now records *when* it went through (`axisTs`). The
drawing marks that instant with a longer tick across the line — twice the length of the second
ticks, drawn perpendicular to the heading like them — labelled `axis` just off its outboard
end. Deliberately **not** a third dot: the drawing spends its two dots on the two things that
happened to the rider (the hollow ring at the low point, the filled outcome dot at the end),
and a third would read as a third verdict. The crossing is not a verdict; it is the instant the
maneuver is *named* by. It is drawn in the same ink as the `N` and `wind` references top right
rather than in a hue of its own, because it belongs to the wind and not to the speed ramp the
line is coloured with. Absent — silently, like the wind arrow — where the engine recorded no
crossing: a course change, a session with no usable wind, or an analysis stored before 0.15.0.

**The ghost.** One comparison turn may be laid underneath, dashed, in the clean-jibe ink
(`clean.jibe`) at low opacity, behind a remembered toggle. The selection rule is exact:

> the **highest-`score`** **clean** jibe of the **same session** with the **same `direction`**
> (rotation, not entry tack) as the turn being read — **never the turn itself**. Ties go to
> the earlier turn.

Same session, because a comparison against different wind is not a comparison. Same rotation,
because a jibe spun to starboard and one spun to port are mirror images. **Clean** (engine
0.12.0), because the model has to be a turn that worked — which now means it flew through
*and* carried its speed, where before it only had to fly through. Never itself, because a
dashed line exactly under the solid one reads as a rendering bug. No such turn ⇒ no ghost,
and the toggle says so — including on a session where no jibe was clean, which is a true
answer and not a missing feature.
Both slices are anchored at their own entry points and at their own `t = 0`, so the comparison
is aligned in space and in time by construction rather than by a transform.

**The strip.** Speed against seconds from the turn's start, over the same padded window, with
the sweep shaded, rule marks and labels at entry / low / exit, and the ghost's speed as a faint
dashed line aligned at `t = 0`. A drag scrubs it and drives the playhead dot on the drawing —
the same **one playhead** rule the map and the chart follow ("Scrub and zoom").

**Where the marks sit, and what the bands mean** (6 Sep 2026). `entryKn` is the engine's
*maximum over the entry window* (`entrySpeedWindowS` before the sweep), not the sample at
`ts` — most riders have begun to slow before the heading starts to move — so the "in" mark
sits at the sample in that window nearest the value, not at 0 s, where it floated above the
line. The shaded band is the **sweep**: it ends when the heading stops changing, which is
usually a second or two before the speed comes back. The **recovery** — from the sweep's end
to the first sample back at `turnRecoverPct` of the entry speed, the engine's own "flying
again" threshold — is shaded lighter behind it, so the band's early end reads as "the turn
was done" rather than "the drawing stopped short".

**Every window, drawn and named** (7 Sep 2026). Jan, reading a fall the engine had called a
touchdown: "It's not clear when the jibe starts and ends, and what extended windows we look
at and why. That should be clearly defined and indicated on the chart." So the strip now
carries a small word under each band it reads from, and the footnote says how long each is,
with the values in force from `TurnConfig` rather than prose that could drift:

| band | span | what the engine reads there |
|---|---|---|
| `entry` | `−entrySpeedWindowS … 0` | `entryKn` is the maximum; "in" sits at that sample |
| `sweep` | `0 … endTs` | the heading's turn; `exitKn` is the sample at its end |
| (no band) | `… endTs + minSpeedLagS` | `minKn` is searched to here, so "low" may sit *after* "out" — the footnote says so |
| `outcome` | `endTs … endTs + outcomeLookaheadS` | stop, recovery and the verdict |
| lighter, inside `outcome` | `endTs … recoverRt` | the recovery: where the speed was back at `turnRecoverPct` |
| `quiet` (a dashed rule, no band) | `endTs + turnCleanQuietS` | the clean jibe's quiet tail (engine 0.17.0) — the last instant a touchdown or a fall still costs this jibe its star |

The `quiet` rule is drawn **only where it fits inside the drawn window**, which at the default
10 s against the drawing's own 8 s of run-out means usually not at all: a rule clipped off the
right edge is a mark nobody can read, and widening the frame for it would redraw every turn to
make room for a line most turns do not need. (The dev build's run-out slider is exactly how it
is made to fit — see "Dev strips and window" under "Tuning" — and the rule that decides is
unchanged: it is drawn when it lands inside whatever span the window is currently cut to.) Its caption steps aside where it would print over
the `outcome` band's word. Either way the footnote carries the number, in one sentence: *"A
clean jibe also needs N s after the sweep with no touchdown, fall or wrist under."*

**The `outcome` band draws the 12 s cap, which since engine 0.24.0 is not always the whole
tail.** `turnOutcomeLookaheadNotRecovered` follows a rider who never got going again for up to
30 s (docs/algorithms.md, "Turn outcome" step 0), so on such a turn the verdict was read from
more seconds than the band covers. The band is left where it is on purpose: the drawn window
is 8 s of run-out by default and a 30 s band would be clipped on every turn that has one,
while the lighter recovery band inside it already shows where the tail actually closed. The
turn's own `outcomeWindowS` is the field that says how long it really was, and the dev
workbench's trace prints it with the reason (*"Still not flying again. The cap for that ran
out"*). **Known deviation, not a decision to keep**: the honest version draws each turn's own
`outcomeWindowS`, on the web and on the phone together, and is worth doing when the run-out
default is next revisited.

The strip carries one more rule, dashed and captioned `axis`, at `axisTs − ts` — the same
crossing the drawing ticks. It has **no dot**: the other three rules each mark a speed the
score is made of, and a fourth point on the trace would claim the crossing was a fourth
reading. It is an instant, so it gets a line. The crossing sits inside the sweep by
construction and therefore lands near "low" on most jibes, so the caption is **lifted onto a
line of its own** when it comes within `captionGapS` of a caption already on the top edge —
lifted rather than dropped, which is where "low" and "out" go when they collide, because the
bottom edge is not free: the three window bands print their own words there and the crossing is
inside the `sweep` band, so sending "axis" down would trade one overprint for another.

The `TurnSlice` used to clamp `minRt` to the sweep's end, which drew "low" at the sweep's
last sample whenever the true minimum came a moment later — the "low 5.4 while out 8.2"
that looked like a contradiction on Jibe 23. It clamps to `endTs + minSpeedLagS` now.

**One channel, one set of numbers.** The numbers row prints the *engine's* `entryKn`,
`minKn`, `exitKn`, `score`, `stoppedS`, `offFoilS`, `radiusM`, `netDeg`, `side`, `direction`
and `outcome` — those are the verdict and nothing may re-derive them. The strip draws **the
maneuver channel the verdict was scored on** (`CleanSample.hybridMps`, position-derived; see
`speedChannelManeuvers` in docs/algorithms.md), not the FIT's Doppler speed, and its three
markers are `entryKn` at `ts`, `minKn` at `minTs` and `exitKn` at `endTs` straight from the
record — so they sit on the drawn line by construction and print the same digits as the row.
Until 6 Sep 2026 the strip drew Doppler and read its markers off that window's samples, with
a footnote allowing "a tenth"; Jan's phone showed 10.7 / 9.4 / 9.6 over a row saying
12.2 / 8.1 / 10.1, because device Doppler is smoothed through a turn and understates the low
point by more than a knot. The footnote now says which channel this is and why the records
page reads differently. Score is spelled "held 71 % of entry speed"; `direction` is spelled
"clockwise / counter-clockwise" and never "port/starboard", which is the entry tack's word
("Filter semantics").

**The crossing, in numbers.** Under the grid, one row and not two cells:
`Through the axis · 87° before, 72° after` — the engine's `axisBeforeDeg` and `axisAfterDeg`
as integers (docs/algorithms/turns.md, "The crossing, as an event"). One row because the two angles
are a single fact read either side of a single instant; two cells in the grid above would
invite a reader to compare them with the speeds. **Absent, never zeroed**, on a turn the engine
gave no crossing: "he started on the axis" and "nobody knows where the axis was" are different
sentences and only the second is ever true here. The footnote gains one sentence saying what
the tick is.

**The chips under the numbers**, in order: the outcome, `clean` where the engine says so —
or, since 0.17.0, **why not** where the engine says that instead — `pumped out` where
`pumped`, `wrist under` where `submerged`.

- **"not clean · …" is the chip that explains a missing star.** A jibe that flew through and
  held its speed and is still not clean used to leave the page saying "flew through" and
  nothing else, with the star simply absent — which reads as a bug, not a verdict. The chip
  reads the engine's `cleanBlockedBy` and says it in rider words, in the neutral ink with a
  crossed-star glyph (never the clean mint: it is the absence of that verdict, not a weaker
  one). The `clean` chip's own rule is untouched — it reads the engine's flag and only it, so
  the two can never both appear.

  | `cleanBlockedBy` | chip |
  |---|---|
  | `quiet_flight_end` | `not clean · touched down 6 s after` — the seconds come from the flight end the engine's own rule found, and where the stored document carries none the chip says `not clean · touched down after` rather than inventing a number |
  | `quiet_off_foil` | `not clean · off the foil after` |
  | `quiet_submerged` | `not clean · wrist under after` |
  | `axis_after` | `not clean · carried 18° past the axis` — the engine's `axisAfterDeg`, an integer; `not clean · short of the axis` where the crossing was not measured |

  Nothing is said on a jibe the **outcome** or the **score** already refused: those the page
  prints in its own words two rows up ("touched down", "held 61 % of entry speed"), and the
  engine writes no reason for them either.

- **"pumped out" carries the count**: `pumped out · 7 strokes`, and `1 stroke` in the
  singular. The number is the engine's — the sum of `strokes` over the pump episodes whose
  `turnIndex` is this turn's (`PumpEpisodeRecord`, engine 0.3.0); where no episode names the
  turn, the ones overlapping the window the outcome was judged on
  (`ts … endTs + outcomeWindowS`), because an older stored analysis can carry `pumped`
  without the assignment. Nothing found ⇒ the chip reads `pumped out` and nothing else:
  "0 strokes" would be a claim where there is only an absence ("Formatter rules"). The same
  count, in the same words, is the one number the `pumpedOut` rung of the coach line adds —
  which is what keeps the ladder's rule that it never prints a number the page is not
  already showing. iOS: `TurnAnalytics.pumpStrokes`, pinned by `TurnSpeedRampTests`.

  Since engine 0.18.0 the chip is *only* an effort chip: pumping no longer moves the verdict
  (docs/algorithms.md, step 3), so a jibe can wear `pumped out · 7 strokes` and `flew through`
  at once. That pairing is the truth — he worked for it and he rode it out.

### Why it ended that way — the line under the chips (engine ≥ 0.18.0)

Jan, 7 Sep 2026: *"Can we add a short comment for the user why a jibe is a touchdown or a
fall?"* The numbers were all on the page — stopped, off foil, wrist under — and the rider was
left to assemble the verdict out of them. One short line, directly under the chip row, says
which rung of the ladder decided.

The engine writes a **code** (`turn.outcomeReason`; docs/algorithms/pumping.md, "Why") and the words
are chosen here, once, for both platforms — `TurnAnalytics.outcomeText` on the phone,
`outcomeText` in `web/js/viz.js` for the site. Two apps wording the same fact differently is
how a rider learns to trust one of them, so the strings are held together from the outside:
`verify_presentation.py` §6 re-derives every sentence in Python and compares it with what the
JavaScript actually produces, over every turn of every fixture, plus the shapes the corpus
cannot supply.

| `outcomeReason` | line |
|---|---|
| `off_foil` | `touchdown · off the foil 2 s, stopped 1 s` — and `…, no stop` where the stop rounds below a second, never `stopped 0 s`, which would be a measurement where there is none |
| `stop` (touchdown) | `touchdown · stopped 4 s, borderline` — the band between `turnTouchdownMaxStop` and `turnFallStop`, named as the near-fall it is |
| `stop` (fall) | `fell in · stopped 7 s` |
| `submerged` | `fell in · wrist under` — the wrist wins the wording wherever it decided, even when a long stop sits beside it |
| `pumped_marginal` | `touchdown · pumped out below 4.3 kn, no sample off the foil` — the knots are `turnPumpedMarginalSpeed` from the **document's own** config echo, converted, never a literal; a run that revived the rung at 12 km/h says `below 6.5 kn`, and without an echo the line says `below min foil speed`. Unreachable at the published defaults since 0.18.0, and kept because a stored document from an older engine still carries it and because the speed can be raised |
| **null** | nothing is printed. A fly-through needs no explanation, and neither does a document written before 0.18.0 — a sentence rebuilt from `stoppedS` alone would be a guess about a ladder that may not have been climbed that way |

Seconds are whole and rounded **away from zero**, spelled out in all three languages rather
than left to each one's default formatter: `%.0f` prints 4.5 as "4" and `toFixed(0)` prints it
as "5", and a stop of exactly 4.5 s is an ordinary reading at 1 Hz.

**The aborted turn says nothing extra, on purpose** (engine 0.21.0, docs/algorithms/turns.md, "The
aborted turn"). A turn the rider fell out of halfway round now appears in the turns list like
any other tack or jibe that fell in, and it wears the same chips and the same line — `fell in ·
wrist under`, `fell in · stopped 7 s` — because that is what happened, and the ladder that
decided is the same ladder. The engine carries a `turn.aborted` flag beside it and **no surface
says a word about it**: it is there so that a later sheet can tell *he fell in the turn* from *he
turned and later fell* without re-deriving anything, and adding a word to the page before Jan has
asked for one would be a second vocabulary for one verdict. The one thing the flag drives is a
*filter*: the web session legend has an `aborted` chip beside its `jibes` and `tacks` ones
(docs/screens.md, deviation 20), which hides those turns rather than labelling them, and it
changes no verdict, no count and no caption. The rider-visible change is that the turn
is *there at all*, with its marker on the map and its row in the table, where before there was a
grey course change or nothing.

**Where it appears.** The phone's turn page, under the chips. The web session page in two
places — the map callout's `why` row and the `why` column of the turns table — both from the
one function. The coach line (`TurnCoach`) is unchanged: it speaks about what to do next, and
a rung that already has a sentence of its own does not need a second one.

**The coach line.** One calm sentence under the numbers, in the `ReplayCommentary` voice —
plain, no exclamation marks, never blaming, and never a number the page is not already showing.
It is a ladder of specificity, first match wins, and the ordering is the contract:

| # | rung | fires when | says |
|---|---|---|---|
| 1 | `fellInFast` | `fell_in && success && score ≥ 0.85` | the speed was there right round, and it still ended in the water |
| 2 | `fellIn` | `outcome == fell_in` | ended in the water, entry → low |
| 3 | `wristUnder` | `submerged` | the barometer saw the wrist go under, entry → low |
| 4 | `pumpedOut` | `pumped` | pumped back out, with the stroke count and `offFoilS` when there is one of each |
| 5 | `touchdownOnExit` | touchdown, low point **at or after** halfway | held it in, lost it after |
| 6 | `touchdownComingIn` | touchdown, low point **before** halfway | the speed was already gone going in |
| 7 | `quietFlightEnd` | `cleanBlockedBy == quiet_flight_end` | you rode the turn, the foil went a few seconds later |
| 8 | `quietOffFoil` | `cleanBlockedBy == quiet_off_foil` | the turn was there, the seconds after it were not |
| 9 | `quietSubmerged` | `cleanBlockedBy == quiet_submerged` | came through carrying it, wrist under just after |
| 10 | `axisAfter` | `cleanBlockedBy == axis_after` | held the speed, did not come far enough past the axis |
| 11 | `cleanAndFast` | `success && score ≥ 0.85` | clean, and barely slowed |
| 12 | `cleanButSlow` | `flew_through && score < 0.7` | flew through, and it cost |
| 13 | `slowedEarly` | low point before halfway | the speed went before the mid-point |
| 14 | `slowedLate` | low point at or after halfway | carried it in, lost it on the way out |
| 15 | `plain` | nothing above, or no usable geometry | the three numbers, said plainly |

Rungs 1 and 11 are the same score test read from the two sides of the outcome, which is what
keeps `cleanAndFast` honest without a `clean` clause of its own: every fall and every
touchdown has been taken by a rung above it, so by the time the ladder reaches it the turn
flew through, and for a jibe that is exactly `clean` (engine 0.12.0).

**Rungs 7–10 exist because that stopped being true in 0.17.0.** A jibe the quiet tail or the
axis gate refused *did* fly through and *did* hold its speed, so `cleanAndFast` would have
called it clean and said so out loud, one line under a chip saying it was not. They sit
immediately above it, in the order the engine settles the reason in, and each says the one
thing the rider could not see. `fellInFast` exists
because that turn — the speed held all the way round, the foil gone in the recovery tail —
is the one the old rule called clean, and the one sentence that must say both things.

"Halfway" is where the sweep has turned through **half its cumulative heading change** — not
half its `netDeg`, because a sweep that overshoots and comes back has swept more than its net,
and not half its duration. A jibe's halfway point is called the **downwind point**, a tack's
**head-to-wind**, and an unnamed sweep's the **middle of the turn**. Rules 4/5 and 8/9 need it;
where the window has too few usable bearings to say, no rule that depends on it may fire and
the ladder falls through to `plain`.

iOS: `TurnSlice` + `TurnCoach` + `TurnSpeedRamp` in the kit (pure, `TurnSliceTests` /
`TurnSpeedRampTests` / `ManeuverSliceTests`), drawn by `TurnDetailView` / `TurnDetailMapView` /
`TurnDetailStripView`. The geometry the drawing needs is a `ManeuverFigure`, which the
flight-end slice also exposes, so one `Canvas` draws both events and neither knows which it
got ("Flight-end detail"). The drawing is a SwiftUI
`Canvas` and deliberately not a `MapKit` map: the frame has to rotate, and the ticks must not
move under the reader on a camera settle. There is no ground under it — a satellite tile at
30 m across is a photograph of water, and it would bury all six of the things the drawing says.

## Flight-end detail — the same page, for the losses no turn owns

Roughly half a session's losses do not happen in a maneuver. A gust dies, the foil ventilates,
a tip catches on a reach; the engine has classified every one of those since it started
carrying `flightEnds` (docs/algorithms/pumping.md, "Flight-end outcome"), and the map has drawn each
as a hollow ring for as long. The ring was the end of the road. Tapping it said "Fell in ·
straight-line · stopped 7 s" and there was nowhere further to go, while a jibe that ended in
exactly the same swim got a drawing, a strip, six numbers and a sentence — for no better
reason than that a turn detector had happened to fire.

**So a flight end gets the same page** (7 Sep 2026), built from the same parts: the same
`Canvas`, through a shared `ManeuverFigure` that both slices expose; the same strip furniture
(`StripChrome`); the same footnote voice. What differs is what genuinely differs.

**The set is every *drawn* flight end**, in time order, swipeable, with a "3 of 9" position —
the ones no turn owns and the recording did not truncate, which is `drawnFlightEnds` read
positionally (`FlightEndAnalytics.drawnIndices`). A turn-owned end is the same swim already
counted at its jibe and reachable on its turn's page; a truncated one is a recording that
stopped, and has no evidence to judge. Both exclusions are said once, under the list.

**A flight end is an instant, not a sweep**, and the page never pretends otherwise:

| turn detail | flight-end detail |
|---|---|
| `t = 0` is the start of the sweep; the drawn window is `[ts − pad, endTs + pad]` | `t = 0` **is the end**; the window is `[−pad, +pad]` around it |
| the thick, speed-coloured part is the sweep | the thick part is the **flight**: everything at or after the end is already off the foil |
| entry / sweep / outcome / quiet bands | **entry** (`entrySpeedWindow`, the speed the flight was ending at), **outcome** (`outcomeLookahead`), and a rule at **evidence** |
| the `axis` tick and its two angles | **absent, never zeroed** — a flight end is not a maneuver and the engine records no crossing for one |
| the ghost, the score, the entry tack, the rotation | none of them exist for a straight-line end |
| all three of in / low / out are the engine's | **only `low` is** — see below |

**`evidence` is a rule, not a band**, because it is a property of the *recording* rather than
of the configuration: how much gap-free record there actually was past the end (`windowS`). It
is a limit on what could be known, and the one window on the page that a tuning slider cannot
move. Its caption steps aside where it would print over the `outcome` band's word — the same
"only when it fits" rule the turn strip's `quiet` mark follows.

**One number is the engine's and two are the picture's, and the footnote says so.** A
`FlightEndRecord` carries `minKn` and no entry or exit speed at all, so there is nothing to
print for the other two. `low` is the engine's `minKn`, placed at the sample of the drawn
window nearest that value — the same trick the turn strip uses for its `in` mark. `in` is the
**maximum of the drawn channel over the entry window**, which is the rule the classifier's own
recovery threshold is built from, applied to the channel this strip draws. `out` is where that
channel came back to `turnRecoverPct` of it, and is **absent, not zero**, where it never did —
which is exactly what a fall looks like, and the line under the numbers says "Never back up to
flying speed inside the window" rather than printing a dash and leaving it.

**The numbers, the chips and the reason line.** Stopped, off foil, the flight's own number and
the evidence seconds; then the outcome chip in the ladder's ink (`glided out` / `touchdown` /
`fell in` — **never** the turn ladder's "flew through", which a flight end cannot earn, since
by the time there is one the rider is off the foil by definition), `pumped out` and `wrist
under` where the record says so. Under them, one line in the turn page's voice:
`fell in · stopped 7 s · wrist under`, composed by `FlightEndAnalytics.outcomeText` from the
record's own fields. Off-foil seconds are printed **only where there is no stop to print**: a
rider who stopped was off the foil too, and saying both says one loss twice. A stop under a
second is not printed at all — at 1 Hz that is one sample, and "0 s" would read as a
measurement. A `truncated` end says the one true thing about itself, "the recording ended, not
the flight", instead of a verdict it does not have.

**Two ways in, one set.** The ride map's hollow-ring callout grows the same "Details ›"
affordance a turn's dot has (`EventMarker.flightEndIndex`, carried rather than looked up by
timestamp, because two flights can end in the same second of a gappy import); and the **Details**
tab carries a "Flight ends" card listing them, each row opening the same page. Details rather than
Ride or Turns on purpose: Ride is the map, Turns is the maneuvers, and a straight-line flight
end is neither — it is what the *record* says happened when the foil stopped carrying, which
is the question that tab exists to answer. On a session with no drawn ends the card is absent
rather than empty.

iOS: `FlightEndSlice` + `FlightEndAnalytics` in the kit (pure, `ManeuverSliceTests`), drawn by
`FlightEndDetailView` through `TurnDetailMapView` and `StripChrome`. Screenshot hook:
`UI_OPEN_FLIGHT_END=<index>`, which selects the Flights tab first (the flight list moved
there from Details on 25 Sep 2026) — a sheet attached to an
unselected tab's subtree never appears.

