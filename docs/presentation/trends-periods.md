> Part of `docs/presentation.md`. Engine 0.25.0.

## Trend charts — one set, one name each

Both platforms draw the same per-session series under the same titles. They had drifted
into plotting *different metrics under similar names*: the web's "Clean jibe rate" was the
score verdict over every counted turn, its "Clean jibes by entry tack" was the same verdict
per side, and iOS's chart in the same slot was the jibes' flew-through share. Three names,
three numbers, none of them clean jibes.

| chart | what it plots |
|---|---|
| **On foil** | `foilPct` |
| **Longest flight** | `longestFlightS` |
| **Flew-through rate** | counted turns that never lost the foil, over counted turns |
| **Clean jibes** | `jibesSuccessful`, per session |
| **CPH** | `cleanJibesPerHour` |
| **JPH** | `jibesPerHour` — dry jibes per hour |
| **TPH** | `turnsPerHour` — dry counted turns per hour |
| **Best 2 s** | `records.best2sKn`, in knots |
| **Flew through by entry tack** | the flew-through share of the turns *entered* on each tack |

Plus what only one platform can draw: iOS adds "Pumps to takeoff" and "Port / starboard",
the analyzer adds "Avg pumps to takeoff". The entry-tack split moved from the score verdict
to the outcome on the web side, which is digest schema 8 (`bySide.flewThroughPct`); a
session stored before it has no point on that chart, which is what a gap in a line already
means.

**The three rates are one row of this table, not one metric with two optional extras.**
Rates are additive (docs/algorithms/rates.md, "Session rates"): TPH says how busy the afternoon
was, JPH says he got away with the jibes, CPH says he rode them, and a page that draws only
the strictest of the three answers one of the three questions a rider asks. They sit in that
order, each reading its own engine field — the two new ones are digest **schema 11** and GRDB
**v17**, and neither is derived by a reader, because both numerators are *dry* counts and
neither the digest nor the session row carries the jibe-level `fellIn` tally to subtract with.
A row written before them has a gap in those two lines, never a zero.

**Best 2 s is the one speed series, and the only chart that marks its own points.** Knots on
both platforms, like every other speed in both apps. A class-(c) session differentiated its
speed from positions, which reads high, so its point is drawn — it is still his afternoon —
and drawn marked, the same claim in the same word the Records table makes about an all-time
best. The two platforms say it in the idiom each already has: the analyzer draws that point
as an **open ring** (shape, not a second hue, so it survives a colour-vision check) with the
word in its tooltip and an `uncertified` badge on the chart head, and iOS writes one caption
line under the chart — *"1 of 10 had no speed channel…"* — beside the caption it already uses
for sessions that cannot report a metric at all.

## Trend weeks — ISO-8601, Monday, local

The "sessions per week" histogram buckets by **ISO-8601 week, Monday start, in the session's
own local time**, zero-filled between the first session and the last — a week with no session
is a bar of height 0, because that *is* the information, and a season with its quiet
fortnights removed is a season nobody had.

Monday is stated rather than inherited on both sides. iOS cuts the buckets with
`LibraryStore.isoCalendar` (`firstWeekday = 2`, `minimumDaysInFirstWeek = 4`) **and hands the
chart the same calendar**, because `BarMark(…, unit: .weekOfYear)` bins a second time under
the environment's calendar and a Sunday-first locale would draw every bar a day early; the
analyzer cuts them in `library._weeks`, in Python, and `js/trends.js` only places rectangles.
The boundary both sides pin is the same one: a Saturday and the Monday after it are two
different weeks, and the Sunday between them belongs to the **earlier** one.

## Periods — a month, a season, a trip, or a range you type

A session is an afternoon. Everything above describes one. **A period is a set of them**,
and the four ways of naming a set are all answered by one block of numbers in one order —
because "how was August" and "how was Garda" and "how has the season gone" are the same
question asked of different afternoons, and answering them in three different vocabularies
would be three different apps.

**Python is the reference implementation.** `web/lab_bundle/library.py` (`periods`,
`period_block`, `custom_period`) decides which afternoons belong to which period and what
the block says about them; `LibraryStore.periods` / `periodBlock(from:to:)` and
`PeriodBlock` say the same things in Swift. The two are pinned against one file —
`fixtures/periods/periods.expected.json`, ten synthetic afternoons and Python's answer
about them — read by `PeriodTests` on iOS and re-derived by `verify_library.py` §6b. Two
hand-written test suites agreeing today is not two implementations that cannot drift.

### The four kinds

| kind | rule | title |
|---|---|---|
| **month** | the calendar month of the session's **own local day** | `August 2026` |
| **season** | **1 April → 31 March**, named for the year it opened in | `Season 2026/27` |
| **trip** | one spot, no gap wider than **3 days**, at least **2 sessions** | `Nago Torbole · 31 Jul – 6 Aug` |
| **custom** | any start/end day, **inclusive at both ends** | `31 Jul – 6 Aug 2026` |

- **The local day, not the UTC one** — the `dateLocal` rule the trend weeks already follow.
  A session that starts at 22:30 UTC on 31 August at +02:00 is a **September** afternoon
  where the rider was standing, and a month bucketed on the instant would file it under the
  month before it happened. iOS cuts on `SessionRow.displayZone`; the analyzer on the
  digest's `dateLocal`.
- **The season cut is the one the Trends range picker has always used** (`TrendRange.season`),
  reused rather than invented a second time: one Northern-hemisphere water year, so a
  February afternoon still counts towards the winter it belongs to. A season that **has not
  crossed a year** is just `2026`; the second half of the name appears once there is a
  second half of the season to name.
- **A trip is detected, not filed.** Three days, because a holiday has rest days, blown-out
  days and travel days in it and a Tuesday off does not end a week at Garda; four days apart
  is a second visit. Two sessions, because one afternoon somewhere is a session and a
  heading has to be worth a heading.
- **A trip clusters on coordinates, never on the spot's name.** This project's own corpus
  spells one beach three ways — `nago-torbole-windsurfen`, `-foilmotion`, `-wingfoiling`,
  because the analyzer derives a spot from the filename — so a trip detected by name would
  turn one week at Garda into three holidays. The radius is **3 km**, deliberately looser
  than the phone's 500 m spot radius (`SpotClusterer.defaultRadiusM`) because the question
  is different: the spot table is naming *launches* and wants the beach, and a trip is asking
  whether two afternoons were the same holiday. Torbole and Malcesine are one week at Garda
  and 15 km apart. The clusterer itself is shared — `SpotClusterer.cluster` on iOS,
  the same greedy single-link assignment against a moving centroid in `library._spot_clusters`.
  - A session with **no anchor fix** (a recording with no positions, or a digest written
    before schema 7) cannot be placed, and falls back to the spot it already answers to:
    its `spotId` on iOS, its filename-derived name in the analyzer. Weaker, and the reason
    the coordinates were added — but a library saved last month must still produce trips.
  - A cluster is **named** by the spot name most of its afternoons carry, ties to the
    earliest, because the first name a place was given is the one the rider has been reading.
- **Same exclusions as the records tables** (`counts_towards_records`, `LibraryStore.clause`):
  the bundled example, a provisional watch row and a friend's afternoon are in nobody's
  holiday. The existing `LibraryFilter` (spot / gear / since) applies on top.

### The aggregate block — one list, one order, both platforms

| # | key | label | how it is derived |
|---|---|---|---|
| 1 | `sessions` | sessions | count |
| 2 | `hours` | hours on the water | Σ `summary.durationS` (T1, the engine's cleaned span) |
| 3 | `distance` | distance | Σ `distanceKm` |
| 4 | `flights` | flights | Σ `flightCount` |
| 5 | `foilPct` | on foil | Σ foil time ÷ Σ **on-water** time |
| 6 | `cleanJibes` | clean jibes | Σ `jibesSuccessful` |
| 7 | `cph` | CPH · clean jibes per hour | clean jibes ÷ Σ `summary.timerTimeS` (T2) |
| 8 | `turns` | turns | Σ counted turns |
| 9 | `cleanJibeRate` | clean-jibe rate | Σ clean ÷ Σ jibes, ≥ 5 jibes |
| 10 | `wph` | WPH · swims per hour | Σ fell-in flight ends ÷ Σ `summary.timerTimeS` (T2) |
| 11 | `best2s` | best 2 s | max |
| 12 | `best10s` | best 10 s | max |
| 13 | `longestFlight` | longest flight | max |
| 14 | `longestDryStreak` | longest dry streak | max |
| 15 | `spots` | spots visited | distinct clusters |

- **Rates over a period use the summed denominators, never the mean of the per-session
  rates.** Ten minutes with one clean jibe and three hours with three is not "6.0 and 1.0,
  so 3.5 an hour"; it is four clean jibes in three hours and ten minutes. The same rule
  already governs the library totals' on-foil share and the gear rollup's.
- **Two clocks, and what a number *is* decides which one it gets: every displayed duration
  is T1, every rate denominator is timer time.** "Hours on the water" is a duration, so it
  sums `summary.durationS` — the *cleaned* first-to-last span, gaps included — like every
  duration on every surface. CPH and WPH are rates, so they divide by summed
  `summary.timerTimeS`, the session minus its pauses, which is what the engine's own
  `cleanJibesPerHour` and `wetPerHour` divide by since 0.13.0 (docs/algorithms/rates.md, "Session
  rates"). A month holding a single afternoon has to report that afternoon's CPH and not a
  second opinion about it, and until 7 Sep 2026 it reported one *under* it: the block summed
  T1 for the rates too, so every paused break the rider took deflated his own month.
- Neither clock is the row's other duration: the analyzer's `durationS` is the FIT's
  `total_elapsed_time` and the iOS row's is the raw sample span, and on the corpus's
  Rheinstetten afternoon those are 10338 s against 7742 s of T1 against 4712 s of timer. So
  both platforms store both engine clocks beside it — digest schema 7 `rateDurationS` and
  schema 9 `timerTimeS`, GRDB v12 and v13. A row saved before either falls back one step at
  a time (timer → elapsed → the row's own duration): elapsed is the closest clock it stores
  and is the number it was already divided by, which is a smaller error than dropping the
  afternoon out of its own month.
- **On-foil share is weighted by time on the water**, not by elapsed time and not as a mean
  of the percentages: the engine divides by its own cleaned timer time, which excludes the
  gaps and the parked stretches, and summing elapsed time instead reports a library-wide
  share about 19 points below every session in it.
- **WPH counts every fell-in flight end**, straight-line swims and turn swims alike — what
  `summary.wetPerHour` counts, and emphatically not the turn ladder's `fellIn`: most of a
  session's falls happen outside a counted turn, and the water does not care. Both platforms
  store the count (digest `wetExits`, GRDB v12).
- **The clean-jibe rate keeps its ≥ 5 jibes floor**, over the *period's* total: four clean
  out of four is a good week and it is still not a rate. One constant on each side
  (`SessionRecordKind.minJibesForRate`, `library.MIN_JIBES_FOR_RATE`).
- **An entry the period cannot supply is omitted** — never a dash, never a zero. That is the
  block's half of "a missing value is absent, never 0", and it is also what lets the card
  leave a number out rather than print a made-up one. A measured zero is still a value and
  prints as one (`0.0` swims per hour).
- The formatters are the key-metrics block's own (`KeyMetrics.duration` / `km` / `knots` /
  `rate`, and their Python twins), so a duration on a period card reads the way a duration
  reads on a session card.

### The period card

**A second card kind, and deliberately the same card.** Same three shapes at the same pixel
sizes, same footer — the mark, `CleanJibe · cleanjibe.org` above the tagline, QR — same
title-and-one-caption header, and since 26 Sep 2026 the same **layout B v2**
(docs/presentation/session-time-video.md, "The share card carries the same block"): the tracks, a hero number, the
outcome bar, the best streak and one ribbon in words, packed from the footer up so every
shape — the landscape included — keeps its words clear of the footer. There are no
Lean/Complete presets any more. What differs is only what is being described.

| | session card | period card |
|---|---|---|
| numbers | the key-metrics block | the aggregate block, and `card` beside it (below) |
| heroes | clean jibes → max 2 s → tacks | clean jibes → best 2 s → **sessions** ("12 sessions / at 3 spots") |
| bars | jibes, and tacks where there were any | **one** bar: jibes when every counted turn was a jibe, turns otherwise |
| ribbon | clean jibes / h · dry jibes or turns / h · max 2 s · duration · distance | clean jibes / h · dry jibes or turns / h · sessions · time on the water · distance |
| date line | the session's day and start | the period's span |
| title default | the session's name | the period's title |
| artwork | the track outline | **the period's outlines, stacked** |
| map background | optional, off by default | optional, off by default — **offered only where the period is one place** |
| speed disclaimer | on a class-(c) source | never |

- **The story beyond the block is `period.card`** (`library.period_card`, `PeriodCard` in the
  kit): the outcome ladder summed over the rows that carry it, the jibes and tacks, the best
  flew and dry streaks, every fall, and the dry rate — dry turns (or jibes) over the timer
  hours of those same rows, one decimal. A stored row carries the ladder over *every*
  counted turn, not one per kind, so the bar is the jibe bar only when the period had no
  tack and every counted turn was a jibe (`dryKind`), and the turn bar otherwise — never a
  tack bar invented out of a total.
- **With 0 clean jibes the clean number and clean jibes / h are left out**, as on the session
  card, and the hero falls back to the best 2 s, then the session count. Only the heroes the
  period can carry are offered; the choice is the session card's one stored preference.
- `Story.make(period:hero:)` (kit) and `periodCardStory` (web/js/cardstats.js) are pinned
  against `fixtures/cards/period-stories.expected.json`: card_parity.mjs dumps the
  browser's for every fixture period and hero, `verify_presentation.py` §5d re-derives the
  rule and asserts the words-to-footer gap on every shape, and `PeriodTests` holds the kit's.
- **No disclaimer.** "Speeds from a degraded source" is a claim about *one* recording's
  speed channel; a period spans several, and marking a whole holiday because one afternoon
  came from a GPX would answer a question nobody asked. The one speed on the card is a
  record, and the records table is where a record's certification is stated.
- **The artwork is every session's outline, laid on one another**, faint, with no marks: a
  period has no single ride and picking one would be picking a favourite, while a week at
  one spot laid over itself is recognisably that beach. Fifty outcome dots per session times
  a dozen sessions is confetti, and the card's own numbers already say how the maneuvers
  went. The opacity falls with the count so a dozen read as one shape rather than a scribble.
  - **One placer, fitted to the union of the tracks' metre extents**, on both platforms — so
    every outline is at one true metres-per-point and a short session draws small *inside* a
    long one rather than being stretched to match it. That is the whole difference between a
    picture of a week and twelve identical rides: a thumbnail is normalized against its own
    extent, which is right for a library row (every session reads as one consistent shape)
    and exactly wrong here.
    - iOS therefore **carries the extent with the thumbnail** — `TrackThumbnail.Bounds`, the
      metre extremes and the equirectangular anchor the unit box was projected around, which
      `metres(x:y:)` inverts exactly and `coordinate(x:y:)` turns back into degrees.
      `TrackThumbnail.currentVersion` is 3 because of it: a v2 blob decodes perfectly well
      without the key, so nothing but the version bump would have rebuilt it, and a
      boundless outline is one the stack and the map would both silently drop.
    - The arithmetic itself is one rule with two spellings — `TrackStack.placement` in the
      kit and `stackPlacer` in `web/js/sharecard.js` — pinned against
      `fixtures/periods/outlines.expected.json`: a set of polylines in metres, a box in
      layout points, and every placed vertex. Uniform in both axes, an axis narrower than a
      centimetre imposes no limit, and a stack with no extent at all is placed at one point
      per metre rather than dividing by zero.
- **The map background is offered only when the period is one place.** A period has no single
  ground *in general*: its sessions may be 15 km apart, and the framing question ("which
  rectangle of the earth?") then has no answer a card can take for granted — the union
  bounding box of a month split between Garda and the Rhine is mostly the motorway between
  them, at a zoom where neither beach is visible.
  - So the ground is offered exactly when **every session in the period lies in one spot
    cluster** — the same greedy clusterer and the same 3 km trip radius that decided whether
    those afternoons were one holiday — **and every one of them was placed by a fix**. A row
    with no anchor is clustered by the name of its file, which is enough to file it under a
    spot and not enough to point a camera at one. A trip is one place by construction; a
    month, a season or a typed range is one when the rider only rode one beach in it.
  - Where it does not hold the switch is **not offered**, never offered-and-inert: a control
    that is on and does nothing is worse than a control that is not there.
  - The rule is decided **once, engine-side** — `library._map_ground`, handed to the browser
    as the period's `mapGround`, and `LibraryStore.period` on iOS — because a second copy of
    a clustering rule in a view is a second answer to "was this one place". Both are pinned
    by `fixtures/periods/periods.expected.json` like every other field of a period, and
    `verify_presentation.py` §5d re-derives it from a second copy of the rule.
  - When it is on, the ground is the **union bounding box of all the period's tracks**, under
    the same contract the session card's map has, clause for clause: the ride fills exactly
    the box the layout already gave it and only the margins become map, the breadcrumb is
    placed through the map's own projection (one anchor per session — each outline's metres
    are in a frame of its own), the same scrim and dark stat plates, the same attribution
    footer, and the same silent degradation to the plain card when there is no network, no
    tile server or no anchor. The same per-device preference as the session card's
    (`wingfoil.shareCard.map.v1`, `ShareCardMapStore`), read but only honoured where it can
    be. iOS takes one `MKMapSnapshotter` image for the whole period
    (`ShareCardMapper.makeStack`); the web composites one OSM tile grid (`buildStackMap`).
- **Entry points**: the Periods screen on iOS (a share button on every period and on the
  custom range), and the Periods section of the Records tab on the web (a "Share card"
  button per period), both opening the composer the session card already uses.
- **The rider's title and caption are transient on both platforms** here, unlike the session
  card's on iOS: a period is not a row in the library, so there is nothing to rename. The web
  remembers them per period key in `localStorage`, the way it already does per session.

### Enforcement

`fixtures/periods/periods.expected.json` (ten synthetic afternoons + Python's answer) is
asserted by `PeriodTests` on iOS and re-derived by `verify_library.py` §6b, so a stale file
cannot pin the phone to an answer the analyzer no longer gives. The same file now carries a
`trends` block — every chart of "Trend charts — one set, one name each" over those same ten
afternoons — which `TrendSeriesTests` reads back through `LibraryStore.trend`, line by line
and session by session. Three of its charts hold no point at all (the fixture carries no turn
outcomes, no per-side split and no pump tally) and that half is as load-bearing as the rest:
both platforms have to answer *absent*, never a flattering zero. `verify_library.py` §6 asks
the third question neither can — handed the fifteen real recordings in `fixtures/sessions/`,
does the rule find the week a person would name? (It finds one Garda week of twelve
afternoons, 31 July to 7 August 2026.) `card_parity.mjs` dumps the period card beside the
session card and `verify_presentation.py` §5d asserts, per period, that `complete` **is** the
block, that `lean` is that block filtered — the same two assertions §5 makes about the session
card — and that `mapGround` is what a second copy of the one-cluster rule says it is.

The card's *picture* is pinned the same way. `fixtures/periods/outlines.expected.json` carries
a set of outlines in metres, a box in layout points and every placed vertex;
`TrackStackTests` holds `TrackStack` to it and `verify_presentation.py` §5e holds
`stackPlacer` to it, re-deriving the file from `make_presentation_goldens.py` first so a stale
fixture cannot pin either platform to an answer the rule no longer gives. §5e also asserts the
thing the shared scale is *for*: three tracks of three different lengths come out at three
different drawn widths, and the longest is the one that fills the box.

## Marker eligibility

- Turns with `counted == false` are excluded from every marker, tally, list and trend.
- Pump episodes: only `success` and `failed` get markers. `recovery`, `in_flight` and
  `unknown` are counted where the analysis counts them but are **not** attempts and are
  never drawn.
- **Pumping spans = the `success` and `failed` episodes' `[startTs, endTs]`** — one span per
  attempt, both halves, on the track and as a chart band. Not one per *takeoff run*: that
  spelling drops every failed attempt, and the two counts differing between the platforms is
  precisely what the presentation goldens exist to catch (`pumpingSpans`).
- A straight-line flight end whose outcome is `glide_out` is the green end of the ladder and
  is counted under `flewThrough`, drawn hollow. There is no separate "glided out" layer or
  chip: fill carries the channel, colour carries the verdict, and a third category would say
  the same thing twice.
- **"Wrist under" is the engine's `submersions` list, one mark per entry** (engine
  0.16.0), placed at the episode's `ts` — the sample the pressure stepped. The UI never
  re-derives it from the mask, and never from the `submerged` flags on turns and flight
  ends, which are the *verdict* inputs and stay exactly where they are. The legend tally,
  the thumbnails, the share card and both platforms' maps all count the same list, which
  is what `splash` in the presentation goldens pins.

## Filter semantics

Turn filters are type (`both | jibes | tacks`) × side (`both | port | starboard`), ANDed.
**Side means the ENTRY tack — the tack you came into the turn on — never the rotation
direction.** UI copy must say "Port entry / Starboard entry"; bare "left/right" is a
misread waiting to happen. Both turn fields exist in the schema (`side`, `direction`);
filters and trends read `side`. Anything that draws a side in colour uses the `side.*`
tokens above and nothing else.

