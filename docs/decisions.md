# Decision Log (ADR-style)

Newest first. One paragraph each: context → decision → consequence.

Every entry opens with a **Status** line, because a decision log whose entries cannot be told
apart is a history, not a contract. There are four:

- **Accepted** — still true, and still the way the code works.
- **Proposed** — written down, not yet Jan's decision.
- **Superseded by ADR-N** — a later ADR replaced it. The entry stays, because the reasoning
  is why the replacement is shaped the way it is.
- **Retired** — the thing it decided is gone, and no ADR replaced it.

An Accepted entry may carry a clause saying what a later ADR narrowed or what has moved since.
That is the point of the line: it says which half of an old paragraph is still load-bearing.

## ADR-033 · One presentation document — the engine emits every rider-facing fact once
**Status: Accepted** (Jan, 22 September 2026; `presentationVersion` 1, no engine bump).

Five surfaces draw one session — the iPhone, the web analyzer, the share card, the
home-screen widgets and the watch's summary card — and each of them computed the block, the
tally, the record set and the wrist-under callout **for itself**, in Swift, JavaScript,
Python and Monkey C. Nothing structural held them together. What held them together was
`web/tools/verify_presentation.py`, which re-derives every one of those facts a *third* time
so the other two can be checked against a rule rather than against each other — 1 653
assertions, and they pass. That verifier is why the surfaces agree today, and it is also the
diagnosis: a fact that needs a third implementation to stay true is a fact with no owner.
The failures it caught are the ones you would predict — a card and the block a tap away
naming different numbers for one afternoon, one metric with five spellings across four
surfaces, a tally that reported one fall on a day with three in it.

**The engine emits the facts once, as a document, and every surface becomes a renderer.**
`build_presentation` in the lab (authoritative) and `PresentationDocument.build` in the kit
produce the same JSON byte for byte, pinned per fixture in
`fixtures/presentation/*.expected.json`. Its three rules are what make it a contract rather
than a second rendering: **no rider sentence** (every word is an id into `docs/copy` plus
the arguments it interpolates), **no formatted number** (a raw value and a `unitKind` — the
speed unit is deliberately *not* an input, which is how one document serves a rider reading
knots and a rider reading km/h), and **no colour value** (a role, a path into
`design/tokens.json`). The rider's speed-record *policy* **is** an input, as an argument,
because it decides which records may stand at all. `docs/presentation/document.md` is the
schema, the list of what a renderer may still decide, and a table answering every section of
the verifier: carried and where, or renderer-only and why.

**Three rounds, and only the first is done.** Round 1 defines the document, produces it on
both platforms and pins it — **no renderer switched and no verifier was retired**. Round 2
grows the two things the analysis alone cannot say: the session clock and its
trust note (`meta.utcOffsetSource`), and the outcome sentence behind
`outcomeReasonId` / `cleanBlockedById`, plus raw values for the divergence banner, which
holds pre-formatted strings today. Round 3 switches the renderers and retires the verifier
sections the table marks as carried.

A renderer keeps everything that is a decision rather than a fact: formatting, layout,
Dynamic Type, ordering within a row that depends on width, interaction, the card's picture,
and the rider's own title and caption — which are the sender talking to the receiver and are
never facts about the session. The cost is a golden per fixture that grew from ~2 KB to
~40 KB; that is the contract being written down instead of assumed, and it is the same trade
`fixtures/goldens` already makes for the engine.

## ADR-032 · A fall the turn caused is the turn's fall
**Status: Accepted** (Jan, 22 September 2026; engine 0.24.0, release channel).

A tester's fenix recordings, Smart Recording. A learner does not fall out of a jibe, he
**mushes out of it**: the foil stops carrying, he keeps coasting at two or three metres a
second, and a quarter of a minute later he is sitting on his board. The engine judged the
outcome over `turnOutcomeLookahead` — 12 s past the sweep — and the stop on those recordings
begins a **median 12 s** after it. Exactly at the cap. So the ladder saw the loss of foil but
not the standstill, called the turn a `touchdown`, and the *same event* was booked a second
time: as a straight-line `fell_in` where the flight end landed past the turn's ownership
window, and as **nothing at all** where it landed inside one — the flight-end channel gave the
fall to the turn, and the turn denied it.

The cap is not wrong, it is **modelling the wrong rider**. Twelve seconds is how long a foil
takes to bleed from foiling speed to a standstill; it is not how long a rider takes to coast to
one. Three shapes were weighed.

| | shape | what it costs |
|---|---|---|
| **a** | raise `turnOutcomeLookahead` to 30 s for everyone | a jibe the rider *powers* out of would be on the hook for half a minute again. This is the 60 s window engine 0.13.0 removed, and it is what "a mush-out three quarters of a minute past the exit was charged to the turn" already says |
| **b** | keep the cap, and let the flight-end channel keep the fall | leaves the verdict on the maneuver wrong. The rider reads *touchdown* on a jibe he swam out of, and the two channels disagree about one event in the same document |
| **c** | **follow the rider while he has not recovered**, to 30 s | the tail lengthens only where there is nothing to close it |

Decision: **(c)**. `turnOutcomeLookaheadNotRecovered` = **30 s**. The outcome tail follows a
rider who has **not recovered** — recovery unchanged: Doppler back above `turnRecoverPct` of
the entry speed, floored at `foilEntrySpeed`, held `turnRecoverHold` — for up to 30 s, and
`turnOutcomeWindow` rises with it, so the fall is booked **once**: as the turn's outcome, never
also as a straight-line fall.

**30 s, and not more, is measured.** For a touchdown turn whose rider never recovered before
stopping, the stop begins within 30 s in **78 of 85** corpus cases, and in 17 of 17 on the
tester's own. The seven beyond it begin at 33–93 s — drift, and then a stop, which is not the
turn's fall.

**The not-recovered condition is defined once and shared** (`evidence.outcome_tail`, read by
`turns.py` and `flightend.py` and by the Swift twins of both): *no recovery at any point
between `turnEnd` and the stop*, equivalently a tail that ran past `turnOutcomeLookahead` with
neither a recovery nor a gap to close it. Two implementations of one condition is how two
channels start disagreeing again, which is the whole shape of the bug (pattern L). A
**recording gap still ends the measurement** exactly as before, and reports "recovered" for the
purpose of the cap: a hole is not evidence that the rider failed to get going again, it is no
evidence at all. The **12 s cap stays** for everything else the tail is used for — `axisAfterDeg`
is still measured to `turnEnd + turnOutcomeLookahead`, and the scored window never read the tail.

**Consequence, on the 21 committed goldens.** Turn `touchdown` 213 → 132, turn `fell_in`
85 → 188, straight-line falls 90 → 80, counted turns 597 → 615 (the aborted-turn pass keeps a
sweep only where the ladder says `fell_in`, ADR-028). Clean jibes 158 → **157**. **The
flight-end channel does not move by one verdict** — 277 falls before and after — and WPH is
unchanged on every fixture, which is what says no fall was invented. Total falls rise 175 → 268
because the corpus was **under-counting** them: falls the two channels between them lost — a
flight end the engine called `fell_in`, owned by a turn that denied it — fall **110 → 18**. Of
the 96 turns that go `touchdown` → `fell_in`, 89 own a flight end that already read `fell_in`.
JPH falls with the dry jibes; the one clean jibe that moves exits at 8.6 kn, never gets back
above `foilEntrySpeed`, stops for 16 s and ends in a 29 s swim.

**No turn the rider recovered from can move**, by construction: recovery closes the tail at the
same sample whichever cap is in force. On the corpus 375 turns recover inside the lookahead and
none changed verdict, and setting `turnOutcomeLookaheadNotRecovered` equal to
`turnOutcomeLookahead` reproduces 0.23.0's goldens byte for byte — which is how the before
column of the table in algorithms.md was measured.

**Not ported to the watch**, and the divergence is written down (algorithms.md, "Watch
approximation"). `LOOKAHEAD_S` there is an unconditional 12 s, so the live verdict on a
mush-out is `touchdown` where the phone says `fell_in`. The watch has no second ladder to
disagree with — nothing on the wrist books a straight-line fall — the live detector would have
to hold a maneuver open for half a minute of samples, and the phone re-derives the session from
the FIT anyway. The data field stays parked (ADR-020).

## ADR-031 · The wrist stream is **windowed 25 Hz**, not decimated and not summarised
**Status: Proposed** (dev channel; docs/channels.md, all four rules unmet).

ADR-027 built the direct transfer and left the wrist magnitudes for later, because the
recording alone is 97 KB and the accelerometer is two orders more. Jan's call of 19 September
2026 was *"send it later, not first"* — so the question is not whether the wrist stream
rides, it is **what of it rides**, and the constraint is memory rather than radio time.

**The arithmetic.** Two hours at 25 Hz is 180 000 samples; a byte each after delta coding is
**about 180 KB**, held in RAM for the whole session because a Connect IQ app cannot read back
what it recorded (ADR-027) and `Application.Storage` is ~100 KB for the whole app. The two
binding watches are the **fr255** (507.7 kB total, ~119 kB of it already the app) and the
**fenix 5 Plus family** (1275.4 kB, ~155 kB), and the record stream is already holding up to
97 KB of its own until the phone says it is whole. 180 KB fits nowhere.

Three bounded forms were weighed.

| | form | 2 h | what it serves |
|---|---|---|---|
| **a** | decimated magnitude, 5 Hz | 36 KB | **nothing.** `pumpResampleHz` is 25 and the band ends at **2.5 Hz**, which is exactly 5 Hz's Nyquist. The lab's own 51-tap band-pass cannot run on it, so this is not the pump channel at a lower rate — it is a different algorithm, and three implementations of one engine would become four |
| **b** | per-second features (mean, max, min) | 21 KB | **no reader.** Nothing in `pump.py`, `takeoff.py` or the kit consumes a per-second envelope. A channel whose only reader is its own test is a number on a wire (pattern L) |
| **c** | **25 Hz inside flagged windows** | budgeted | the lab's chain, **unchanged**. It is the only form that is the same channel the FIT carries, so `PumpAnalyzer` reads it with no new code |

Decision: **(c), with a hard byte budget and no envelope beside it.** The watch flags a window
when the rider is off the foil, a turn window is open, or its own detector picked a stroke in
the last ten seconds — the three states the phone's pump chain has anything to find in — and
writes those stretches at 25 Hz in centi-g, 8-bit deltas where they hold (docs/transfer-format.md
§2b). Cost is about **26 B per covered second**. The budget is **60 000 B**, or 24 000 B under
a 700 KB heap: 38 minutes of covered riding, eight pages, roughly **16 s on the link**. When it
fills, half of what is held is dropped and half of what arrives is skipped, so a long session
is **thinner rather than shorter** — coverage in stripes across the whole afternoon rather than
its first twenty minutes.

Three things make it honest.

* **An uncovered second is a sensor gap, which is a state the engine already has.** The pump
  grid holds empty bins at the mean, marks them `valid = false` and picks no stroke there —
  exactly what a `SensorLogging` hole already is (ADR-030, docs/algorithms.md). So no new
  capability, no new channel and no new letter.
* **Every window carries a second of lead-in and a second of tail** beyond the flagged span.
  That is the 51-tap band-pass's group delay; without it the strokes at a window's edge are
  the ones the phone would miss, and the padding costs 10 %.
* **The class does not move and was never going to.** `sourceClass` is `a` on developer
  fields, `b` on speed, `c` otherwise — `hasAccel` is not one of its inputs, so a direct
  session was already class (a). What the wrist stream buys is the **analysis**: the phone
  runs the lab's chain over real magnitudes instead of reading the watch's live approximation
  off the `pump_cadence` column (ADR-005), and `pumpsToTakeoff`, the failed-attempt count, the
  pump rung of the touchdown ladder and the pump-versus-cruise HR split stop reading nil.

**What it does not serve, stated rather than hoped for.** *Jumps.* docs/algorithms.md is
explicit that the height estimator needs **100 Hz** — at 25 Hz it costs 3–6 % of bias at low
support and collapses above it (s = 0.7: 0–6 % detection). The watch's own listener runs the
25 Hz pump grid and the FIT's 100 Hz stream is `SensorLogging`'s, which the app cannot read
back, so **no wrist stream over this link will ever feed jump heights**. A 100 Hz ring frozen
around flagged jump candidates is the shape that could, and it is a separate decision. *The
wet test* is not a consumer either, and a note in this file's own backlog said it was: it
reads the **barometer** (ADR-029), and the accelerometer feeds none of the outcome ladder's
three rungs on the watch.

**The residual risk, named.** The windows are chosen by the watch, so pumping the watch's live
detector failed to see *while flying and outside a turn* never reaches the phone, and the
phone cannot know it is missing. The cheap fix is (b) after all — a two-byte per-second
peak-to-peak envelope, 14 KB for two hours, as **coverage evidence** rather than as a pump
channel: a second whose peak-to-peak is under `pumpStrokeAmp` cannot contain a stroke. It is
not built, because a channel is added when something reads it. If a field session shows the
windows missing strokes, that is the thing to add and this paragraph is the design.

## ADR-030 · A cadence is not a hole
**Status: Accepted.**

A tester's fenix 5 Plus sessions arrived with three separate faults, and all three were the
engine reading a *device convention* as damage.

**One: Smart Recording.** Garmin writes a sample when the track changes, not on a clock —
1–9 s apart, median 2 s. `filters.clean` called a step a gap when `dt > max(gapMinS 3,
gapFactor 2 × median)`, which on such a track is **4 s**: inside the recorder's own normal
spacing. A native afternoon was therefore cut into 120–650 gap-free segments, and a segment
boundary is a hard break everywhere downstream. Session distance — the per-segment Doppler
trapezoid — ran **11–27 % short** of the file's own `total_distance` on every corpus native
and **21–31 % short** on the tester's four; timer time, the denominator of foil % and of all
four per-hour rates, lost the same fifth of the session; 668 of 825 flight ends across the
eleven Smart Recording fixtures were `unknown`, i.e. truncated by a boundary that was not
there. Decision: **above `smartMedianDtS` (1.5 s) the gap threshold is floored at `smartGapS`
= 10 s**, the same valley `hrMaxSampleGap` already sits in for the same distribution. A long
Smart Recording step *is* a steady reach — which is why the watch skipped samples through it
— so bridging it is physically sound; a 1 Hz track never reaches the floor and does not move
by a digit; a `gap_before` the *source* declared still cuts. One consequence had to come with
it: `maxAccel1Hz` is a 1 Hz value, and `|dv| ≤ 4 × dt` over a newly-judged 7 s step permits
28 m/s, which is exactly what a receiver emits when it reacquires after a hole — so the spike
rule's budget stops growing at `spikeMaxDtS` = 3 s. That half moves **no committed golden**
and drops one sample on one tester file, where it keeps a 23 kn "best 2 s" out of the records.

**Two: an opposed pair of reaches.** `wind.py` refused a lobe separation above
`windMaxLobeSeparation` = 179° as a degenerate bisector. The tester's 1 Hz session has lobes
132.74° / 311.90°, separation 179.16° — so no wind, and therefore not one of its 78 maneuvers
named a tack or a jibe, while the watch's own live estimate said 222° and a weather archive
225°. The bisector is undefined *at* 180° and nowhere else, and even there the wind axis is
simply the perpendicular of the lobe axis with the no-go cone picking its end. Decision:
**replace the refusal with the half-angle construction** `lobe0 + wrap180(lobe1 − lobe0) / 2`,
which is defined at every separation and returns that perpendicular at 180°, and **retire the
parameter**. The doubt rides in `confidence`, which can be read, instead of in a hard `null`.
That session now reads 222.3°, confidence 0.70, and splits 45 tacks / 33 jibes against the
watch's 44 / 32. The construction agrees with the retired circular mean everywhere that mean
was defined, so no corpus session moves by a digit. **The watch is not ported in this change**
and keeps its 179° refusal — a divergence, written down in docs/algorithms.md.

**Three: an accelerometer stream with no clock.** The same watch writes one
`accelerometer_data` batch after each 1 Hz record and stamps every one of 4 312 of them with
a handful of constant `timestamp`s days either side of the session, with `sample_time_offset`
flat at zero. Read literally that is a stream fifty days long starting before the ride: the
lab produced `t = −138 457 s` and NaNs and died in the pump resampler on `int(floor(nan))`;
the kit, whose grid is bounded, silently returned no pump channel at all. Decision: **detect
the shape and time the batches from file order** — each starts at the last `record` before it
and lasts one second, its samples spread evenly across it, monotonic. The stream is condemned
when fewer than half the batch bases fall inside the records' span, or when no batch has any
spread in its offsets; our own recordings pass both outright. The result is good to ±1 s
against GPS, which is ample for a 0.5–2.5 Hz band and not ample for aligning a sample with a
wave — so it is **recorded rather than hidden**, as `capabilities.accelClockReconstructed`,
false on every fixture in the corpus. Separately, the pump grid now drops non-finite samples,
sorts an unsorted stream and refuses a grid past four hours of 25 Hz samples: its length comes
out of a file, and `nil` is the state a source with no accelerometer is already in.

Consequence: engine **0.23.0**. Three config keys join the document (`smartGapS`,
`smartMedianDtS`, `spikeMaxDtS`), one leaves it (`windMaxLobeSeparation`), one capability key
joins (`accelClockReconstructed`). Every Smart Recording golden moves and no 1 Hz golden
moves by a digit; the per-fixture table is in docs/algorithms/hygiene.md, "A cadence is not a hole".
The headline on the eleven Smart Recording fixtures: distance 151.8 → 184.4 km against 184.2
km of FIT session totals, timer time 43 508 → 60 387 s, flights 825 → 346, counted turns
369 → 378, `unknown` flight ends 668 → 37, `fell_in` flight ends 69 → 201, clean jibes
81 → 69. **Foil % falls 5–16 points on those fixtures and that is the correction**: the old
denominator was missing a fifth of the session the rider spent on the water.

## ADR-029 · The wet test reads **the drop, not the level**
**Status: Accepted.**

A tester rode 20 September 2026 on a fenix 5X Plus and the session came back with **33 of his
70 jibes "fell in"** — seven of them jibes he had named as smooth, and every one of them with
its flight running straight on through the swim it was supposed to be. Nothing was broken in
the outcome ladder. `submerged_mask` compared every altitude sample with **one session-wide
median** and called it wet `turnBaroDrop` (25 m) below that. This models Jan's fenix 8
exactly: it drops ~250 m on a dunk and crawls back to the *same* level over minutes, so one
line fits the afternoon. The 5X Plus dunks the same way — −65/−34/−73 m in three consecutive
seconds at 12 km/h, precisely at his falls — and then **re-anchors**. That session's reference
sat at −30, −93, −30, +150, +130, +105, +73, +24, −60, −75 and −190 m in successive stretches,
370 m of wander at sea level, and against a fixed median of −33 m every stretch below −58 m
read "wrist under": 43 of 85 turns flagged wet. The afternoon's weather became the rider's
falls.

Decision: **the mask reads a local, causal baseline instead of the session median.** The
baseline starts at the first finite sample, restarts at every recording gap, and walks towards
each dry sample with a 50 s time constant; a sample is wet when it is `turnBaroDrop` below
*that* line. While a sample reads wet the baseline **holds**, so a swim cannot re-baseline
itself dry — with one release: a level that has held for **20 s within ±5 m** is accepted as
the new baseline, and that sample is dry. *A dunk is a spike; a level is not a dunk.* The
three numbers are **code constants, not tuning parameters** — they describe the altimeter's
slew and its re-anchoring, which is a property of the watch and not a judgement about riding,
and a rider who moved them would be tuning his watch's firmware rather than his session.
`turnBaroDrop` keeps its value and its meaning, one word of it changed: "below the local
baseline" instead of "below the session median". `submerged_reference` is retired, and an
episode's `dropM` is now measured against the baseline in force at its own first wet sample —
the same line the mask crossed to open it, so the two still cannot drift.

Two things this deliberately does **not** do. It does not add a parameter: the tuning page has
no new slider, because there is no riding question here for a rider to have an opinion about.
And it does not weaken the positive-only semantics — a wet sample is still *proof*, the
silence of a dry one still means nothing, and the ladder above it is untouched.

Consequence: engine **0.22.0**, no config key, one retired function, three code constants.
The tester's session: jibes made 20 → 30, jibe outcomes flew/touched/fell 36/1/33 → 63/1/6,
tacks 1/4/10 → 3/5/6, wet turns 43 → 11, and three flight ends the median had **missed** —
dunks taken from a +150 m stretch — are read as falls. On the committed corpus the change is
almost invisible, which is the check that says it is a correction and not a re-tuning: no ciq
or windsurf-native fixture moves by one verdict, and only `2026-08-05-…_foilmotion` moves at
all — one jibe `fell_in` → `touchdown`, and one **aborted** turn that stops being a turn
because an aborted sweep is kept only where the ladder calls it a fall (ADR-028). Across all
19 goldens: counted turns 569 → 568, jibes 565 → 564, turn `fell_in` 50 → 48, turn `touchdown`
208 → 209, **clean jibes 161 → 161**, straight-line falls 44 → 44. Submersion *episodes* fall
95 → 37 and four more fixtures get an empty list, which is the re-anchored stretches leaving
the map. **The watch already agreed with this rule and not with the old one** — its live test
has always read a slow pressure baseline that holds under a spike — so this closes a
divergence rather than opening one; the settle release is the one half still to be ported, in
a change of its own (docs/algorithms/pumping.md, "Watch divergences").

## ADR-028 · An attempted turn that ends in the water is **a turn that fell in**
**Status: Accepted.**

A tester rode 19 September 2026, tried two tacks, went in on both, and the session showed him
**0 tacks and 0 falls in a turn**. Nothing was broken: the detector's entry condition is
`turnMinAngle` (60°) of net COG change inside `turnMaxDuration`, the COG is only read above
`turnCogSpeedFloor`, and a rider who goes in halfway round therefore leaves a sweep that is
both too short and cut off at the fall. Where the part he rode cleared 60° it was filed as an
uncounted bear-away — a grey marker on the map with no name and no verdict — and the swim went
to the flight-end channel as a straight-line fall. Jan, 20 September 2026: *"an attempted turn
that ends in the water is a turn that fell in."*

Decision: **one more sweep per sailing run — the one still turning when the run ended — read
backwards from that last heading and offered to the same machinery, with `turnAbortMinAngle`
(45°) in place of `turnMinAngle` and nothing else changed.** The peak-rate floor, the carve
gate and the on-foil context all still apply: this lowers one number, it does not open a second
detector. And the scan does not decide that the rider fell — the candidate is scored by the
same builder and judged by the same three-channel ladder as every other turn, and only the ones
the ladder calls `fell_in` are kept. It is therefore impossible for this pass to add a turn
that is dry, successful or clean, which is what makes it safe to turn on by default: every
number a rider judges his session by (JPH, TPH, CPH, clean jibes, the streaks' lengthening
rule) reads *dry* turns, and an aborted turn is by construction not one.

Two smaller decisions ride with it. **The classification floor does not apply to an aborted
turn**: `turnClassifyMinAngle` reads a sweep's angle as evidence of intent, and an aborted
turn's angle is evidence of when the rider fell. And **it is named by the axis it was going
through, not the one it crossed** — an aborted tack, by definition, never got through the wind,
so requiring a crossing would leave the tack/jibe label unreachable for exactly the maneuvers
the rule exists to count. Where the sweep did cross, that crossing still names it.

45° is half the classification floor — he has to have ridden at least half the sweep that would
let the engine name a maneuver at all — and the corpus is the judge: at 30° four more appear
and all four ended 66–133° from any axis, which is the mislabel ADR of 0.13.0 all over again.

Consequence: engine **0.21.0**, one config key (`turnAbortMinAngle`) and one per-turn key
(`aborted`). Over the 18 committed session fixtures: counted turns 560 → 569, tacks 2 → 4,
jibes 558 → 565, course changes 147 → 140, turn `fell_in` 41 → 50, straight-line falls 45 → 44,
**clean jibes 161 → 161** and no rate numerator moved on any fixture. Eight of the nine new
turns are falls the page had attributed to nothing at all. **A new watch divergence** (its
first since 0.13.0): the wrist has no such pass and under-counts turns and falls on a session
with aborted maneuvers in it, until it is ported — docs/algorithms/pumping.md, "Watch divergences",
says what it should do. Not decided here, and left for Jan: the tester's *second* attempt is
still not a fall, because it stopped dead for 4 s before a 42 s recording gap and `turnFallStop`
is 5 s. That is a flight-end question — what a stop that runs into a long gap means — and this
ADR deliberately does not answer it.

## ADR-027 · The direct transfer's wire format — our own delta stream in 8 KB pages, not FIT
**Status: Proposed** (dev channel; docs/channels.md, all four rules unmet).

Issue #14 asks for a Garmin session on the phone without intervals.icu, Strava or a cable.
The research spike (docs/direct-transfer.md) ranked five options and the probe of 19 September
2026 fixed the rules the link actually has: a page of 16 KB kills the watch app, a second
`transmit` while the first is still on the radio kills it too, a locked phone times out, and
8 KB lands in about two seconds. So the transport is **pages of at most 8 000 payload bytes,
exactly one in flight, the next from `onComplete`, an app-level ACK, the phone app open**.
What is left to decide is what rides in them.

**Not FIT.** A Connect IQ app cannot read the FIT it recorded — Garmin staff say so plainly —
so "send the FIT" is not an option that exists, only one that sounds like one. Even if it did,
a two-hour FIT is 10.5 MB with the wrist stream and 445 KB without, which is three to six
hours and seven to fifteen minutes on a 0.5–1 KB/s link. And nothing downstream of
`RawTrack.samples` wants a FIT: the engine reads lat, lon, speed, altitude, heart rate and the
four record developer fields, and nothing else.

Decision: **`rec.v1` — a keyframe of 22 bytes, deltas of 13, in pages of 8 000, every page
opening with a keyframe** (docs/transfer-format.md is the contract). Nine bytes a second, so a
two-hour session is about 97 KB, thirteen pages and roughly 26 seconds on the beach. Three
choices carry it:

* **A keyframe per page, not per session.** A page then decodes on its own, so a page that
  never arrives costs its own seconds rather than the session, and the phone can import what
  it has when a transfer is abandoned. The cost is 22 bytes per 8 000, which is nothing.
* **1e-6 degree deltas in an int16.** ±0.032° per step is ±3.6 km at one fix a second, which
  no rider approaches, and the step costs two bytes where an absolute int32 costs four. The
  error is one micro-degree, about eleven centimetres, bounded rather than accumulating —
  three orders below what a GNSS fix is worth. Both ends hold the identical quantised
  integers, which matters more than the absolute error: rounding is stated as half away from
  zero with truncating division, because Python, Swift and Monkey C disagree about `round`.
* **8 KB pages.** Measured, not chosen. The page size is the one number in this format that
  came off a watch rather than out of an argument.

Consequence: **a third reference implementation exists on purpose.** `lab/tools/cjr_ref.py` is
the plain-Python statement of the same bytes, and the worked example of §2.3 is pinned by it,
by the kit's `DirectStreamTests`, by the watch's `WingfoilTests` and by
`fixtures/direct/example.cjr`. Three encoders are two too many to keep in step by reading.
**The session lands as class (a)**: the stream carries the four record developer fields, from
the same detectors that write them into the FIT, so `SourceCapabilities.sourceClass` answers
the same letter for both and no letter is invented (pattern L). It has no wrist stream, which
is dev3's and is already the ordinary shape of a class-(a) recording because `accelLogging` is
off by default. **Dedupe is ADR-013's and not a second rule**: the header's start is the
card's `KEY_START`, so a card that arrived first left a provisional row the stream fills, and
a FIT of the same afternoon later takes the direct row over in place — the FIT carries the
laps, the wrist stream and the local clock the stream does not. **The door is dev-only in the
app and nowhere in the kit**: `DirectStream`, `DirectPage` and `DirectStreamParser` compile in
every channel and are tested there, while the inbox, the link's routing and the Settings row
are `#if DEV`, so the release and beta binaries carry no inbox, no page assembler and no
`.cjr` anywhere. And **no new switch on either side**: the watch gates the whole send on the
card's existing `phonePush`, so a rider who lets the watch talk to the phone gets the
recording too.

## ADR-026 · The library syncs as a **folder**, not as a database — iCloud Drive, last writer wins per field
**Status: Proposed** (dev channel; Jan's call to accept).

Issue #7 asks for two devices and one library, and for a new phone to find the library
already there. The library is a GRDB file plus an immutable per-session archive (ADR-006),
and there are two honest ways to share it. **CloudKit records** would mirror every table and
give per-record conflict handling for free, and would buy that with a schema that has to be
migrated in two places for ever, a second source of truth for numbers the engine derives, and
a container that is unreadable without the app. **A folder in iCloud Drive** carries what the
backup already proves is the irreplaceable part — the recordings, and the handful of facts
nothing else in the world holds — and nothing else. The backup's own lesson (ADR-015) is that
a library is restored *through the ingest path*, never as a file copy, precisely so that one
rule decides what a session is; a folder keeps that, and a record store would quietly add a
second.

Decision: **`iCloud.de.lahmann.wingfoil` (dev: `iCloud.de.lahmann.wingfoil.dev`), holding
`Sessions/<uuid>/original.<ext>` and `Sessions/<uuid>/meta.json`, plus `tombstones.json` at
the root.** The recording is the file as it was ingested — the scrubbed FIT where one exists —
and is immutable, so it needs no clock. `meta.json` holds what the rider changed and nothing
derived: custom title, share note, rider, discipline override, spot name, gear by **name**,
and the deleted flag; **each field carries its own `updatedAt` and the later stamp wins**, a
tie keeping what the reading device already has. Per field rather than per session because the
two devices are edited for different reasons — a name on the beach, a wing in the evening —
and a row-level rule would silently throw one of those away every pass. **The analysis cache is
not synced**: each device re-analyses what it receives, under its own engine version, so the
folder can never carry a number this build did not compute. **Arrivals go through
`SessionIngestor`**, so the ±60 s dedupe key, the discipline ladder, the spot clusterer and the
default gear all run exactly as they do for a file dropped on the app. Changes are observed
with `NSFileCoordinator` and `NSMetadataQuery`; there are no CloudKit records.

Consequence: **uuids are per device and are not renumbered.** A session that reached the two
phones separately has two ids and is one afternoon, so the folder is keyed by whichever device
wrote it first and everything else — pushing a rename back, refusing a resurrection, removing
a deleted session's bytes — is decided by the ±60 s key, exactly like an import. **A deletion
outranks an arrival**: tombstones are merged before anything is read, they carry the
intervals.icu id *and* the dedupe key like `SessionTombstoneRow` does, and re-importing the
same recording after a delete is refused rather than resurrected. **The clock is the sync's,
not the edit's**: the library has no per-field `updatedAt` column and is not growing six, so a
field is stamped when a pass first sees it differ from the last copy this device agreed with
the folder (`Sessions/<uuid>/sync.json`, local and disposable). A rider who edits offline and
syncs in the evening therefore loses that field to a device that edited and synced at noon —
per field, and only where both touched the same one. The feature starts in **dev**
(docs/channels.md): the switch, the status line and every call into `LibrarySyncEngine` are
`#if DEV`, so no other channel has a door to it. XcodeGen writes one `CODE_SIGN_ENTITLEMENTS`
per target, so the beta shares the dev's entitlements file; the container id follows the
channel through `$(CJ_BUNDLE_ID)` instead, and the release channel's own file stays empty.

## ADR-025 · The session list's filters narrow the list, never the records
**Status: Accepted.**

The library grew past the length a flat newest-first list answers questions on, and the
questions that arrived with it — "how many afternoons in August", "everything at Torbole",
"what came in from Strava" — are all about sets of sessions. A filter is the obvious answer
and the dangerous one: the same chips would read perfectly well over Records and Trends, and
a rider who left "Nago-Torbole, 2025" on last week would then be quoting a personal best that
silently means "at that spot, that year".

Decision: **group by and filter are a view of the Sessions tab and of nothing else.** The
rules are a separate kit type (`LibraryListFilter` / `LibraryGrouping` in
`Presentation/LibraryListing.swift`) from the SQL-side `LibraryFilter` that Records, Trends,
Periods, the gear rollups and the widget go through, so the two cannot be wired together by
accident. The narrowing is per-visit — a question, not a setting — while the grouping is
remembered (`library.groupBy.v1`), and its default (Month from twenty sessions up) is read off
the *unfiltered* library so a chip can never change how the list is shaped.

Consequence: the count line has to say both numbers ("3 of 41 sessions") and a filter that
matches nothing gets its own empty state, because the fresh-library card in front of a rider
with forty sessions is the app being wrong about him. Records and Trends keep their own spot
and gear pickers, which say on the screen what they narrow. Dates are read on each session's
own clock; the custom range's two ends are read on the reader's, inclusively, exactly as the
Periods screen's own range is.

## ADR-024 · Windsurf is a **preset, not a fork** — and it ships marked experimental
**Status: Accepted.**

Issue #6 asks for windsurf as a discipline: engine presets, a vocabulary, the share card.
There were two ways to have it. A second detector tuned on windsurf sessions would be honest
about the differences and would immediately give the product two engines to keep in step
across four implementations — the exact failure ADR-001's golden-file contract exists to
prevent — and it would have to be tuned on a corpus that does not exist: Jan has no fin
session recorded, and every `…-windsurfen…` file he *does* have is a wingfoil afternoon under
Garmin's windsurf profile. Jan, 13 Sep 2026: *"jibe analysis applies, but not pumping"*, and
*"hide it a bit and mark as an experimental/untested feature"*.

Decision: **a `Discipline` preset over the existing configs — `wingfoil` (default),
`windsurfFoil`, `windsurfFin` — and nothing else.** `wingfoil` is not merely equal to today's
behaviour, it is **not applied**: the preset function returns its input, so a wingfoil run is
byte-identical to one produced before the type existed and a tuning slider survives it
untouched. `windsurfFoil` is the wingfoil reading with the **pump channel never built** — the
analyser is handed the `nil` a source with no accelerometer already hands it, so every stage
degrades through the path it has always had rather than through a second one, and every
pump-related number is *absent rather than zero*. `windsurfFin` also moves the two speeds that
decide when the board is up, into all four configs that carry them: 20 km/h in, 15 km/h out,
which makes "on the foil" read as planing and "lost the foil" as stopped planing. Those two
numbers are **PROVISIONAL and say so** — in the code, in algorithms.md, in the help topic and
under the control itself — because they are a guess, not a reading. The vocabulary is one
lexicon table keyed by discipline (`DisciplineLexicon`, `web/js/lexicon.js`) whose wingfoil
column is the strings both platforms already printed; the *turn* vocabulary is untranslated,
because a jibe is a jibe and "clean jibe" is what this product is called.

Consequence: `ENGINE_VERSION` stays **0.18.0** — a preset is not a new engine — and the preset
rides in the analysis' `engineVersion` as `+disc.<name>`, composing inside the tuning stamp, so
switching one session's discipline makes exactly that session stale and `reanalyzeStale()`
re-derives it through the mechanism tuning already built (the staleness comparison moves out of
SQL into Swift, because the version a row *should* carry now depends on the row). One new
column (`session.disciplineOverride`, schema v14, no re-analysis sweep behind it — every
existing row resolves to wingfoil), one optional config echo (`config.discipline`, **absent**
on a wingfoil document so no committed golden moves), two cross-check goldens under
`fixtures/goldens/discipline/`, one help topic, and one segmented control on the session's Details
tab under a footnote that calls the whole thing untested. The **FIT sport code is never
consulted**: ADR-004 records sport 43 for wingfoiling, so a windsurf-profile recording of a
wingfoil session — the common case in the corpus — stays wing unless the dev-field tag or the
rider says otherwise, and `Discipline.resolve` does not take a sport as an argument. Rejected:
a second engine (two contracts, four implementations, no corpus); switching on the sport code
(would have re-read most of Jan's library as windsurf on day one); and echoing
`"discipline": "wingfoil"` unconditionally (nineteen goldens rewritten to announce a layer the
default never reaches). The watch and the Trends/Records pages are untouched — there is no
separate windsurf record set, which the help topic states rather than leaves to be discovered.
## ADR-023 · Strava as a read source: class (c) **by construction**, and read-only on purpose
**Status: Accepted.**

The second cloud source beside intervals.icu, and the one that reaches the riders who have no
Garmin account, no Apple Watch and no intention of setting up intervals.icu — which, on the
water, is most of them. **Decision: the mapper writes a GPX.** What
`/activities/{id}/streams` returns is positions, an elapsed clock, an elevation and a heart
rate; channel for channel that *is* a GPX, so `StravaImport` emits one and `GpxSessionParser`
decides everything after it. Nothing in the Strava path sets a source class, marks a record
uncertified or derives a speed — all three fall out of the format, in the one place they are
already decided for every positions-only source, and a Strava session cannot drift away from a
GPX of the same afternoon because after the mapper the two are the same file. Strava's
`velocity_smooth` is fetched and thrown away: it is computed from the positions and then
smoothed, so treating it as measured would be a claim the data cannot support, and carrying it
beside the engine's own derivation would put two differently-filtered answers in one column.
`hasSpeed` false, `source_class` `c`, speed records **uncertified** everywhere — and the
Import screen, the Strava screen and the help all say so before the rider imports rather than
after, plus the sentence that matters most to a Garmin owner: *if the same session is on
intervals.icu, take it from there instead.*

**Read-only, and not as a stage.** CleanJibe lists and downloads; it writes nothing to
anybody's Strava account. Write-back — a CleanJibe block in the activity description — stays
issue #5, with its own consent and its own opt-in, and nothing in this change is a step
towards doing it quietly. The scope asked for is `activity:read_all`, and a rider who narrows
it on Strava's own consent screen is *told* (`stravaScopeIsNarrow`), because a connection that
works and lists nothing is indistinguishable from a bug.

**Consequences, all of them configuration.** The API application is registered under Jan's
Strava account — category *Performance analysis*, website `cleanjibe.org`, client id `279015`
— and its secret lives in an untracked `ios/Strava.xcconfig` (template:
`ios/Strava.example.xcconfig`, created automatically by `xcodegen generate` so a fresh clone of
a public repository still builds, with the Strava row explaining what is missing rather than
failing). Strava validates the redirect against the application's **single** Authorization
Callback Domain, `cleanjibe.org`, and refuses custom schemes — so the round trip has one hop
more than it looks like it should: Strava → `https://cleanjibe.org/strava/callback`, a
self-contained static page that forwards `code` and `state` to `cleanjibe://strava`, where
`ASWebAuthenticationSession` is waiting. Until Strava reviews the application it allows **one
connected athlete** and 1 000 requests a day, so `StravaClient.Error.athleteLimit` is its own
cause with its own sentence, and the help says plainly that Strava import is single-rider for
now. Rate limits (100 / 15 min) stop a run rather than retrying into them, and what was
already imported stays imported.

## ADR-022 · The pumped-out touchdown is an opinion, so it is a switch — and it asks the wrong speed
**Status: Accepted.**

Step 3 of the outcome ladder promoted a fly-through to a `touchdown` when the accelerometer
heard a pump burst *and* the speed channels went below `foilEntrySpeed` somewhere in the same
window. Two things were wrong with it. It is the one rung that is a **judgement about the
rider** rather than a measurement of the water — everything else on the ladder says *the foil
stopped carrying*, and this one says *he worked, so it must have* — and it was asked against
the speed a **flight starts** at, 12 km/h, which is not the speed below which a foil stops
flying. Jan's Jibe 50 of 4 Sep 2026 07:58 is the case: it sagged to 5.5 kn = 10.2 km/h, below
entry and comfortably above the 8 km/h exit, with no off-foil sample, no stop and no wrist
under — and he flew it. Jan, 7 Sep 2026: *"change to '…below min foil speed…'"*, and *"can we
add a short comment for the user why a jibe is a touchdown or a fall?"*

Decision: **the rung gets a speed of its own and a switch — `turnPumpedMarginalSpeed` (8.0
km/h) and `turnPumpedOutIsTouchdown` (on).** The speed defaults to the number `foilExitSpeed`
carries, and because `flying` is *defined* as in a flight, not submerged, and above
`foilExitSpeed`, the rung is thereby **unreachable**: on the only branch it lives on, every
sample is already above the speed it tests. That is the intended effect and not a side effect —
the rule is retired, in the open. It is a **parameter rather than a reference** to
`foilExitSpeed` precisely so the retirement is a *setting somebody can disagree with*: the band
the rung judges is `(foilExitSpeed, turnPumpedMarginalSpeed]`, empty at 8.0, and at 12.0 the
0.17.0 reading restored — which is asserted, in both directions, against Jibe 50 itself. The
switch sits beside it as the gate, because the two answer different questions: whether the rung
is asked at all, and what it asks. Left alone deliberately: the `pumped` flag and the "pumped
out · N strokes" chip, which are about *effort* and were always true. Beside it, every touchdown
and fall now carries `outcomeReason` (`stop` | `off_foil` | `submerged` | `pumped_marginal`,
null on a fly-through) — a code, with the words chosen once in presentation for both platforms
and held together by `verify_presentation.py` §6.

Consequence: engine **0.18.0**. Over the 21-session corpus 13 of 270 jibe touchdowns become
fly-throughs (493 → 506 flew through, 270 → 257 touched down, 55 fell in unchanged) and 3 jibes
become clean (263 → 266). One new per-turn key, two new config echoes, two new tuning rows —
one of them the first that is a **switch** rather than a slider (`TuningParameterSpec.kind`).
No new watch
divergence, despite what this ADR first said: the watch's `TurnDetector` never had the pump
rung (its ladder is submerged-or-stop → fell in, any loss of the foil → touchdown, else flew
through, and the accelerometer feeds none of it), so at the 0.18.0 defaults the wrist and the
phone agree, and only a dev build that raises the marginal speed diverges from the wrist —
corrected 9 Sep 2026 while porting the quiet tail to device app 0.9.9. Rejected: deleting the rung outright (a stored
document would then decode a verdict nothing in the tree explains), and writing the speed as a
reference to `foilExitSpeed` (it would have made the retirement unarguable and the switch inert
at every setting, which is a knob that lies about what it does).

## ADR-021 · A clean jibe needs a **quiet tail** — ten seconds, and only for clean
**Status: Accepted.**

A turn's outcome window closes at *recovery* (`turnRecoverPct` held for `turnRecoverHold`), so
a jibe the rider powers straight out of is judged over a second or two and a touchdown at +7 s
is a straight-line loss the flight-end channel counts. That is right for the ladder — charging one
swim to two channels is exactly the double count the ownership rule exists to prevent — and
wrong for the word: a rider swimming ten seconds after his jibe does not call it clean.
Decision (Jan, 7 Sep 2026): **`turnCleanQuietS`, 10 s, as a third clause of `clean` only.**
Over `[turnEnd, turnEnd + 10 s]`, on the same off-foil evidence and stopping at a recording
gap, there may be no `touchdown`/`fell_in` flight end, no off-foil spell of 1 s or longer and
no submerged sample; the turn keeps its outcome, its `success`, its score and its place in
every count and streak. Consequence: engine **0.17.0**, clean jibes 160 → 150 over the
committed fixtures and 278 → 263 over the 21-session corpus (about 5 %), one new per-turn key
(`cleanBlockedBy`) so a page can say *why* a jibe has no star, one new tuning slider, and one
new watch divergence — the wrist has no way to withdraw a count ten seconds later, so the watch
now reports **more** clean jibes than the phone on a session with a fall shortly after a jibe.
Rejected: 6 s (catches only the run-out, 5 jibes) and 15 s (takes jibes for a fall the turn did
not cause, 23). Rejected too: making it a requirement for *carried through*, which is a
measurement of the sweep and has no business reading a tail.

## ADR-020 · The Garmin data field is **dormant** — the app is the product
**Status: Accepted** — it supersedes ADR-009.

ADR-002 chose a device app over a data field, and the field arrived later (0.1.0, 13 Aug 2026)
as a companion for riders who wanted to keep Garmin's native Windsurf profile. Three weeks on:
Jan has never ridden with it, no rider has asked for it, its CPH denominator already diverges
from the app's (`docs/algorithms.md`, timerTime vs elapsed), and every metric added to the app
now costs a second implementation, a second listing, a second review and a second set of store
assets. Decision: **park it.** `garmin/field/` stays in the tree and keeps building (it shares
the barrel and the tokens, so it costs nothing to keep compiling), but it gets no new metrics,
no releases and no listing work. cleanjibe.org stops linking to it; `garmin/store/listing.md`
marks the section dormant and keeps the text for a possible re-listing. The store listing itself
comes down only by *Remove* — Garmin has no unpublish — and that is Jan's call, taken on the
store page, not in this repo. Reversal condition: riders asking for it, in numbers, with a use
the app cannot serve (a customised native profile is the only one anybody has named).

## ADR-019 · Watch GPS needs the phone's permission string and the background flag — the workout session alone is not enough
**Status: Accepted.**

The first real Apple Watch session (4 Sep 2026, 68 min, heart rate throughout) reached the phone
with **zero position fixes**, and the start screen had said "Asking for location" the whole time.
Two separate facts, both wrong in the code since ec1e3bd, and neither produced an error anywhere:
1. **watchOS keeps a companion watch app's location permission under the iPhone app.** The
   prompt on the wrist only appears when the *iPhone* app's Info.plist carries
   `NSLocationWhenInUseUsageDescription` — since watchOS 10 a missing key is not a crash but a
   silent `.notDetermined` forever. The phone never asks for location itself; the string is there
   for the watch and says so.
2. **A running `HKWorkoutSession` keeps the process alive, not the fixes.** Since watchOS 4,
   CoreLocation stops delivering to a backgrounded (wrist-down, water-locked) app unless
   `allowsBackgroundLocationUpdates` is true. ITMS-90362 was right that `location` is not a
   `WKBackgroundModes` value, and ec1e3bd drew the wrong conclusion from it: the key the flag
   wants on watchOS is **`UIBackgroundModes: [location]`** in the watch app's Info.plist — the
   same entry the WatchKit extension carried since watchOS 4 — plus a running workout session.
   `LocationBridge.startUpdating(background:)` sets the flag `true` right after
   `WorkoutBridge.start` succeeds and `false` before START, after stop, and whenever the manager
   is stopped.
   *Amendment, same day:* build 21 shipped the flag without the plist entry and START killed
   the app with `NSInternalInconsistencyException` ("!stayUp || CLClientIsBackgroundable"),
   because CoreLocation asserts the entry the moment the flag is set. Build 22 adds the entry,
   and `LocationBridge` reads it before setting the flag so a plist mistake can only ever cost
   the background fixes, never the session.
Also decided: the recording screen now says **NO GPS** in the paused slot whenever
`hasUsableFix` is false, because 0.0 kn on a foil looks exactly like waiting for wind, and a
rider cannot otherwise tell a dead recorder from a calm day. The import's "contains no position
fixes" refusal stays as it is: a heart-rate-only file has nothing to analyse.

## ADR-018 · The complication is a **launcher**, the Siri intents live in the app, and neither detects anything
**Status: Accepted** — it narrows ADR-016.

ADR-016 declined a complication on the grounds that it would be "a fourth surface making claims
about a session". That reasoning was about *claims*, and it survives intact — what it did not
cover is the gesture. Between a watch face and a running recording there were five steps (crown,
find the app in a grid of forty, launch, wait, START), performed in knee-deep water by a rider
holding a wing overhead with wet hands, and every one of them is a chance to start the session
two minutes late or not at all. Decision: **one complication whose entire job is to start the
session**, plus Siri phrases that do the same thing hands-free. `accessoryCircular`,
`accessoryCorner` and `accessoryRectangular` carry the brand mark and a `widgetURL` of
`cleanjibe://start`; the app answers it through `SessionRecorder.startFromOutside()`, which is
also the door `StartSessionIntent` comes through. One entry point, so a session begun from a face
is not a second kind of session — same `HKWorkoutSession`, same water lock, same files — and the
UI follows without a tap because `phase` is what `RootView` switches on.
**The complication is a separate target because WidgetKit demands one; the intents are not,
because nothing demands it.** A complication is a WidgetKit extension — its own process, its own
`@main`, its own bundle id — and there is no way to render one from an app target, which is why
`WingFoilWatchWidgets` (`de.lahmann.wingfoil.watchkitapp.widgets`) exists at all. App Intents are
under no such constraint, and an intents *extension* would have been actively worse: the thing
this intent moves is a state machine that owns an `HKWorkoutSession`, which exists in the app
process and nowhere else, so an extension would have to message the app to do the work — the app
doing the work, with a round trip in front of it. `openAppWhenRun` says "run me in the app" and is
also the honest answer, because the rider who says it out loud wants to see his watch recording.
No new entitlement: no app group, no HealthKit in the extension, nothing but the URL.
**It still claims almost nothing, and that is ADR-016 holding rather than being softened.** The
watch cannot print a clean-jibe count or a foil percentage, because under ADR-016 it does not
compute them — those exist only after the phone has analysed the recording, and a face that
guessed at them would be the exact second answer that ADR forbids. The rectangular family
therefore shows either "Start session" or the three facts the watch measured itself (date,
duration, distance), through a ~200-byte `WatchLastSessionStore` snapshot written *after* the
`.cjw` container is safely assembled — never before, so a face cannot advertise a session that
failed to save. That store has the same app-group shape, and the same missing entitlement, as
`WidgetSnapshotStore`: the manual App Store profiles do not carry `group.de.lahmann.wingfoil`, so
today the write is a no-op and every face reads "Start session". Which costs nothing that matters,
because the launcher — the whole point — needs no group at all.
Consequences: `SessionRecorder` becomes a singleton (there is one workout session on a wrist, and
two things outside the view tree now have to reach it); `startFromOutside` waits on the HealthKit
prompt before starting, because a Siri start may be the first thing a cold process does and
`WorkoutBridge.start` throws if Health has not answered; the two constants both targets must agree
on live in `ios/WatchShared/`, outside either target's source tree, for the XcodeGen path-collision
reason `Views/WatchBrand.swift` already documents; and `ios/ExportOptions.plist` needs a fourth
profile, three bundles deep. **iPhone-side intents were considered and dropped**: the phone cannot
start a watch workout without `HKHealthStore.startWatchApp(with:)` and a WatchConnectivity handoff,
which is a feature and not a trivial re-export, so "Start a CleanJibe session" is a watch phrase.
## ADR-017 · Apple Health is a **source**, and it reuses the watch container rather than becoming a fourth format
**Status: Accepted** — it narrows ADR-003.

ADR-003 ruled HealthKit out as an input and the reason it gave was about *Garmin*: HealthKit
hands out no `HKWorkoutRoute` for a Garmin-synced workout, so it can never be the way this app
reaches the recordings it was built around. That is still true and nothing here contradicts it.
What it missed is the workout an Apple Watch makes **for itself**: a rider who owns no Garmin at
all, records with Apple's own Workout app under Surfing, Water Sports or Sailing, and has a
1 Hz `CLLocation` route with Doppler speed plus a heart-rate stream sitting in Health with
nothing able to read it. That rider is the whole funnel ADR-016 opened, minus the requirement to
install our watch app. Decision: **read those workouts**, through a new `HealthImport` mapper in
the kit and a `HealthImporter` in the app, with an "Apple Health" source on the Import screen and
an opt-in automatic pickup.
**Not a fourth format.** A route is, sample for sample, what the CleanJibe watch app already
writes into a `.cjw` container (docs/watch-session-schema.md), so `HealthImport` maps into *that*
— `WatchSessionParser` is still the only parser, the capability rules are decided in one place,
and the archived original re-analyses on an engine bump exactly like every other session.
`TrackFormat.watch` was always the name of a packed track layout rather than of a device;
`meta.producer` says who filled it in (`"CleanJibe iOS 0.14.0 (Apple Health)"`) and
`session.importSource` (`applehealth`) says where the session came from. The alternative — a
second binary shape for identical data — would have bought a nicer file extension and cost a
second parser, a second capability table and a second thing to keep in step with the first.
**Class (b), certified, and plain (b) this time.** ADR-016's argument transfers unchanged:
`CLLocation.speed` is the GNSS chip's own Doppler solution rather than a difference of positions,
which is exactly what docs/presentation.md's provenance rule asks for. But unlike a CleanJibe
watch recording there is **no accelerometer** — Health carries none — so there is no pump chart,
no failed-takeoff count, and the standard class-(b) sentence is the correct one. That is why
`SessionDisplay.sourceClassNote`'s special case stays keyed on `applewatch` and is not widened.
`discipline` is set to `wingfoil` because the *import* is the rider saying so: Apple has no
wingfoil type, so the type he picked says nothing, and pointing a wingfoil app at a workout and
asking for it is the claim. The type Health actually holds is not thrown away — it lands in
`SourceCapabilities.sport`.
**The one thing the container could not already say.** Apple's Workout app usually writes no
`HKMetadataKeyTimeZone`, and a device-zone guess handed over wearing rung 1's provenance would
license every surface to state a clock the app does not know (engine 0.9.1's whole point). So
`WatchSessionMeta` gains one additive optional field, `utcOffsetKnown`, absent-means-true on
every container the watch has ever written; false hands the question back to
`SessionIngestor.resolveUtcOffset`, where a Health session lands on `longitude` exactly like a
GPX. A workout that *does* carry a zone gets rung 1, and the two cases are distinguishable in
the library rather than averaged.
**Our own workouts are skipped**, by bundle-id prefix — the watch app's live save and
`HealthWriter`'s after-the-fact stub are both already in the library, by a better road in both
cases — and the symmetric rule is the one that matters more:
`SessionStore.writeNewSessionsToHealth` now excludes `applehealth` as well as `applewatch`, or
importing a workout would be how a rider ends up with two of them on the same afternoon.
Consequences. **A read denial is invisible and stays that way**: HealthKit refuses to reveal one
on purpose, so the empty list names both possibilities and points at Health → Sharing → Apps
rather than inventing a verdict. **Background delivery is asked for and may simply be refused** —
`com.apple.developer.healthkit.background-delivery` is not on the manual "WingFoil App Store"
profile, which is ADR-011's trap exactly — so the sweep at launch and at every foreground is the
path that always works and the observer only shortens the wait; the entitlement is documented in
`ios/project.yml` as configuration rather than added there. And **the automatic pickup remembers
workout uuids** on top of the dedupe key, because the key alone cannot see the one case that
would be maddening: a workout imported, then deliberately deleted, then silently imported again
an hour later.

## ADR-016 · The Apple Watch recorder is class (b) and **certifies**, and it detects nothing
**Status: Accepted** — its "a fourth surface making claims about a session" clause is narrowed by ADR-018, which allows a launcher that makes none.

An Apple Watch is the one recording device a rider already owns that can reach the library
without an account, a cable or anybody's cloud: the watch writes a file, `WCSession.transferFile`
queues it, the phone imports it. That removes the Garmin→Connect→intervals.icu chain from the
funnel entirely, so the MVP's job is to be a **recorder** and nothing else — GPS, heart rate, and
the wrist accelerometer at 50 Hz, into a versioned `.cjw` container (docs/watch-session-schema.md)
that `TrackParser` recognises by its first four bytes exactly as it already recognises a GPX.
Nothing downstream of `RawTrack` + `SourceCapabilities` learns that an Apple Watch exists.
**No detection on the wrist.** ADR-005 says the watch approximates and the phone is
authoritative, and that division earns its keep on Garmin because the Garmin watch is also the
*display* — a rider mid-session wants a flight count on his wrist. Here it buys nothing: the
recording reaches the phone in seconds, so a second implementation of flight, turn and record
detection would be a second answer to every question with no way to tell which one the app meant.
Phase 2 can add it; the MVP declines it on purpose, and `hasDevFields` is false because there
genuinely are none.
**Class (b), certified, and no new letter.** The rule in docs/presentation.md is about
*provenance* — a speed record is trustworthy when it came off the receiver's Doppler channel —
and `CLLocation.speed` is exactly that, the GNSS chip's own solution rather than a difference of
positions. A GPX is class (c) because the file cannot prove where its speed came from; this
container can, because we write it and it carries speed and position as two separate channels.
That is the same claim already made for a native Garmin FIT, and it is **not** a GP3S validity
claim, which this app has never made for any source. A dedicated letter was considered and
rejected: (d) is spoken for by ADR-009, so a watch class would be (e), and it would have to be
taught to six Swift switch sites, `web/js/render.js`'s letter dictionary, `HelpCatalog`'s
three-case prose and `lab/parse.py` — to express a distinction `certified` does not draw.
Provenance survives in `session.importSource` (`applewatch`) instead.
Consequence: the letter now understates one source, and two places had to learn that. A watch
session has class (b)'s Doppler **and** class (a)'s accelerometer, so pump strokes and takeoff
effort are all present — the pipeline degrading on capabilities rather than on formats, which is
what that design was always for. `SessionDisplay.sourceClassNote` therefore reads `importSource`
as well as the class, because the standard class-(b) line ("everything except pump and takeoff
effort") would otherwise print over a session that visibly has a pump chart.
**`.surfingSports`, and the phone stands down from Health.** HealthKit has no wingfoil type;
`HealthWriter` already chose `.surfingSports` and the watch matches it, or a rider's Health
timeline would name one sport two ways. Because the watch saves the workout live — with the
heart-rate samples and ring credit an after-the-fact `HKWorkoutBuilder` stub cannot give —
`SessionStore.writeNewSessionsToHealth` skips rows tagged `applewatch`; nothing downstream would
have collapsed the duplicate, since `HKMetadataKeyExternalUUID` carries the watch's session id on
one copy and the library's row id on the other.

## ADR-015 · The library backup restores through the **ingest path**, never as a file copy
**Status: Accepted.**

The library lives in Application Support, so an iPhone migration and an iCloud device backup
already carry it and nothing here replaces that. What neither covers is a *fresh* start — a
phone set up as new, the app deleted and reinstalled — and the loss is asymmetric: the
recordings can be re-fetched from intervals.icu with some pain, but `customTitle`, `shareNote`,
the rider attribution, the gear links, the spot names and the tombstones exist in one SQLite
file on one phone and nowhere else. Decision: **one zip** — `manifest.json`, `library.sqlite`,
`Sessions/<uuid>/{original.fit|gpx,analysis.json}` — written to `tmp/` and handed to the share
sheet, so the rider picks the destination (iCloud Drive being the obvious one) and the app never
writes to his storage on its own.
Two decisions inside that carry the weight. **The database snapshot is `VACUUM INTO`, not a
file copy.** Copying a live SQLite file is the classic way to ship a corrupt backup: the `-wal`
and `-shm` sidecars hold committed pages the main file has not absorbed, and copying all three
is not atomic either. `VACUUM INTO` runs on GRDB's serialized writer connection inside SQLite's
own read transaction, so it sees one consistent snapshot with the WAL folded in, writes a single
sidecar-free file, and compacts on the way — `DatabasePool.backup(to:)` plus the compaction, and
unlike `PRAGMA wal_checkpoint(TRUNCATE)` + copy it cannot race a writer that commits between the
two steps. **And restore never puts that file back.** Copying it over the live database would
delete every session imported since the backup, undo every rename since, and resurrect
everything deleted since. Instead the snapshot is opened *beside* the live library, migrated
forward by the ordinary `AppDatabase.migrator` when it is older, and read as a source of facts:
each session goes back in through `SessionIngestor.ingest` — the same door icu, GDPR and AirDrop
use, same ±60 s dedupe key — and the metadata is merged with one rule, *fill what is missing,
never overwrite what is there*. Gear merges by natural key (kind + name, case-insensitive) so a
second restore does not double the kit list; spots carry over only a name the rider typed, onto
a live spot still auto-named within the backup spot's radius; tombstones union by id.
Consequences, all of them deliberate. **Restore is idempotent by construction** rather than by a
"already restored" flag — the second pass finds every session by dedupe key and every field
already filled, and writes nothing (asserted). **It never resurrects a session deleted since the
backup**: a live tombstone is the newer instruction, and those are counted and reported rather
than silently obeyed or silently overruled. **A provisional row cannot be restored** — the
watch's BLE card carries no recording, and inventing a session row from summary columns is the
blind copy this whole design avoids. **A future schema is refused by name**, because a backup
from a newer build can hold columns this one has never heard of; an older one is the ordinary
case and is migrated. Size is stated before the work starts and warns above 200 MB naming the
accelerometer, which is ~95 % of any CIQ recording that has one. ZIPFoundation was already a
dependency for the GDPR nested-ZIP reader, so the write path cost nothing new; unlike the import
side it opens the archive **by URL** rather than from `Data`, because a season's backup is
gigabytes and the GDPR reader's whole-file-in-memory shape does not survive that.

## ADR-014 · The device list stops at CIQ ≥ 5.x sports watches (Tier A), and stops there on purpose
**Status: Accepted** — the floor has moved since. `docs/channels.md`, "Devices", is the live list: the fenix 5 Plus family joined in 0.9.11 (minApiLevel 3.3.3) and the Venu, vívoactive and Instinct 3 AMOLED families in 0.9.10, all of which this ADR excluded. What stands is the rule it wrote down — a watch joins when it runs the current code unchanged — not the 0.9.4 list.

The app shipped on the fenix 8 and fenix 7 families and nothing else, which is a small slice of
the watches that could run it. A survey of the whole SDK device catalogue against the built
app's own footprint (the scratchpad's `device-table.txt` / `app-headroom.txt`) sorted the rest
into tiers, and 0.9.4 takes the top one whole. Decision: **Tier A** is every remaining CIQ ≥ 5.x
round sports watch — epix 2 and epix 2 Pro (42/47/51 mm), Forerunner 255/265/570 (42/47 mm)/955/
965/970, MARQ 2 and MARQ 2 Aviator, Enduro 3, D2 Mach 1 and Mach 2, Descent Mk3 43 mm — because
each of them runs the *current* code unchanged: ≥ 524 KB of watch-app memory against a 67 KB
build, a 100 Hz accelerometer, a round glass at one of the four sizes the layout suite measures,
and the same `has`-guarded GNSS fallback the fenix 7 already exercises. Everything below that
line stays out, and each for its own reason: the **128 KB fenix 5/6 and Enduro 1 bases** would
need the app cut roughly in half (a 108 KB build against a 131 KB ceiling was the survey's
finding — buildable, but with nothing left for a session); the **Instinct family** is a 1 bpp
semi-octagon with a second sub-screen, which is a different UI, not a rescaled one; and the
**rectangles** (Venu X1, epix Gen 1) would need every round-display fitter in `RecordingView`
replaced, since the whole layout suite measures chords. Venu 3 and Vivoactive 5 are excluded on
top of that as non-sports watches. Consequence: 30 products across the app, the field and the
barrel, all four `.iq` exports green with the compiler's per-device memory gate passing; two
real layout bugs surfaced on the way in (see `docs/testing.md` — a digits-only vector face and
the Forerunner font metrics), both fixed for every watch including the ones already shipped.

## ADR-013 · The companion link carries a **card**, not data — and reuses the import dedupe rule
**Status: Accepted.**

Phase 5 asks for a session summary on the phone before the FIT has finished its trip through
Garmin Connect. The channel for that is `Communications.transmit` to a companion app over BLE,
which is shared with the whole Garmin ecosystem and is documented by Garmin itself as a place
to send as little as possible. Decision: the payload is a **notification, never a source of
truth** — integers only, short keys, and only the numbers the card actually shows (measured:
**192 bytes, 21 keys** for a 2-hour session against a 1 KB budget). The FIT still arrives
later and the phone still re-derives everything from it; the card is replaced by real analysis
when it does.
Reconciliation is the part that could have gone wrong twice. The dedupe key is **session start
epoch + elapsed seconds, meaning exactly what the FIT's session start and `total_elapsed_time`
mean**, so the card goes through the SAME `SessionIngestor` rule that already dedupes imports
(±60 s on both), instead of a second mechanism that would drift from the first. The card lands
as a **provisional** row (schema v4 `isProvisional`); the FIT replaces it in place, same row id,
sources merged. A provisional row whose FIT never arrives stays — it is a real session the rider
did, and its absence from Garmin Connect is information too. Provisional rows are excluded from
the library aggregates and from `reanalyzeStale`, which would otherwise announce a re-derive on
every launch for ever.
When the phone is unreachable — the normal case, not the error case — the watch keeps **one
pending slot, newest wins**. Three sessions recorded away from the phone should produce the
newest card on reconnect, not three stale ones replayed in order.
The SDK boundary: `connectiq-companion-app-sdk-ios` 1.8.0 is an SPM **binary** target (ObjC
xcframework) and it goes into the **app target only**, behind a `CompanionLink` protocol
declared in WingFoilKit. WingFoilKit never imports it, so the package keeps building and
testing on any machine with no framework and no watch in the room, and the wire contract stays
unit-testable (17 tests) against a fake.
Two fenix 7 platform traps found the hard way, both now in `PhoneLink.mc`'s header because
neither is discoverable from the docs: **`registerForPhoneAppMessageErrors` bricks the fenix 7
family** — the app does not start, with no exception and no log — and `Communications has
:registerForPhoneAppMessageErrors` returns **true** there, so a capability guard does not save
you. It is not called at all; the failure that matters (a summary that did not land) arrives
through `ConnectionListener.onError`, which is what preserves the pending slot. And a
`Lang.Method` bound to a **module** rather than a class wedges the same call: compiles clean,
works on fenix 8, hangs on fenix 7.
Consequence to be honest about: **the BLE hop itself is unverified.** Everything either side of
`transmit` is unit-tested; the hop needs a paired watch, GCM and a real iPhone. So does the
assumption underneath the dedupe key — that `Activity.Info.elapsedTime` equals the FIT's
`total_elapsed_time` — which needs one real session **with a pause** compared against its synced
FIT before the key can be trusted.

## ADR-012 · Invite testers get a **public** listing with an obfuscation-grade lock
**Status: Retired** — the lock has been off since 0.9.11: every stream compiles the all-zero pepper, so `LockGate.enabled()` is false everywhere (`docs/channels.md`, "Devices"). The channel it created lives on as the beta listing (`manifest-beta.xml` + `monkey-beta.jungle`); `lab/tools/make_unlock.py` and the shared test vectors stay, so the gate can be re-armed from the same secret without reissuing a key.

A Connect IQ "beta app" listing is visible only to the developer account, so the one thing it
cannot do is reach a tester. The only channel to a friend's watch is a **public** store
listing — which anyone can install. Decision: a third build channel, then `manifest-invite.xml` +
`monkey-invite.jungle`, since 0.9.11 `manifest-beta.xml` + `monkey-beta.jungle` with the lock retired (own UUID, "WingFoil - Invite Beta"), identical code to the public app
except that it starts locked. `LockGate` derives an 8-character **request code** from
`System.getDeviceSettings().uniqueIdentifier` (present on fenix847mm per the SDK 9.2
`api.debug.xml`; per-app, per-device, stable across uninstall, and null-guarded by a
first-run random id in `Storage`), the lock screen shows it, Jan runs
`lab/tools/make_unlock.py <code>` and mails back an 8-character **unlock key**, the tester
types it into the app's Garmin Connect settings, `onSettingsChanged` re-validates and the
app opens for good on that watch. Codes are Crockford base32 (no I/L/O/U) because they are
read off round glass and typed on a phone; the watch folds the look-alikes back anyway.
The honest part: the check is `key == B32_40(FNV1a64(pepper || request_code))`, computed the
same way on both sides, so the 8-byte **pepper** compiled into the invite build is the entire
secret and anyone who unpacks the `.prg` can mint keys. That is not a shortcut, it is the
shape of the problem — offline per-device verification means the watch must hold whatever it
verifies against, and an HMAC secret would be no less extractable (and CIQ has no crypto
primitives to compute one with anyway). Truncated-HMAC key generation was the first design
and was dropped for exactly this reason: it would have looked cryptographic while being
unverifiable on-watch, and the two sides would have had to disagree. So the gate is a
"please don't", sized for a handful of invited testers on a free hobby app, and this ADR
says so rather than the code implying otherwise.
Mechanics that keep the secret out of git: `UNLOCK_SECRET` lives in the gitignored `lab/.env`;
`make_unlock.py --emit-pepper` derives the pepper and writes `garmin/gen/UnlockPepper.mc`,
which `.gitignore` covers (`garmin/gen/` **and** `garmin/source/gen/`, so the file cannot be
moved under the shared source path by accident). Exactly one directory supplies module
`UnlockPepper` per build: `garmin/source-nopepper/` (all zeros ⇒ `LockGate.enabled()` false
⇒ the public app and the beta build never reach the lock screen, verified by a unit test and
by their settings JSON not carrying `unlockKey`) or `garmin/gen/` (invite only). Building the
invite jungle without the generated file fails loudly on an undefined `UnlockPepper` rather
than silently shipping an open lock. Consequence: three channels to keep straight
(public / beta / invite), one gitignored generated file to re-emit on a fresh clone — from
the same secret, so keys already issued keep working — and a per-tester step for Jan that is
two lines of mail. Parity between the Python and Monkey C implementations is held by three
shared test vectors hard-coded in both suites; the 64-bit FNV state is carried as two 32-bit
halves on both sides so nothing depends on Monkey C's undocumented `Long` overflow behaviour.

## ADR-011 · Widgets ship without an app group, and say so
**Status: Accepted** — and since carried out. The app group the ADR calls "configuration, not code" is in `ios/project.yml` for the beta channel's app, its widgets and the watch app; the release channel embeds neither widget nor watch app and its entitlements file still carries none. The runtime probe stands, because it is what makes both states honest.

The WidgetKit extension (`de.lahmann.wingfoil.widgets`, embedded in the app) needs the app's
data, and a widget process cannot open the GRDB library — different container, 30 MB memory
limit. The app therefore publishes a small denormalized `WidgetSnapshot` (last session +
this week's foil time) after every library change, and the widget only decodes it. The
transport **would** be `UserDefaults(suiteName: "group.de.lahmann.wingfoil")`, but the
existing manual "WingFoil App Store" provisioning profile does not carry that group, and
requesting an entitlement a profile does not grant fails the archive — which would break
Jan's TestFlight path for a home-screen widget. Decision: no app-group entitlement in
either target; `WidgetSnapshotStore` probes for the shared container at runtime with
`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` — the *only* honest
test, since `UserDefaults(suiteName:)` returns a usable-looking object without the
entitlement and a write/read round-trip through it succeeds against a plist that lives
inside the app's own container and is invisible to the widget. Consequence: with today's
profile the widget installs, archives and renders a "finish setting up" state; the app
always writes a local copy so its own read-back never depends on the entitlement. Turning
the widget on for real is **configuration, not code** — add the App Groups capability to
both app ids, regenerate the profiles, add `com.apple.security.application-groups` to both
`entitlements` blocks in `ios/project.yml`, and add the widget's bundle id to
`ios/ExportOptions.plist` (which currently carries only the app, so a *manual* export of an
archive containing the extension needs that entry, or an automatic-signing export).
Second consequence: the snapshot *format* is compiled into the widget as shared source
(`WidgetSnapshot.swift`) rather than by linking `WingFoilKit`, so an extension whose job is
to decode a few hundred bytes of JSON does not carry GRDB, the FIT parser and ZIPFoundation;
the half that reads library rows lives in `WidgetSnapshot+Library.swift`, which only the app
compiles.

## ADR-010 · Metric explanations are kit data, not view code
**Status: Accepted.**

Every number the app shows needs a plain-language explanation, and the explanations have to
be reachable from the card that shows the number — a glossary nobody opens is not
documentation. `HelpCatalog` lives in `WingFoilKit` as pure data keyed by a `HelpTopicID`
**enum**, so a card's `?` button cannot link to a topic that does not exist (compile-time),
and one test asserts the other half: that no case ships without written content. Wording is
derived from `docs/algorithms.md`, and where it quotes a threshold it says it is a default
rather than a law. Consequence: adding a metric to the UI forces a `HelpTopicID` case, which
fails the test until it is actually written — the glossary cannot silently rot behind the
app. Same reasoning put the share-card content (`ShareCardStats`), the list-row thumbnail
geometry (`TrackThumbnail`), PB detection and the widget snapshot in the kit: they are the
parts of a UI change whose mistakes are invisible in a screenshot — a card that prints
"0.00 kn" where it means "unknown", a thumbnail that silently stretches, a confetti burst on
the first import.

**Pictures, added later, on the same terms.** Some help topics describe a *screen* rather
than a number, and those are the ones that are genuinely hard to follow in words — the
session page's key-metrics block, the turn list, the replay, the share composer, the map's
layer chips. A topic may therefore carry one optional `HelpImage`: an **asset name** and a
one-line caption, nothing else. The kit has no image bundle of its own, so `HelpView`
resolves the name in the app's catalogue
(`ios/WingFoil/Resources/Assets.xcassets/Help/`) and draws it between the summary and the
prose — one `Image`, fit to the width, rounded, no lightbox and no carousel. The cost of
keeping only a name in the kit is that a typo draws *nothing*, silently, in a screen nobody
re-reads; so `PresentationTests` walks the checked-in image sets on disk and fails on a name
that has no `.imageset`, on an `.imageset` with no PNG, and on a caption that is a stub.
A second test pins **which** topics are allowed a picture, because the rule is the decision:
a screenshot of a number does not explain a definition, and a decorative image in a
reference work is a tax on every reader who came for the sentence. The images are captured
from the simulator with the `UI_*` hooks (`docs/testing.md`), cropped to the region the
caption talks about, and kept under 150 KB each — full colour where the budget allows,
because on the two legend shots a shifted chip colour would be a wrong answer rather than a
compression artefact.

## ADR-009 · Data-field companion **in addition to** the device app, sharing a barrel
**Status: Superseded by ADR-020** — the data field is dormant. `garmin/field/` still builds and still shares the barrel; it gets no new metrics.

ADR-002 chose a device app and that stands — it is the only way to control recording, laps and
the accelerometer. But it forces an either/or on the water: launching it means *not* using the
native Windsurf profile Jan already records with. The **WingFoil Field** data field
(`garmin/field/`, own UUID + beta UUID, type `datafield`) removes that choice: it runs inside
the native activity and contributes the same metrics as developer fields. Its costs are real
and permanent — no `ActivityRecording` control, **no `addLap()`**, 128 KB, 32 B *and* 16
developer fields per message, and every `Toybox.Sensor` entry point crashes a data field
outright (verified in the fenix 8 `api.debug.xml`), so **no accelerometer and no pump metrics,
ever**. Barometric submersion evidence and `Activity.Info.track` (COG) *are* available, so
flight and turn detection survive intact. Consequence: a new FIT source class (d) — compact
session schema, packed fields, no laps of ours (docs/fit-schema.md).
Layout: `garmin/field/` and `garmin/barrel/WingFoilCore/` sit *inside* `garmin/` rather than as
top-level `garmin-field/`. Jungles name paths relative to their own directory, so nesting keeps
every barrel reference short and symmetrical (`barrel/WingFoilCore/barrel.jungle` from the app,
`../barrel/WingFoilCore/barrel.jungle` from the field), lets both apps share one
`developer_key.der` and one `bin/`, and keeps everything Garmin under one root — while the
projects stay fully independent, since a jungle's `sourcePath` is explicit and never inherits a
sibling's sources.

## ADR-008 · Detection core extracted into the `WingFoilCore` Monkey Barrel
**Status: Accepted.**

Two apps computing "a flight" from two copies of the same state machine is how the watch and
the field would silently disagree by next season. `RingBuffer`, `SpeedRecords`,
`FlightDetector`, `TurnDetector` and a new `Config` moved into `garmin/barrel/WingFoilCore/`,
linked by both apps as a barrel *project* dependency (`base.barrelPath = .../barrel.jungle`) so
there is no export step between editing the core and rebuilding either app. The detectors used
to read the device app's `AppSettings` module directly; they now take a `Config` object in
`initialize()`, and each app fills one from its own GCM properties. The barrel carries its own
`tests/`, so **both** apps' `--unit-test` builds run the same 16 core tests against the same
sources. Barrel constraints learned: every symbol must live inside the barrel's module (a test
function at file scope fails `barrelbuild`), and class-level `const`s are instance-scoped, so
shared tables like `COMPASS` belong at module scope.

## ADR-007 · Pump detector armed only while off-foil (watch); in-flight pumping on phone
**Status: Accepted.**

Wrist accel while flying is polluted by chop and steering inputs. The live watch counter arms
only in `OFF_FOIL` (takeoff attempts — the priority metric); raw accel is logged regardless, so
the phone can analyze in-flight pumping (lulls, downwind) later without on-watch false positives.

## ADR-006 · GRDB + immutable file archive, not SwiftData
**Status: Accepted.**

Workloads are SQL aggregations (all-time records, per-gear/spot rollups), heavy background
imports, and schema migrations; no CloudKit requirement (local-first). Original FIT files are
immutable under `Sessions/<uuid>/`; analysis is a versioned derived artifact (`analysis.json`),
so the engine can always re-run. iCloud Drive folder sync is the later path, not CloudKit.

## ADR-005 · Watch approximates, phone is authoritative
**Status: Accepted.**

1 Hz + 768 KB on-watch vs unlimited offline compute: the watch ships robust approximations
(hysteresis flight detection, greedy 5×10s, alpha-lite) and maximal raw capture (1 s records,
laps, accel); the phone re-derives everything from the original FIT. Divergence is surfaced as a
tuning signal, never silently reconciled.

## ADR-004 · Record FIT sport 43 (windsurfing), discipline tag in a dev field
**Status: Accepted.**

No wingfoil sport exists in FIT-as-exposed-to-CIQ/GC/Strava/intervals.icu. Sport 43 lands as
"Windsurf" everywhere (vs the "Walk" mis-typing of FoilMotion et al.) and gets Garmin's
least-filtered Doppler speed path. Session dev field `discipline="wingfoil"` (not the sport
code) is our authoritative discipline marker. Sport user-overridable in settings.

## ADR-003 · Data pipeline via intervals.icu personal API, not Garmin APIs
**Status: Accepted** — narrowed twice since: ADR-017 admits Apple Health as a source for the workouts an Apple Watch makes for itself, and ADR-023 adds Strava. What stands is the finding this ADR is about, that no Garmin route reaches the original FIT except intervals.icu.

Garmin Connect Developer Program is business-only and paused (2026); unofficial APIs are
Cloudflare-blocked with account-ban risk; HealthKit carries no Garmin GPS routes; Strava API has
no original FIT + restrictive ToS. Jan's Garmin→intervals.icu sync is active; `GET
/api/v1/activity/{id}/file` returns the original FIT (dev fields intact). Fallbacks that always
work: Files/AirDrop import, GC "Export Original", GDPR bulk ZIP. Importer sits behind a protocol
so an OAuth2 intervals.icu client (or future Garmin API) can swap in for a store release.

## ADR-002 · CIQ device app, not data field
**Status: Accepted.**

Data fields cannot record activities, get 32 B/message dev-field budget and 128 KB RAM on
Fenix 8. Device app: 768 KB, 256 B/message, full UI/input/alerts, `Communications` for the
phase-5 companion link. minApiLevel 5.0.0 (all shipped Fenix 8 firmware).

## ADR-001 · Monorepo with a Python lab and golden-file contract
**Status: Accepted.**

Detection algorithms are tuned in `lab/` (fitdecode + scipy) against real labeled sessions,
frozen as golden JSONs, then ported: Swift (authoritative) and Monkey C (live approximation)
assert against the same goldens/clips. Parameters live once in `docs/algorithms.md`.
