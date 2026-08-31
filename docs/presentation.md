# Presentation contract — UI semantics all implementations follow

`algorithms.md` holds the parameters the three analysis implementations follow; this file
holds the *presentation* semantics the UIs follow. Two full implementations exist today —
the iOS app (SwiftUI) and the web app (inline SVG) — plus the watch's colour vocabulary,
and nothing but convention kept them aligned until this contract. The rule is the same as
for the engine: **semantics are defined once, here. An implementation that needs to deviate
changes this file first, in the same commit.**

Colour *values* live in `design/tokens.json`, which generates the Swift constants
(`DesignTokens`), `web/css/tokens.css`, `web/js/tokens.js` and `garmin/source/DesignTokens.mc`
and is staleness-checked in CI (`design/check_tokens.py --check`). A value is edited there and
nowhere else; this file defines the *meanings*.

**The watch (device app ≥ 0.8.0).** It consumes the `hex` half, like the web: `Dc.setColor`
takes a literal `0xRRGGBB` on every product in `garmin/manifest.xml`. Each token additionally
carries a generated `_MIP` twin — its nearest colour in the fixed 64-entry `{00,55,AA,FF}³`
palette that the 8 bpp products (both fenix 8 Solars, the whole fenix 7 family) quantise to.
The firmware does that snapping itself, so the twin changes no pixel; it exists so the
fallback is a reviewable value and so palette *collisions* are visible in the generated file
rather than on the water — on 8 bpp, `phase.flying`, `effort.takeoff` and `effort.splash` all
land on `0x55AAFF`, and `outcome.touchdown` and `effort.window` both on `0xFFAA00`. None of
those pairs is drawn on one watch screen. `garmin/source/ui/Ink.mc` picks the half per device
and is also where the one contrast concession lives: the "off" half of a two-state mark is
`COLOR_DK_GRAY` on AMOLED over true black, and the phase grey on a reflective MIP, where dark
grey over a mid-grey ground in sun is nothing at all.

Until 0.8.0 the watch reused `Graphics.COLOR_GREEN` for *both* the phase tint and the ladder's
"flew through", which broke on the Timeline page in particular — foil-fraction bars and turn
outcome dots, six rows apart on one screen, in one ink for two meanings. The phase tint is now
the teal, on the ring, the foil-% arc, the flight timer, the timeline bars, the breadcrumb and
the summary's track; green is the verdict and nothing else. Heart rate left the ladder's red
for the effort indigo (a pulse is not a swim), and the PB celebration left green for the
effort orange (a record is something the rider *did*, not a verdict).

## Layers

| id | shows | default | notes |
|---|---|---|---|
| `flying` | track tinted on-foil | visible | phase tint, not a marker |
| `offFoil` | track tinted off-foil | visible | |
| `effort` | the selected GP3S record window glowing on track + shaded on chart | visible | window choice is the record picker's (below) |
| `flewThrough` | turn outcome markers, flew | visible | |
| `touchdown` | turn outcome markers, touchdown | visible | |
| `fellIn` | turn outcome markers, fell in | visible | |
| `courseChange` | rejected sweeps (bear-away / round-up) | visible | grey — a non-verdict |
| `pumping` | pump-burst spans on the track | visible | spans, not markers |
| `takeoff` | takeoff attempts, BOTH halves: successes and failures | visible | one chip hides both halves together |
| `splash` | submersion moments | visible | |
| `direction` | course-of-travel chevrons along the track | visible | decimated by on-screen spacing |

Layer visibility persists on iOS (hidden-set, `mapLayerVisibility.v1`; unknown ids must
decode harmlessly so old prefs survive new layers) and is transient on web. Legend chips are
the only toggle surface; a struck-through chip means hidden.

**Chip text is the layer catalogue's `label` in `design/tokens.json`** — flying · off foil ·
pumping · direction · flew through · touchdown · fell in · course change · takeoff · splash
— read from the generated constants on both platforms, never written as a literal in a view.
The one exception is `effort`, whose chip is labelled with the *selected* window ("best 2 s")
because that is what it is currently highlighting; the catalogue's "best effort" is the
fallback for a session with no achieved window.

## Colour and glyph vocabulary

**The outcome ladder is a verdict scale and nothing else may borrow it:**
green = flew through · orange = touchdown · red = fell in · grey = course change (no verdict).

**Fill carries the channel:** solid = a maneuver's outcome; hollow = a straight-line flight
end no turn explains. Same dot, same ladder, different fill.

**Effort-and-water layers sit deliberately outside the ladder** — nothing in them is a
verdict, and borrowing the ladder would make a takeoff look like a good jibe:
pumping = indigo (spans) · takeoff = blue (glyphs) · splash = cyan (drop glyph) ·
the selected record window = orange, one ink for both of its marks (the glow on the track
and the shading in the chart).

**Takeoff glyphs** (glyphs, not dots, so they can't be mistaken for outcomes on a busy
track): filled up-arrow = pumped takeoff ("this cost something") · hollow up-arrow = free
takeoff (wind alone) · **hollow red u-turn = failed attempt** — the one event in the effort
layers that *has* an outcome, so it alone borrows the ladder's red, and shape + fill carry
the distinction on two more channels for anyone who cannot use colour.

On sources without an accelerometer stream every takeoff renders as the filled (pumped)
arrow; free takeoffs cannot be distinguished without stroke counts. The engine reports
neither half of the split there (`freeTakeoffs` / `pumpedTakeoffs` are absent and every
takeoff carries `free: false`), so both apps draw the same arrow rather than inventing a
verdict about effort nobody measured.

**Entry tack has its own pair, and it is the only thing allowed to use it:**
`side.port` / `side.starboard`. A side is not a verdict, not an effort and not a phase, so
it may borrow none of their inks — and a symmetric pair needs a symmetric encoding, so the
two are **one hue at two intensities, with the quieter half dashed as well**. The dash is
not decoration: it is the second channel that carries the split for a reader who cannot use
colour, the same job fill does for the outcome dots.

This is a token rather than a convention because it was already broken twice on one screen.
Trends drew "turn success by entry tack" with port in the takeoff blue and starboard in the
**ladder's green** — on a chart whose subject is *"% flew through"*, so the green line read
as the flew-through line — and the port/starboard share chart above it in a **magenta
belonging to no vocabulary at all** (`app-ui-review.md` §5.2, §5.3). Both were only ever
literals in a view, which is exactly what `design/tokens.json` exists to prevent.

**Phase tints** are one colour each, in both apps: flying = teal, off foil = the secondary
label grey. They are *not* the app's own accent blue — a track tinted with the brand colour
reads as chrome, and the flying tint has to be a category. **Every flight fact takes the
phase tint**, which includes the "longest flight" trend line — it wore the takeoff blue
until §5.4, for a metric that is a duration in the air rather than an effort.

**Phase tint follows the engine's flight spans, cut at exact boundary times with
interpolated points — a gap with no samples still renders off-foil.** Tinting per *sample*
("is this fix inside a flight?") is the wrong question on a coarse source: at 2 s cadence
with a 5 s p95, an off-foil span of 5–7 s can contain no positioned sample at all, and the
two flights on either side of it then tint as one continuous flight with a takeoff arrow
apparently mid-flight. So the polylines are cut at the engine's own `start_t` / `end_t`: the
cut coordinate is interpolated between the two positioned samples that straddle the boundary
(a boundary that falls *on* a sample cuts there, and the sample belongs to both runs — a
shared vertex, so the drawn line has no hole), and every off-foil span therefore renders as
at least a short grey stub. The interpolated point lies on the line the map already draws
between those two fixes, so the cut changes the colour and never the geometry. A recording
gap still breaks the line — except across a boundary cut, where the two straddling fixes are
the only evidence there is of where the phase changed.

**Direction chevrons**: small, semi-transparent, oriented to travel, subordinate to every
marker — they indicate, never compete.

## Key metrics — the block that opens the session

Both apps open the session analysis with the same block, above the map and the chart, in
the same four rows, numbers big and labels small. It exists because `app-ui-review.md` §1.1
measured the alternative: on a 6.9″ phone the first actual result sat one and a third
screens below a map, ten legend chips and three paragraphs of legend documentation.

| row | content |
|---|---|
| 1 | duration `h:mm` · distance · average speed |
| 2 | the best 2 s record, labelled **"max 2 s"** |
| 3 | the outcome tally on the ladder's inks · the two turn streaks |
| 4 | **JPH** (dry jibes) and **WPH** (`docs/algorithms.md` "Session rates"), one decimal |

The rules, which are the only thing the two implementations can disagree about:

- **Duration is rounded to the nearest minute, never truncated.** `0:00` over a recording
  that exists reads as a failure to measure.
- **Average speed is converted to knots.** The engine reports `avgSpeedKmh`, but every
  other speed in both apps is knots, and a km/h number in a column of knots is a misread
  waiting to happen. It is a session-shape number — elapsed time, gaps included — and never
  a record: the GP3S block is still the only place records live.
- **Row 2 names the window, not the peak.** "max 2 s", the same rule the record picker's
  chip follows; "max speed" over a 2 s window would be the overclaim that rule exists to
  prevent.
- **Row 3 is the jibe ladder**, and the caption says what the three numbers are out of
  ("of 50 jibes"). A session whose wind axis never resolved has no jibes at all, so it
  falls back to every counted turn ("of 51 turns") — an empty ladder over an afternoon of
  turns would read as "nothing happened". The tally is a verdict, so it may wear the
  ladder, and the **library row** wears it too — over every counted turn there, which is
  what a row scanned against its neighbours has to be. The web rows carried no tally at all
  until §5.6, on the more prominent of the two library surfaces; a row from a digest
  written before the field existed renders "—" rather than three zeroes.
- **Streaks are `summary.turns.longestDryStreak` / `longestFlewStreak`**, rendered
  `11 dry · 5 flew` — the first time either app draws them. They are over counted turns,
  which is what the engine measures them over; nothing is re-derived here.
- **JPH is dry jibes, and the label says so.** The engine's `jibesPerHour` counts the jibes
  he came out of still sailing (`docs/algorithms.md` "Session rates", engine 0.7.0), so the
  cell is captioned **"JPH · dry jibes per hour"**. A rate that counted the swims too could
  be raised by falling more often, and a caption reading "jibes per hour" over a number that
  excludes seven of them would name a different figure than the one printed.
- **Row 4 degrades JPH to TPH, not to zero.** When `jibesPerHour` is 0 while
  `turnsPerHour` is positive — turns the wind axis could not name — the row shows
  `turnsPerHour` labelled TPH. WPH needs no fallback: a fell-in flight end is a fall
  whatever the wind was doing. A session with a duration and genuinely no turns keeps JPH
  at `0.0`, because that is a measured zero.
- **No duration, no row.** `durationS <= 0` makes the engine report all four rates as
  null, and row 4 disappears — the general rule ("a missing value is absent, never 0")
  applied to the one place where a 0.0 would read as a verdict on the rider.

Implemented once per platform: `KeyMetrics` in `ios/WingFoilKit/…/Presentation/`, whose
strings `PresentationTests.keyMetrics*` pin, and `keyMetrics` in `web/js/render.js`. The
Swift half resolves every display string so the SwiftUI view is pure layout; the two are
twins, and a difference between them is a bug.

### The share card carries the same block

The exported card shows **this block and nothing else**, re-laid-out as cells: same keys,
same order, same labels, same strings, and the tally's three counts kept as counts so they
can wear the ladder there too. A card is the one artefact that leaves the device and is read
next to nothing, so it is the last place either app may name a different number for the same
session — `ShareCardStats.make` takes the rendered `KeyMetrics` rather than rebuilding
anything from the index row.

**Both platforms compose one now.** The web's composer is `web/js/sharecard.js` (a canvas at
the same three pixel sizes, with a live preview, Download PNG, and a Share… button wherever
`navigator.canShare({files})` is true); its content comes from `web/js/cardstats.js`, which
is the same move the Swift side makes and for the same reason — `keyMetricEntries` is the one
list, `keyMetrics` in `web/js/render.js` renders its HTML from it, and `cardStats` can only
filter it. `web/tools/verify_presentation.py` §5 asserts, per fixture, that the card's stat
list *is* the rendered block.

Two presets choose how much of it appears, and a preset may only **remove** entries:

| preset | cells |
|---|---|
| `complete` (default) | the whole block: duration · distance · avg speed · max 2 s · tally · streaks · JPH/TPH · WPH |
| `lean` | duration · distance · max 2 s · tally |

The card's outline carries three semantics and no more (`TrackThumbnail.Mark`): the track
tinted by foil state, a dot per **counted** turn on the verdict ladder's inks, and the
barometer's submersion evidence as a cyan **diamond** — shape as well as colour, because a
splash usually sits on the fell-in verdict it belongs to. Course changes get no dot, by the
same rule the map draws by. Nothing else from the map's eleven layers survives the shrink.
**The footer is a contract of its own, and both platforms print it identically**: the app's
mark, the wordmark **CleanJibe**, the call to action `analyze your wingfoil sessions free —
cleanjibe.org`, and a **QR code to `https://cleanjibe.org`** in the trailing corner. The card
is the declared promotion channel — it leaves the phone as a PNG and is read in somebody
else's chat by a rider who has never heard of the app — so the footer is the only part of it
addressed to the receiver rather than to the sender, and it may not differ between the card
the phone exports and the card the web composes. The strings come from `Branding` in the kit
(`appName`, `callToAction`, `siteURL`), pinned by test, and from `BRANDING` in
`web/js/cardstats.js` on the other side — one constant per platform, never a literal at a
draw site.

Two details of the QR are load-bearing rather than cosmetic and are the same on both
platforms: it is **dark-on-light with its own light plate**, because the card's background is
navy or somebody's photo and a decoder needs the light half to be light; and it is drawn at
**~96 px at 1080 width** from a **nearest-neighbour** upscale with a four-module quiet zone,
because the generator emits one pixel per module and any smoothing turns every module edge
into a grey ramp for a decoder to guess at after a chat app has recompressed the picture. iOS
renders it with `CIQRCodeGenerator` (`ios/WingFoil/Features/Share/BrandQRCode.swift`) at
correction level M — a short URL, a clean digital image, and bigger modules matter more here
than damage tolerance. The web draws the same symbol from a committed 33 × 33 PNG
(`web/icons/qr-cleanjibe.png`, one pixel per module, quiet zone included) with
`imageSmoothingEnabled = false` at 99 px, which is the same 3× nearest-neighbour upscale: the
URL is fixed, so a QR library in the bundle would be a dependency to draw a constant.

Note the case, which is deliberate: **CleanJibe** is the brand, *wingfoil* in the call to
action is the sport. The word WingFoil survives only as the Xcode target, the module and the
bundle ids (`de.lahmann.wingfoil.*`, unchanged — renaming them would orphan the TestFlight
build, the BGTask registration and the keychain), and as the name of the **Garmin watch app**,
which the phone app still refers to by that name where it means that app.

The same footer closes a replay clip (`ReplayClipCards`), which is the frame a viewer is left
staring at while the clip loops — the one frame worth pointing a camera at.

## Sections — how a session divides

Both apps open on the key-metrics block and then **switch between four sections**, in this
order: **`Map · Speed` · `Turns` · `Takeoffs` · `Effort`**. The ids and the words are
`SessionSection` in the kit; the web uses the same ids on `data-section` attributes. The
alternative was measured: one column of ~3 800 pt on the phone and ~6 000 px on a phone
browser, five unrelated subjects deep, with no way to the fifth except through the other
four (`app-ui-review.md` §3.1, §7.2).

- **The key-metrics block is above the switcher and is never a section.** It is the answer
  to "was that a good session"; a page you can navigate away from is not an answer. There
  is therefore no `Overview`.
- **The map and the speed chart are on one section, always.** "Scrub and zoom" below
  mandates one playhead across them and "Pairing" focuses the chart on the flight whose
  track you tapped — they are one instrument with a *visible* link, and a switcher that
  gives Map its own page breaks the half of it you can see. Everything that annotates the
  two figures rides with them, which is why the record picker lives there too and why there
  is no `Records` section: a picker whose whole purpose is to highlight a window on the map
  and the chart cannot be on a tab away from them.
- **The chart's zoom window outlives a section change.** Zoom stays transient per *session
  view* (below), but a trip to Turns and back is not a new session view, and silently
  resetting the window would make "transient" mean something the rider did not ask for.
- **Desktop web keeps its single scroll — this is a phone rule.** Above 760 px the web
  session view is a document, the two long tables want the continuous page, and that is
  what makes it a lab tool. The switcher exists only below the breakpoint, and crossing the
  breakpoint upward must restore every panel.
- **A section with nothing in it is not shown.** The web has no HR card, so its fourth chip
  is the raw-output panel (`Data`) rather than an empty `Effort`; an honest label beats a
  matching one. When the web gains effort content, the id is already reserved.

## Tables over tile walls

Where a screen shows one number per row with the same shape on every row, it is a table:
`record | value | at` for the session's speed records, `record | value | +Δ PB | when ·
where` for the all-time ones. Eight 2-up cards spent ~520 pt and ~2 000 pt respectively to
show eight numbers each, and the values could not be compared by eye because they did not
line up in a column (`app-ui-review.md` §1.4, §6.2). A table also has no odd-count parity
problem, which is what left `Glide-outs 0` alone beside an empty cell.

Decoration that repeats the row's own text is not information: the record medallion
contained the same words as the title beside it, and a 90 px sparkline read as a flat line
with a bump on all eight rows. The *distinction* a decoration encodes may still be worth
keeping — record freshness survives as a 7 pt dot — but it is kept at the size the fact is
worth, not at the size the ornament was.

## Record windows

Eight kinds, in canonical order: `best2s, best10s, best5x10s, best100m, best250m, best500m,
bestNm, alpha500`. Default highlighted window: `best2s`. The picker: tapping a record
highlights *that* window on map and chart; tapping the selected one returns to the default;
selection is transient (never persisted); a record with no achieved window is inert and
says nothing.

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
- Splash evidence comes from the engine's submersion flags (turns, flight ends); the UI
  never re-derives it.

## Filter semantics

Turn filters are type (`both | jibes | tacks`) × side (`both | port | starboard`), ANDed.
**Side means the ENTRY tack — the tack you came into the turn on — never the rotation
direction.** UI copy must say "Port entry / Starboard entry"; bare "left/right" is a
misread waiting to happen. Both turn fields exist in the schema (`side`, `direction`);
filters and trends read `side`. Anything that draws a side in colour uses the `side.*`
tokens above and nothing else.

## Formatter rules

- **A missing value is absent, never 0.** No dashes-grid where a whole card has nothing to
  say — the card does not render.
- Aggregates with a coverage carry it visibly ("23 of 23 takeoffs"); below the engine's
  `hrMinCoverage` the presentation warns (warning tone / banner), it does not hide.
- Rates with an empty denominator render empty, not "0%" — "0% ok" before the first turn
  reads as a verdict.
- A measured zero is a value ("0 bpm"), and "−0" must never appear.
- **A delta is never printed finer than the numbers it is shown beside, and it reconciles
  with them.** The HR card read `-0.1 bpm · 119 vs 119 bpm on the foil` (§5.7): a delta
  asserting a difference over two operands that, as displayed, were the same number. So the
  operands are printed at the delta's precision *and* the printed delta is derived from the
  printed operands, which makes the arithmetic on the card exact rather than usually right.
- Speeds in the rider's unit (kn/km/h per settings); missing HR renders as the unit's
  missing form ("-- bpm"), not as zero.
- **A time axis is labelled with round times, not with equal fractions of its domain.**
  Both platforms pick the finest step from one ladder — 5/10/15/30 s, 1/2/5/10/15/30 min,
  1/2/3/6 h — that fits the label budget, and write its multiples. Dividing the domain into
  fifths produced `0:00 · 33:20 · 66:40 · 100:00` (§1.5), which is correct and unreadable.
  Zoom moves which rung is in use, never the roundness. iOS: `TimeAxisTicks` in the kit,
  pinned by `PresentationTests.timeAxisTicks*`, shared by the speed chart and the HR chart.
- **Reference material lives behind the `?`, never in body copy on the page.** The session
  screen printed three grey paragraphs of legend documentation under the chips on every
  visit — ~115 pt above the fold, telling the rider something he learned once (§1.2). The
  chips are the control and stay; the words are the `mapLegend` help topic. A number that
  was hiding in that prose is not help: "38 failed attempts" is a *takeoff* fact and now
  sits on the takeoff card at the size a number gets.

## Scrub and zoom

- **One playhead.** The chart scrub position and the map dot are the same timestamp; moving
  either moves both. (iOS: `ReplayScrubber` shared state; web: the shared scrubber.)
- Chart zoom is a gesture on the time axis (iOS: pinch, because one-finger drag is the
  scrubber; web: wheel/pinch). While zoomed: scrubbing works within the window, a reset
  affordance is visible, the window's place in the session is indicated, and markers and
  shading outside the visible domain are not drawn.
- Zoom state is transient per session view — but it survives a section change, which is not
  a new session view (see "Sections" above). On iOS that means the window is owned by
  `SessionDetailView`, not by the chart.

## Pairing

A takeoff, the flight it started and the end that stopped it are three marks on one event.
Drawing that link *always* — a leader line, a shared number, a badge on every arrow — buys a
fact nobody asked for at the cost of the busiest layer on the map. So the pairing is
**tap-only: nothing about it renders until a mark or a flying segment is tapped**, and what
appears is one extra line on the popover (iOS: the track callout) that was going to open
anyway.

Every fact in it is read verbatim from the analysis document — the flight's own `startTs` /
`endTs` / `distM`, its flight end's `outcome`, its takeoff's `pumps`. Nothing is recomputed
here; the only arithmetic is `endTs - startTs`, which is the same licence
`PumpEpisodeRecord` takes for not encoding its own duration.

The four lines, exactly:

| tapped | line |
|---|---|
| takeoff (pumped or free) | `starts flight 12 · 1:23 · ended: touchdown` |
| failed attempt | `no flight · 3 strokes` |
| straight-line flight end | `ends flight 12 · started 41:07 · 7 pumps` |
| a flying segment of the track | `flight 12 of 55 · 1:23 · 272 m · ended: touchdown` |

`·` separates, times are `m:ss` (`h:mm:ss` past an hour) on the session clock, the flight
number is 1-based, and the outcome words are the flight-end ladder's own: **glided out ·
touchdown · fell in**, plus **recording ended** for an end the engine marked `unknown` or
`truncated` (a recording that stopped is not a verdict).

Absence, as everywhere else, is absence and never zero:

- no accelerometer stream ⇒ `pumps` is nil ⇒ the ` · N pumps` clause is **omitted**, not
  written as `0 pumps`;
- a flight with no distance ⇒ the ` · N m` clause is omitted;
- a mark whose flight cannot be resolved gets **no pairing line at all** rather than
  `flight ?`.

Tapping a flying segment does one more thing: it **focuses the chart on that flight** — the
timeline window is set to the flight's span plus a margin on each side (iOS:
`TimelineWindow.focus(on:)`, the same window the pinch moves; web: the strip's zoom window),
so the tap that asks "what was this stretch?" answers on both figures at once. The focus is
transient like every other zoom, and the reset affordance the zoom already has is the way
out of it.

## Enforcement

1. `design/tokens.json` + generated constants + a CI staleness check (bundle_lab-style) —
   colour/glyph values cannot drift silently.
2. Presentation goldens (`fixtures/presentation/*.expected.json`): per-fixture marker counts
   per layer, filter tallies and record-window sets, asserted by BOTH the Swift
   `PresentationTests` and the web verification scripts. A count that differs between
   platforms is a failing test, not a bug report.
3. **Flight-count invariants**, in the same goldens and asserted on both platforms. Every
   flight is started by exactly one takeoff and stopped by exactly one end, so
   `takeoff.pumped + takeoff.free == flightCount` and `flightEnds.total == flightCount`,
   per fixture — with `flightEnds` partitioned into the three buckets the marker rules
   already distinguish (`drawn` + `ownedByTurn` + `truncated`). They are the arithmetic the
   pairing above depends on: a takeoff that cannot name its flight, or a flight with two
   ends, would render a wrong number in a popover long before anyone noticed a tally was
   off. `failed` attempts are deliberately outside both sums — a failed attempt is the one
   takeoff-layer mark that starts no flight.
