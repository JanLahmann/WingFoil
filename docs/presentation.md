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

## Clean jibe — the name of the strict verdict, and how it is spelled

**A clean jibe is a counted jibe you fly all the way through, carrying your speed — no
touchdown, no swim, at or above the success threshold of your entry speed.**

That is the engine's per-turn `clean` flag, and every surface reads it rather than
re-deriving it: `counted && type == jibe && success && outcome == flew_through`
(`docs/algorithms.md`, "Turn detection & classification"). No parameter moved; the metric
was called "turn success" or "carried through" or "held speed" on four screens and is
called one thing on all of them.

**Until engine 0.12.0 clean was the `success` flag alone** — the score verdict, deliberately
independent of how the turn *ended*. That let a jibe be starred as clean on the map and
listed as a swim in the table six rows below it, which is what happened to 2026-08-29's jibe
13: 71 % of its entry speed held, 54 s off the foil, in the water. The word had to mean what
a rider means by it, so the outcome joined the verdict and the clean counts fell on eleven of
the seventeen fixtures. `success` did not change and the Turns tab still shows it, under the
name **carried** — the score half, on its own, which is a different question.

**The spelling is a contract, both halves of it:**

| context | spelling | example |
|---|---|---|
| the product | **CleanJibe**, one word, camel-cased | "CleanJibe for Garmin" |
| the metric / the sport term | **clean jibe**, two words, lowercase | "7 of 10 clean", "12 clean" |
| a label position that capitalizes | **Clean jibes** | the session card's title, the trends chart |

Never "CleanJibes" for the metric and never "clean jibe" for the app. A sentence that
means the count is lowercase even when it opens with the word.

**It is not the ladder's green, and no surface may let the two blur.** "Flew through" is
how the turn *ended*; clean asks that *and* what it cost. Since 0.12.0 clean is a strict
**subset** of `flew_through` — every clean jibe flew through, and on the corpus session 24 of
the 35 jibes that flew were clean. That is the whole reason the two must stay visibly separate: the
distinction is no longer "these disagree" but "this one is narrower", and a surface that drew
them alike would be claiming every jibe that flew was ridden. So the clean count never wears
the outcome ladder's inks, never sits inside the three-count tally, and never borrows the
word "flew". Where it is a *count* beside the tally it is drawn in neutral ink, as the
stricter reading of the same set of turns; where it is a *mark of its own* — the map's star —
it carries the clean ink (`DesignTokens.Clean.jibe` / `--wf-clean-jibe`), a green chosen to
be nothing on the ladder. Either way the rule is the same one: clean is the narrower of two
verdicts, and no ink may say they are one.

## Layers

| id | shows | default | notes |
|---|---|---|---|
| `flying` | track tinted on-foil | visible | phase tint, not a marker |
| `offFoil` | track tinted off-foil | visible | |
| `effort` | the selected GP3S record window glowing on track + shaded on chart | visible | window choice is the record picker's (below) |
| `cleanJibe` | **clean jibes, as filled stars** in place of their outcome dot | visible | cuts *across* the ladder — see below |
| `flewThrough` | turn outcome markers, flew | visible | |
| `touchdown` | turn outcome markers, touchdown | visible | |
| `fellIn` | turn outcome markers, fell in | visible | |
| `courseChange` | rejected sweeps (bear-away / round-up) | visible | grey — a non-verdict |
| `pumping` | pump-burst spans on the track | visible | spans, not markers |
| `takeoff` | takeoff attempts, BOTH halves: successes and failures | visible | one chip hides both halves together |
| `splash` | submersion moments | visible | |
| `direction` | course-of-travel chevrons along the track | visible | decimated by on-screen spacing |

Layer visibility persists on iOS (hidden-set; unknown ids must decode harmlessly so old prefs
survive new layers) and is transient on web. Legend chips are the only toggle surface; a
struck-through chip means hidden.

### Every map has the same legend, and its own visibility

**One control, three maps** (iOS, 6 Sep 2026). The Ride section's track (inline and full
screen), the Turns section's maneuver map and the Takeoffs section's attempt map all mount
the same collapsible legend — the `Layers · N hidden` header, the chips, "show all", the
style picker, the `?` — and nothing else may be a layer control. The two analysis maps used
to have no legend at all and carried a lone style chip in their caption lines, which made
them look like a different kind of map rather than the same map asking a narrower question.

Two rules, and they are the whole of it (`MapLayerScope` in the kit, pure and tested):

- **A map declares the subset it can draw, and gets chips only for those.** A `pumping` chip
  on the Turns map would be a control that changes nothing, which is worse than no control:
  it tells the rider the page has a state it does not have.

  | map | draws |
  |---|---|
  | `ride` | the whole catalogue — the twelve above |
  | `turns` | `direction` · `cleanJibe` · `flewThrough` · `touchdown` · `fellIn` · `courseChange` |
  | `takeoffs` | `pumping` · `direction` · `takeoff` · `splash` |

  Neither analysis map draws the **line** layers: their route is deliberately neutral grey,
  because the page is about one filtered set and a phase-tinted track under it would be the
  loudest thing on a 240 pt figure. So `flying` / `off foil` / the effort glow are *absent*
  rather than present-and-inert.

- **Visibility is per map; the collapsed/expanded header state is shared.** Three stored sets
  (`mapLayerVisibility.v1` for the ride map — the original key, so an existing preference
  survives — plus `mapLayerVisibility.turns.v1` and `mapLayerVisibility.takeoffs.v1`), each
  with its own defaults: ride hides nothing, Turns opens without `direction` and
  `courseChange`, Takeoffs without `direction`. Hiding "fell in" on Turns, where the page is
  a verdict on maneuvers, is a different intention from hiding it on the ride, which is a
  picture of the afternoon. "Show all" resets **one** map. The expanded state stays shared
  (`mapLegend.expanded.v1`): "I use the chips" is a habit, not a per-map choice.

The `N hidden` count is scoped the same way — only this map's layers, and only categories the
session actually has any of (`MapLayerVisibility.hiddenCount(in:tally:)`).

**The layer chips and the pages' own filters are different controls and must stay apart.**
The Turns tab's type/side segments and the Takeoffs tab's outcome chips are *data* filters:
they choose which attempts or maneuvers the page is about, and the pins, the tally, the
caption and the list move together. The legend chooses *what is drawn about them*. Filtering
to failures and hiding the pumping runs are different intentions; neither control may imply
the other.

### The Takeoffs map

The Takeoffs section's map is the Turns map's sibling — the same frame, the same legend, the
same pan and zoom — with attempts instead of maneuvers:

- **The whole session's track, faint and neutral**, with the same dark outer edge over
  photography the other maps' tracks get (`TrackHalo`).
- **The pumping spans under the pins**, because a run he pumped is the context for the
  attempt that ends it and not a thing to read on its own — the same order the Ride map draws
  them in. The spans obey the outcome filter with the pins.
- **One pin per attempt**, in the takeoff layer's existing glyphs and inks: the filled arrow
  for a pumped takeoff, the hollow one for a free takeoff, the red u-turn for a failed
  attempt (§ "Colour and glyph vocabulary"). Nothing new is invented here.
- **Outcome filter chips — `All · Success · Failed · Free`** — where **free is a narrowing of
  success, not a rival to it**: a rider who got up on the wind alone got up. Same shape as
  clean ⊂ flew through on the Turns tab.
- **Tapping a pin or a row focuses the attempt**: the pin grows and the row bands. Transient,
  like every other way of pointing. There is no takeoff detail sheet — a takeoff is one
  moment, not a maneuver with a shape.
- **A list under the map, in time order**, mirroring the turn list: `at | pumps | to foil |
  outcome`. A missing number is **absent, never 0** — a source with no accelerometer counted
  no strokes, and a failed attempt never reached the foil, so both print an em-dash rather
  than a zero that would read as a claim.

### The clean jibe is a star, and it answers to one chip

A clean jibe (the engine's per-turn `clean` flag — see "Clean jibe" above) is drawn as a
**filled star** — SF Symbol `star.fill` on iOS, the `star` shape in `viz.js` — in the
clean-jibe ink (`DesignTokens.Clean.jibe` / `--wf-clean-jibe`, `#2ee6a8`). Three rules, and
all three are the same rule read from different sides:

- **It replaces the outcome dot; it does not join it.** Two marks on one turn at map scale
  is two events to the eye, and the turn is one.
- **It is a green of its own, never `Outcome.flew`.** Every clean jibe flew through, but not
  every flew-through jibe is clean: "flew through" is how a jibe *ended*, clean is that *and*
  what it cost. A star drawn in the ladder's green would quietly claim the two sets are one.
  Shape carries the distinction anyway, so nothing here depends on telling one green from
  another.
- **A starred jibe answers to the `cleanJibe` chip and to nothing else** (Jan, 5 Sep 2026 —
  the star's chip and the flew-through chip are independent). Hide "flew through" and the
  plain flew-through dots go while the stars stay; hide "clean jibe" and the stars go while
  the dots stay. Until 5 Sep a star answered to both chips, because "clean" could then sit on
  a touchdown and a star that survived "hide touchdowns" would have been a touchdown the rider
  asked not to see; with clean ⊂ flew through that case no longer exists, and one mark, one
  chip is the simpler contract.
- **Counts follow the chips.** The flew-through chip still counts every jibe that flew
  through, clean ones included — it is the outcome tally and the outcome did happen — while
  the star's chip counts `cleanJibes`. The clean count is deliberately *not* a fifth entry in
  `PresentationFacts.markers` — those partition the turns and the drawn flight ends one mark
  each — but a fact of its own, pinned per fixture in `fixtures/presentation/`.

**The Turns tab's map draws the star too** (6 Sep 2026). It was the one map in the app that
drew a clean jibe as a plain outcome dot, which made the star look like a property of the
session map rather than of the jibe; it now answers to the `cleanJibe` chip there under the
same one-mark-one-chip rule (`TurnOutcomeKind.layer(clean:)`).

The speed strip shares the visibility model, so a star hidden on the map is hidden there too,
and the web keeps its numbered marks in step with the Turns table: the number rides with the
mark and disappears with it.

### The option row under the map: three groups, one question each

Both platforms lay the row out the same way, and the split is by *what a tap changes*:

| group | holds |
|---|---|
| route | flying · off foil · pumping · direction · the effort window |
| events | **clean jibe** · flew through · touchdown · fell in · course change · takeoff · splash |
| utilities | "show all" (only while something is hidden) · the map-style menu (iOS) or the zoom bar (web) · the `?` (iOS, and not on the full-screen map) |

- **Clean jibe leads the event group.** It is the mark a rider opens the map to find, and it
  is the one mark there that is not a rung of the ladder — putting it after "fell in" would
  file the strict verdict as the ladder's fourth outcome.
- **The utilities are last and trailing-aligned**, because none of them toggles a layer: the
  style menu is the map's *ground*, "show all" is a reset, the zoom bar is a camera and the
  `?` is a sheet. They used to sit in the middle of the route chips, which on a narrow phone
  wrapped the style menu between "direction" and "best 2 s" and made the row read as a list
  of eight unrelated things.
- iOS draws the two chip groups as two rows (`MapLegendView.routeRow` / `markerRow`) behind
  the header row below, with the utilities riding on that header; web draws all three as
  `.chip-group` spans with a visible seam between them, wrapping as units so a narrow screen
  breaks between the questions rather than through one. The legend note stays last, under
  all three.

**iOS collapses the chip groups behind a one-line header** (Jan, 6 Sep 2026, on build 24).
Twelve chips wrap to two or three lines, which is ~70 pt between the map and the speed chart
on every visit to every session — and the two are one instrument, so the rider was scrolling
past the controls to reach the half of the figure they control. The contract:

- **The header is always on screen and always says the state**: `Layers · all shown`, or
  `Layers · 3 hidden` with the count in the accent colour. A collapsed control that hid the
  fact that a filter is on would be exactly the failure the chips exist to prevent.
- **The count is of layers this session actually has any of.** A rider who hid "splash"
  months ago is not told something is off on every session he never went under on; the
  number's whole job is to be the reason to open the block.
- **The utilities stay on the header row**: "show all" (only while something is hidden), the
  map-style menu and the `?`. None of them is a chip and none needs the block open.
- **Collapsed by default, and the state is remembered per rider**
  (`mapLegend.expanded.v1`), like the visibility set itself: "I use the chips" is a fact
  about a rider, not about a session. **All four legends read it** — inline, full screen,
  Turns and Takeoffs — because it is a habit and not a per-map choice; the *visibility* sets
  underneath are per map (§ "Every map has the same legend, and its own visibility").
- **Expanded, a chip is exactly what it was** — same groups, same order, same three states.
  Only whether the rows are on screen changes.
- The web keeps its chips open: above the breakpoint it is a document on a desktop, not a
  phone screen with a chart below the fold.

**Chip text is the layer catalogue's `label` in `design/tokens.json`** — flying · off foil ·
pumping · direction · clean jibe · flew through · touchdown · fell in · course change ·
takeoff · splash
— read from the generated constants on both platforms, never written as a literal in a view.
The one exception is `effort`, whose chip is labelled with the *selected* window ("best 2 s")
because that is what it is currently highlighting; the catalogue's "best effort" is the
fallback for a session with no achieved window.

### The inline map pans and zooms

The session map takes **pan and zoom** and nothing else (iOS, 6 Sep 2026 — it used to take no
gesture at all, `interactionModes: []`). A two-kilometre track on a 260 pt figure is four
pixels per jibe, and the one thing a rider wants to do with it — get closer to the corner he
jibed at — cost a trip to the full-screen map and back.

- **Rotate and pitch stay off.** The drawing is a plan view of a plane of water; a tilted one
  answers nothing, and a rotated one breaks the chevrons' one job.
- **A drag that starts on the map moves the map**, and the page scrolls from anywhere else on
  it. That is the trade, it is known, and there is no lock toggle: a control whose only
  purpose is to say which of two gestures a drag meant is a control about the app.
- **A tap still means "show me this point"** — mark, then flown stretch, then nothing — and
  its two tolerances are read off the camera *as it stands* rather than off the region the
  map opened on, so they stay roughly a fingertip after a zoom (iOS: the region from
  `onMapCameraChange`).
- **"Open map full screen" stays.** The big map is still where rotation, the whole session at
  once and the floating legend live.

## Map style — the ground under the track

Four grounds, one choice, **iOS only** (the analyzer draws its track on a canvas, not on a
map): `standard` · `muted` · `satellite` · `hybrid`, persisted per rider in `mapStyle.v1`
(`MapStyleChoice`, `MapStyleStore`). Standard is the default and is what every map used to be.
The reason the other three exist is that a rider at his home spot wants the track to be the
loudest thing on screen, and a rider looking at somewhere new wants to see the shore — the
launch, the pier he jibed around, the shallows he stayed off — which only photography shows.

| choice | MapKit | points of interest | track halo |
|---|---|---|---|
| `standard` | `.standard(elevation: .flat)` | excluded | no |
| `muted` | `.standard(elevation: .flat, emphasis: .muted)` | excluded | no |
| `satellite` | `.imagery(elevation: .flat)` | (no label layer) | **yes** |
| `hybrid` | `.hybrid(elevation: .flat)` | excluded | **yes** |

The table is `MapStyleChoice.recipe` and the view builds its `MapStyle` *from* it, because
`MapStyle` is opaque and cannot be asserted once built. All four are **flat**: a GPS trace is a
plan view of a plane of water. Points of interest are excluded wherever the argument exists —
including on the full-screen map, which used to be the one place they were drawn.

**One setting, five surfaces.** The session's inline map, the full-screen map, the Turns
tab's map, the Takeoffs tab's map and the cinema replay all read it. The control is a menu
chip in the legend row — the map's control strip — on every one of them: the analysis maps
carried a lone style chip in their caption lines until 6 Sep 2026, when they gained the same
legend as everything else and the chip moved into it, where it belongs.

**Over photography the track is redrawn to survive it, and the vector styles keep today's
rendering exactly.** Two rules, both in the shared drawing path (`TrackHalo`,
`TrackContent`):

1. **A dark outer edge** on every stroke and every mark — 55 % black, 3 pt either side, one
   pass under the whole track so no join is overdrawn. Soft on purpose: a hard keyline reads
   as a second, wider track and turns a busy corner into a smear.
2. **The inks flip; the hues never do.** Foil-teal, the outcome ladder, splash-cyan and the
   effort orange mean the same thing on every ground and are drawn identically. But the
   *inks* — off-foil and neutral track (`Color.secondary`), the direction chevrons
   (`Color.primary`), the Turns map's quiet route — are semantic label colours that assume the
   app's background is behind them: dark grey in light mode, invisible on deep water, and a
   dark halo under a dark grey line only merges the two. Over imagery they resolve to the
   light end at their own weights (`TrackHalo.ink`). Same intent, read against what is
   actually underneath.

**The replay clip keeps whatever ground was chosen** — a clip of a session is a clip of the
rider's own map. Note that MapKit draws Apple's attribution itself, so a satellite or hybrid
clip carries the "Apple Maps · Legal" mark in its corner for the whole recording. That is
correct and required; a rider who wants a clip without it records on `standard` or `muted`.

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

**The speed ramp is a scale, not a vocabulary, and it is scoped to one drawing:** the turn
detail breadcrumb and the legend under it ("Turn detail"). Five stops, `speed.*`, cold →
`phase.flying` at the turn's entry speed → hot. It is the one place a *magenta* is drawn on
purpose — the §5.2 complaint above is about a magenta belonging to nothing, and this one is
the top of a labelled scale with a legend beside it. It may not leave that card: on the
session map a line coloured by speed would compete with the phase tint, which answers a
different question, and the two ramps would be read as one.

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
| 1 | duration (`10:45 min` / `1:57 h`) · distance · average speed |
| 2 | the best 2 s record, labelled **"max 2 s"**, in the largest type · beside it **5×10 s** and **alpha 500** at the ordinary size, "—" where the session produced none (since 6 Sep 2026). These two are **block-only**: the share card is the block *minus* them — one speed on a card, the one a rider quotes; the Records page owns the set. The web renders them with the `extra` class, which is how `card_parity.mjs` tells them apart |
| 3 | the outcome tally on the ladder's inks · the two turn streaks |
| 4 | **JPH** (dry jibes) and **WPH** (`docs/algorithms.md` "Session rates"), one decimal |

The rules, which are the only thing the two implementations can disagree about:

- **Duration is `M:SS min` under an hour and `H:MM h` at or above one.** It was `h:mm` at
  every length, which printed **`0:11`** for the ten minute forty-five second example
  session — the two interesting digits rounded away, and a leading zero where the number
  should be. Survivable on a page a rider can scroll past; not survivable on the share
  card, which is a PNG in somebody else's chat thread with no re-render and nothing beside
  it to check against. A short session is exactly the kind a rider shares.
  - **The unit rides inside the value**, as `km` and `kn` do in every other cell of this
    block. That is the block's own habit, and it settles the ambiguity the bare digits
    create: `10:45` under the word "duration" reads as ten and three quarter *hours* as
    easily as minutes, and at cell size on a card there is no second number to resolve it
    against. It also keeps the card's caption slot free — the tally owns that.
  - **Colons, not "10 m 45 s".** A colon is what a clock looks like, it stays narrow at
    75 px type, and it is the shape the flight table and the replay caption already print.
  - **Rounded, never truncated** — to the nearest minute above the hour, to the nearest
    second below it. `0:00` over a recording that exists reads as a failure to measure.
  - Implemented as `KeyMetrics.duration` (Swift) and `hm` (web/js/cardstats.js), with a
    third spelling in `verify_presentation.py` §5 so the two are checked against a rule
    rather than against each other. The engine's `durationS` is untouched: this is display.
- **Average speed is converted to knots.** The engine reports `avgSpeedKmh`, but every
  other speed in both apps is knots, and a km/h number in a column of knots is a misread
  waiting to happen. It is a session-shape number — elapsed time, gaps included — and never
  a record: the GP3S block is still the only place records live.
- **Row 2 names the window, not the peak.** "max 2 s", the same rule the record picker's
  chip follows; "max speed" over a 2 s window would be the overclaim that rule exists to
  prevent.
- **Row 3 is the jibe ladder**, and the caption says what the three numbers are out of and
  how many were **clean** ("of 50 jibes · 12 clean"). A session whose wind axis never
  resolved has no jibes at all, so it falls back to every counted turn ("of 51 turns ·
  12 clean") — an empty ladder over an afternoon of turns would read as "nothing
  happened". The tally is a verdict, so it may wear the
  ladder, and the **library row** wears it too — over every counted turn there, which is
  what a row scanned against its neighbours has to be. The web rows carried no tally at all
  until §5.6, on the more prominent of the two library surfaces; a row from a digest
  written before the field existed renders "—" rather than three zeroes.
  - **The clean count rides in the caption, not in a cell.** It is `jibesSuccessful`
    against the jibe ladder and `turnsSuccessful` against the turn fallback — the fallback
    is the score verdict, because a session with no jibes has no clean jibes to report and
    the caption is qualifying a tally of turns. A fifth cell on row 3 is a cell
    the streaks pair would lose, and the count is a *qualification* of the tally rather
    than a metric standing beside it. It stays in neutral ink — see "Clean jibe" above.
- **Streaks are `summary.turns.longestFlewStreak` / `longestDryStreak`**, rendered
  `5 flew · 11 dry` — the first time either app draws them. They are over counted turns,
  which is what the engine measures them over; nothing is re-derived here.
  - **Flying leads the pair.** The flew run is the harder of the two and the one the rider
    is chasing, and `longestFlewStreak <= longestDryStreak` always — so the pair reads
    strict-then-lenient, the same order the watch's Turns page has always drawn it in
    (`drawStreakRow2`: green run, then orange run). The block used to lead with dry, which
    put the two surfaces in different orders for one fact.
- **JPH is dry jibes, and the label says so.** The engine's `jibesPerHour` counts the jibes
  he came out of still sailing (`docs/algorithms.md` "Session rates", engine 0.7.0), so the
  cell is captioned **"JPH · dry jibes per hour"**. A rate that counted the swims too could
  be raised by falling more often, and a caption reading "jibes per hour" over a number that
  excludes seven of them would name a different figure than the one printed.
- **CPH sits beside JPH, never instead of it** (engine 0.10.0). `cleanJibesPerHour` is the
  strict verdict per hour — the jibes he flew all the way through carrying his speed — and
  the cell is captioned **"CPH · clean jibes per hour"**. The two are on the row together
  because they answer the two questions a rider asks in exactly that order: *did I come out
  of it still sailing*, and *did I ride it*. Neither is derivable from the other. 2026-08-03
  pm is the session that makes the point — **4.5 JPH beside 0.0 CPH**, fifteen jibes he
  mostly stayed out of the water on and did not ride one of — and a block printing either
  number alone would be answering half the question. The pair reads lenient-then-strict, the
  same direction the tally reads when its caption qualifies the three counts with the clean
  number.
  - **CPH never wears the outcome ladder's inks**, here or anywhere — see "Clean jibe"
    above. It is a rate in the block's ordinary type, like every other cell on the row.

**The clean jibe is a personal best, and it gets the celebration.** Until engine 0.10.0 every
record the app celebrated was a speed. The two that were missing are the ones a wingfoiler
actually chases, and they are kept beside the nine (`CleanJibeRecordKind`,
`PersonalBestDetector.cleanJibeBests`):

| record | what it is | why it is separate |
|---|---|---|
| **Clean jibes** | most clean jibes in one session (`SessionRow.jibesSuccessful`) | the afternoon he rode the most |
| **Best CPH** | best `jibesSuccessful / (durationS/3600)` | the afternoon he rode them *fastest*, which a short evening in good wind wins |

- **A session must last one rate window (15 min) to hold the CPH record.** The rolling
  window's "never a flattering peak" rule (docs/algorithms.md) applied to a session: one
  clean jibe in a four-minute sail is fifteen an hour, and a personal best a rider can set by
  going home early is not one. The *count* takes no such floor.
- **Ties keep the earlier session**, the way the window peak keeps the earliest window.
- **One burst for both kinds.** A speed record and a clean-jibe record are the same moment to
  a rider, so `RecordsView` fires one confetti burst and one haptic for either, with a line
  above the table naming what was beaten — the two records have no row in a table of knots,
  and a count of jibes in a column headed `kn` is the one thing a records screen may never
  print. A snapshot written before the pair existed celebrates nothing, exactly as an empty
  snapshot does: the first measurement beats nothing.
- **The replay says it too.** `ReplayCommentary` gains a `cleanJibe` beat on the same
  ordinals the dry count uses — "First clean jibe!", "5 clean jibes" — ranked *above* the dry
  line, so a jibe that is both the fifth dry and the third clean is announced as the clean
  one. It survives a tighter clip budget than an ordinary jibe ordinal and never outranks a
  streak record.
- **Row 4 degrades JPH to TPH, not to zero — and CPH goes with JPH.** When `jibesPerHour`
  is 0 while `turnsPerHour` is positive — turns the wind axis could not name — the row shows
  `turnsPerHour` labelled TPH, **and no clean-jibe cell at all**: CPH is a jibe rate, and
  "0.0 clean jibes per hour" over a session that named no jibes would be the precise lie the
  TPH fallback exists to avoid. Where jibes *were* named, a `0.0` CPH is a measured verdict
  and is printed as one. WPH needs no fallback: a fell-in flight end is a fall whatever the
  wind was doing. A session with a duration and genuinely no turns keeps JPH and CPH at
  `0.0`, because those are measured zeroes.
- **No duration, no row.** `durationS <= 0` makes the engine report all four rates as
  null, and row 4 disappears — the general rule ("a missing value is absent, never 0")
  applied to the one place where a 0.0 would read as a verdict on the rider.

## Session time — the clock a session is drawn on

**Every time either app prints for a session is the time the rider saw**, not the time the
reader's device would make of the same instant.

A FIT timestamp is UTC. Until engine 0.8.2 that instant was formatted in whatever zone the
*viewer* was currently in, which is correct only while the viewer and the recording share
one — a coincidence that ends at every DST boundary (on 25 October 2026 every session in
the library shifts by an hour, and stays shifted) and on the first session ridden abroad. A
session's time is a fact about the session, so it is stored with the session.

- **What is stored** is a UTC offset in **seconds**, not a zone name: what a source can
  tell us is an offset, and a name we had to guess would be inventing a fact.
  `session.startUtcOffsetS` (GRDB schema v7), `meta.utcOffsetS` in the web digest.
- **Where it comes from**, best answer first — and, since engine **0.9.1**, *which of these
  answered* is stored beside it (`session.startUtcOffsetSource`, schema v8;
  `meta.utcOffsetSource`; `RawTrack.start_utc_offset_source`; digest schema 4):
  1. `activity` — the recording said so itself: the FIT's own `activity` message,
     `local_timestamp − timestamp`, the offset the watch was wearing at save time (exact,
     DST included, present on every file in the corpus), or a GPX timestamp written with a
     numeric offset, which is the exporter stating the same fact;
  2. `icu` — intervals.icu's `timezone` for the activity, resolved at the session's own
     instant. Also exact; second only because it is a fact about the athlete's account
     rather than about this recording. Set on the sync path, the only caller with an
     account to ask;
  3. `longitude` — a coarse guess from the first GPS longitude, `round(lon / 15°)` hours.
     This is the *solar* offset, not the civil one — an hour out under DST, up to two inside
     a wide zone, blind to the half-hour zones — and it exists only for a source that
     carries position and nothing else;
  4. `device` — nothing could say. The offset column stays NULL, the display falls back to
     the device's zone, and the surface is allowed to say so (`SessionRow.hasKnownZone`;
     the web page's header note).

  A **NULL source** is a fifth state and means *unrecorded*: a row written before schema v8,
  or one the v8 backfill could not resolve. It reads as neither exact nor estimated and
  keeps the pre-0.9.1 wording — inventing a caveat is as wrong as inventing a certainty.

- **Why the rung had to be stored** (the 0.9.1 change). `+7200` because the watch wrote it
  down and `+7200` because the first fix was at 11° E are the same number and different
  facts, and only the first licenses a page to say *times as recorded on the water*. Engine
  0.9.0's GPX door made the difference routine rather than exotic: a GPX usually carries no
  zone at all, so rung 3 is the *normal* answer for the whole of that input class — and rung
  3 is an hour wrong in Torbole every summer, which is when people wingfoil there. The
  ladder itself did not change; what was missing was the qualification.
- **What each rung is allowed to say.** Wherever a time is shown **in the session's own
  zone**, the wording follows the source, and there are exactly two:

  | source | wording |
  |---|---|
  | `activity`, `icu`, or unrecorded | **times as recorded on the water** (web header note); no caption on iOS |
  | `longitude` | **times estimated from the track's position** (web header note; iOS `SessionDetailView.estimatedClockNote`, "Times estimated from the track's position — this recording carries no time zone.") |
  | `device` / offset NULL | the existing **no timezone in this file — times shown on your own clock**, which is already the honest sentence: this is not the session's zone at all |

  A **library row or a trend tick is not annotated** either, and for a different reason
  again: they print a *date*, and a whole-hour guess moves a date only for a session that
  starts within an hour of midnight. A caveat on every row of a list is noise on all of them
  to be right about one.

  The soft caption appears **only** on the `longitude` rung. A reassurance printed on every
  page is noise, and noise is what a reader learns to skip past on the one page where it
  says something — which is why iOS shows nothing for an exact source rather than a
  "recorded" badge, and why the web keeps its one-line note either way.
- **The replay clip's title card carries no caveat**, deliberately. The rule above is about
  a surface that makes a *data claim*: a report page states the session's facts and is read
  as a record of them. A clip is presentation — a 30-second video with a date on its opening
  frame, watched once, usually without sound, by somebody who was not there. There is no
  room for a qualifier that would be on screen for a second and a half, no reader in a
  position to act on it, and no claim being made beyond "this was that afternoon", which the
  guess supports to within an hour. The same reasoning is why the share card's date line is
  uncaptioned: both are the *picture*, and the page behind them is where the qualification
  lives. (`ReplayTitleCard` and `ShareCardStats.dateLine` still take the session's zone, and
  still get it from `row.displayZone` — the estimate is used, it is simply not annotated.)
- **One accessor, no defaults.** `SessionRow.displayZone` is the only answer, and the
  `timeZone:` parameters on `ReplayCommentary.make`, `ReplayStoryboard.make`,
  `ReplayTitleCard.make`, `ShareCardStats.make`/`outro`, `ShareText.*` and
  `FitShareFilter.filename` have **no default**. A default is a decision made silently at
  every call site, and the silent decision was wrong at all of them; with the defaults gone
  the compiler names each one and it has to answer out loud.
- **`.current` is still right in three places**, and is commented as such where it is used:
  Settings' "Last sync" and the watch link's "Last summary" (events on the reader's clock),
  the trend ranges and week buckets (the reader's calendar), and the spot/gear "last used"
  aggregates (which span sessions and have no one zone). A tombstone also keeps `.current`,
  because a deleted session's recording is gone and nothing is left that knows its zone.
- **On the web** every clock goes through `zonedFormat` (web/js/viz.js): shift the instant
  by `meta.utcOffsetS`, then format in UTC. `clockAt` and `sessionDate` take the whole
  `meta` rather than a bare `startUtc`, so a caller cannot pair the two up wrongly. The
  header note is written by `clockNoteFor` in `web/js/render.js` from the table above, and
  only names the reader's own zone when the file could not say.
- **Calendar dates too.** A session that starts at 00:30 in Torbole is a 22:30 UTC session
  on the *previous* day, so a library row, a trend x-axis tick and a share card dated on
  the UTC day would name a day the rider did not have. The digest carries `dateLocal`
  beside `dateUtc` for exactly this.
- **Pinned by** `SessionTimeZoneTests` (iOS), which ingests the bundled example through the
  real ingest path with the process default zone forced away from the session's and asserts
  the bookend, title card, share-card date line and shared filename all still read `14:07` /
  `30 August 2026`; and by `verify_presentation.py` §4, which does the same arithmetic on
  the web's `meta`. `TZ=UTC swift test` is the stronger form and is what CI runs.

  The **rungs** are pinned separately, one assertion per rung on each side, because the bug
  0.9.1 fixed was not a wrong number but a missing qualification and a ladder that quietly
  reordered would otherwise still pass: `SessionTimeZoneTests.theLadderFallsThroughInOrder`
  and `onlyAnExactRungLetsARowClaimTheSessionsClock` (iOS), `GpxParseTests` for the
  GPX-shaped cases, `test_parse.test_the_ladder_records_which_rung_answered` and
  `test_gpx` (lab), and `verify_presentation.py` §4, which asserts the two note wordings
  come out of the same `meta` the browser reads.

Implemented once per platform: `KeyMetrics` in `ios/WingFoilKit/…/Presentation/`, whose
strings `PresentationTests.keyMetrics*` pin, and `keyMetrics` in `web/js/render.js`. The
Swift half resolves every display string so the SwiftUI view is pure layout; the two are
twins, and a difference between them is a bug.

### The share card carries the same block

*(There is a second card kind — the **period card** — which is this card describing a week
rather than an afternoon. Everything below holds for it unchanged; what differs is set out
under "Periods".)*

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
| `complete` (default) | the whole block: duration · distance · avg speed · max 2 s · tally · streaks · JPH/TPH · CPH · WPH |
| `lean` | duration · distance · max 2 s · tally |

**The rider gets a title and one caption, and neither is a cell** (schema v9). The card's
header is the session's name, its date, and — when he wrote one — a single line of his own
under the date. Everything else on the card is a measurement or the footer's offer; the
caption is the only thing on it addressed by the *sender* to the reader, which is why it sits
in the header rather than joining a grid whose whole contract is that it is the app's own
block. It is capped at **80 characters** (`SessionNaming.noteLimit`, `NOTE_LIMIT`), folded to
one line, and it shrinks rather than truncating — an ellipsis in a PNG is permanent, three
points of type size are only small. Absent, the header is exactly the two lines it always was:
42 layout points, unchanged, and the caption's 14 come out of the track's remainder.

The two platforms differ in *what is being named*, and only there. On iOS the title field is a
**rename of the session**: it writes `SessionRow.customTitle`, and every surface follows —
library row, detail header, card, clip title card, share messages, and the name the scrubbed
FIT and the clip arrive under (`SessionNaming.title`, which `SessionDisplay.title` applies
once). The caption is `SessionRow.shareNote`, shown on the card and on the clip's *opening*
frame — not on the closing one, where the same sentence would be printed twice in forty
seconds, and never in a library row or on the detail page, because it is a message to an
audience rather than metadata. The analyzer has no session record to rename, so both fields
are transient there: they feed one render and are remembered per session digest id in
`localStorage`.

**The title field opens filled in, on both platforms.** It carries the session's current name
as editable text — the rider's own if he has given one, the derived one otherwise, resolved
exactly the way the card's headline resolves (`SessionNaming.titleDraft`, `cardTitleDraft`).
It used to open empty with the derived name greyed out behind it, and a placeholder is not a
prefill: it vanishes on the first keystroke, so every rename started from nothing even though
renaming is nearly always *editing* the name — adding "— first 20 kn" to the spot. The
placeholder stays on for the one moment it is now visible, after a select-all and delete. Two
consequences follow and both are load-bearing: the prefill is never blank, and a draft still
equal to the derived name is **not** a rename — it is written through as empty on iOS and
remembered as nothing on the web, so a sheet that is opened, captioned and closed leaves the
session derived. Only a keystroke in that field names a session.

**The derived name says Wingfoil, whatever the watch called it.** Garmin has no wingfoil
profile, so a session is recorded under the windsurf one and the watch names the activity
after that profile in the watch's own locale — "Nago-Torbole Windsurfen" on a German Fenix.
The word rides the filename into the app (and into `<id>_<slug>_icu.fit` when the session
comes back through intervals.icu), so both platforms swap it on the way to the screen: a
**standalone** `Windsurfen` / `Windsurfing` / `Windsurf` becomes `Wingfoil`, keeping the case
of the position it lands in (`SessionNaming.sportCorrected`, `sportCorrected` in
`js/cardstats.js`). On iOS that is one call site — `SessionDisplay.derivedTitle`, which every
surface already asks. On the analyzer it is applied to the card's headline and to the three
places that print the Python digest's filename-derived `spot`: the library list, the records
table and the trends tooltip. The digest itself is not rewritten (`library.py` is engine-side
and its goldens stand); the swap happens in the view. Three limits, all deliberate: it is
applied to the **derived** title only,
so a rider who types "Windsurfen mit Tobi" keeps it; it never touches a stored name, a
filename or the FIT's sport code, which are records of what the watch actually did; and the
word has to stand alone, so "Windsurfschule Torbole" is left as it is. The discipline **badge**
is not covered by it either — `SessionDisplay.sportLabel` still reports what the file says,
because a badge that renamed the sport code would be reporting something the recording does
not contain.

The card's outline carries three semantics and no more (`TrackThumbnail.Mark`): the track
tinted by foil state, a dot per **counted** turn on the verdict ladder's inks, and the
barometer's submersion evidence as a cyan **diamond** — shape as well as colour, because a
splash usually sits on the fell-in verdict it belongs to. Course changes get no dot, by the
same rule the map draws by. Nothing else from the map's eleven layers survives the shrink.
**The ground under it is optional, and off.** A switch on both composers — "Map background",
remembered per device (`ShareCardMapStore`, `wingfoil.shareCard.map.v1`) — puts a map behind
the whole card: `MKMapSnapshotter` on iOS, OpenStreetMap raster tiles composited on a canvas
on the web (`ios/WingFoil/Features/Share/ShareCardMap.swift`, `web/js/cardmap.js`). Five rules
hold it together, and the first is the one everything else serves.

- **Default off, byte for byte.** A rider who never touches the switch gets exactly the card
  described above — same pixels, and, on the web, not one request to anybody. The map is the
  only part of making a card that reaches a third party, so any stored value that is not the
  switch's own is read as off.
- **The ride does not move.** The snapshot (or the tile grid) is *framed* so the track fills
  precisely the box the layout already gave it, and the card's own margins are what become
  map. Flipping the switch shows one card with and without ground under it, never two cards.
- **The breadcrumb is placed through the map's projection**, not the card's. The plain card
  fits a normalized outline to a box — a projection about the session, which does not know
  where the water is. With a map behind it every vertex goes through
  `MKMapSnapshot.point(for:)` / Web Mercator instead, or the line would sit near the water
  rather than on it.
- **A scrim, and dark stat plates.** A navy wash plus a vertical gradient heavy at both ends
  (and, on the wide shape, a panel under the word column), and the stat cells invert from
  white-at-a-tenth to black-at-a-third: a translucent white plate over a town's building fill
  is not a plate. Tuned against the busiest ground either platform produces, not against open
  water.
- **Attribution is printed on the card.** `© OpenStreetMap contributors` on the web (ODbL
  requires it) and `Maps © Apple` on iOS, at 6.5 pt in the corner opposite the title on the
  tall shapes and bottom-leading on the wide one — never in the QR's corner, and never under
  the footer. `MKMapSnapshotter` burns its own badge into the bottom-left of the image, which
  on this card lands under the brand mark; the snapshot is taken a band taller than the card
  and cropped so that half-covered badge never ships.

Everything about it degrades to the plain card, silently: no fixes in the recording, a
document analysed before the geographic anchor existed (`view.geo`, added by
`web/lab_bundle/web_entry.py`), no network, a tile server that will not answer, a tainted
canvas. A rider on a beach still gets a card.

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

Three details of the QR are load-bearing rather than cosmetic and are the same on both
platforms: it is **dark-on-light with its own light plate**, because the card's background is
navy or somebody's photo and a decoder needs the light half to be light; it is drawn at
**~96 px at 1080 width** from a **nearest-neighbour** upscale with a four-module quiet zone,
because the generator emits one pixel per module and any smoothing turns every module edge
into a grey ramp for a decoder to guess at after a chat app has recompressed the picture; and
it carries the **brand mark in its centre**, below. iOS renders it with `CIQRCodeGenerator`
(`BrandQRImage` in the kit, drawn by `ios/WingFoil/Features/Share/BrandQRCode.swift`) at
correction level M — a short URL, a clean digital image, and bigger modules matter more here
than damage tolerance. The web draws the same symbol from a committed 33 × 33 PNG
(`web/icons/qr-cleanjibe.png`, one pixel per module, quiet zone included) with
`imageSmoothingEnabled = false` at 99 px, which is the same 3× nearest-neighbour upscale: the
URL is fixed, so a QR library in the bundle would be a dependency to draw a constant.

**The mark in the middle, and why it is exactly five modules.** An unbranded code in the
corner of a picture is an anonymous grey square; the app's own icon on a small rounded white
plate at its centre makes it visibly *this* app's link, which is the entire job of a footer
that exists to be followed. The plate is **5 modules** across the centre of the 25-module
version-2 symbol — 25 of its 625 cells, **4 % of the symbol's area**, against the ~15 % of
codewords level M's parity can rebuild — and the mark itself is three quarters of that, so a
white rim keeps the artwork's dark edge off the dark modules it abuts. Three constraints fix
the number, and all three were measured rather than assumed:

- **Parity.** 4 % is a quarter of the budget, and the rest is left for the real enemy, which
  is a chat app's recompression of a photograph of a phone screen.
- **The alignment pattern.** Version 2 puts its 5 × 5 alignment block at module 16, and
  parity cannot substitute for it: a decoder that cannot find that landmark never reaches
  error correction. Five modules stops a clear module short of it, which is why decoding
  fails *abruptly* at six modules rather than degrading — the measured cliff is 5.75 (every
  export size decodes) to 6.0 (a fifth of them stop).
- **Odd.** The symbol's centre is the middle of a module, so only an odd-width plate lands on
  module boundaries; an even one would leave a rim of half-covered cells for a decoder to
  threshold.

The number lives in `BrandQRImage.markModules` and `QR_MARK_MODULES` in
`web/js/sharecard.js`, and the two must agree. The **committed PNG stays unmarked**: at one
pixel per module a baked-in mark would be a five-pixel square, so the web composites the
plate at draw time and it scales with the render. What makes this safe is not the arithmetic
but the decode: `BrandQRTests` renders the code at every size the app exports it — as PNG and
through JPEG q50/q35 — and reads it back with `CIDetector`, each marked case paired with the
unmarked control and with an oversized-mark case that must *fail*; the web's six card renders
(3 shapes × 2 presets) are decoded the same way with OpenCV, PNG and JPEG q50.

Note the case, which is deliberate: **CleanJibe** is the brand, *wingfoil* in the call to
action is the sport. The word WingFoil survives only as the Xcode target, the module and the
bundle ids (`de.lahmann.wingfoil.*`, unchanged — renaming them would orphan the TestFlight
build, the BGTask registration and the keychain), and as the name of the **Garmin watch app**,
which the phone app still refers to by that name where it means that app.

The same footer closes a replay clip (`ReplayClipCards`), which is the frame a viewer is left
staring at while the clip loops — the one frame worth pointing a camera at.

### Uncertified speed — the one mark a degraded source always wears

A speed record is only trustworthy when it came off the receiver's Doppler channel. A source
that carries positions but no speed channel — **every GPX** (engine 0.9.0), and the occasional
converted export — has its speed differentiated from positions instead, which is noisier and
biased upward on a bad fix. Those records are still shown, because they are still the rider's
session; they are shown **marked**, because an all-time best is exactly where a number nobody
can verify does the most damage.

The rule is read from one field, `sourceClass == "c"`, and nothing downstream of the parser
knows the word GPX:

| surface | mark |
|---|---|
| session badge | `limited data` (web `render.js`), `SessionDisplay.sourceClassNote` (iOS) — the title/subtitle names both absences: estimated speed, no pump data |
| records table | an `uncertified` chip beside the **value** (web `trends.js`, iOS `RecordsView`) — beside the claim, not beside the session |
| personal bests | a class-(c) effort never fires the celebration (`PersonalBestDetector.improvements`). The clean-jibe records are exempt: a jibe count is not a speed and a bad fix cannot inflate it |
| share card | `disclaimer` — "Speeds from a degraded source — uncertified" (`ShareCardStats`, `cardDisclaimer`) — the card leaves the device, so it cannot be read as a speed claim |

The same source class also has no accelerometer, so the pump and takeoff-effort figures are
absent rather than zero, by the never-a-flattering-zero rule the goldens already follow
(docs/testing.md).

### A clip can carry the rider's own music, and only his own

The replay clip is muxed after recording, never during (iOS: `ReplayClipSoundtrack`,
`ReplayClipCropper.export`): the microphone is off and stays off, the recording's own audio
track is dropped by construction rather than by a setting, and the track the rider chose is laid
under the finished video — trimmed if it is longer than the clip, repeated from the top if it is
shorter, with a 0.8 s fade in and a 1.5 s fade out. The setup sheet's Music row defaults to
**None** on every clip (unlike the length and the shape, which open where the last one left
them) and carries one line: *"Use music you have the rights to share."*

**The seam for bundled tracks is deliberate and unfilled.** Everything below the sheet takes a
file URL and asks nothing about where it came from, so a "pick one of ours" row would be a
second way of producing that URL and no other code would change. What is missing is not code
but licensed audio: a track shipped inside an app whose riders then post the results to social
networks needs a licence written for exactly that use, and nothing from a commercial streaming
service can ever be one — those files are DRM'd, the APIs hand out stream handles rather than
samples, and the terms forbid redistribution outright. Hence the rider's own file, and the
caption saying whose responsibility the rights are.

## Sections — how a session divides

Both apps open on the key-metrics block and then **switch between four sections**, in this
order: **`Ride` · `Turns` · `Takeoffs` · `Log`**. The ids and the words are `SessionSection`
in the kit. The alternative was measured: one column of ~3 800 pt on the phone and ~6 000 px
on a phone browser, five unrelated subjects deep, with no way to the fifth except through
the other four (`app-ui-review.md` §3.1, §7.2).

| section | holds |
|---|---|
| **`ride`** *(default)* | the map, its legend, the speed chart, the replay scrubber, the foil tiles and the speed-records table — one instrument, one section |
| **`turns`** | the turn cards, then the two filters, the outcome tally, the maneuver map and the turn list |
| **`takeoffs`** | the failed-attempt headline and the takeoff & pumping tiles, then the attempt map and list, then the HR card ("What pumping cost") |
| **`log`** | the gear card, the wind detail, the recording's provenance, and the watch-vs-phone table |

**The four were re-cut on 6 Sep 2026** (Jan), from `Map · Speed | Turns | Takeoffs | Effort`.
Two rationales, and both are about a name describing the wrong thing:

- **Takeoffs and Effort were one subject split by sensor.** The takeoff tiles counted
  attempts off the accelerometer and the HR card priced those same attempts off the optical
  heart rate — "how many did I have to pump for" and "what did the pumping cost" are the same
  question asked twice, and the app was answering them on two tabs. The word gave it away:
  **"effort" was already the map legend's name for the GP3S record window**, so a section
  called Effort was competing for a word the map had spent. The HR card is under the takeoff
  content now and its heading dropped the redundant half (§ "The HR card's own title").
- **The session's own facts had nowhere to live.** The recording's provenance was a footer
  repeated under all four sections, the wind axis the whole analysis is named against was one
  grey line under the date, and the watch-vs-phone table was hidden inside a warning banner
  most riders dismiss. Three facts about the *record*, filed as page furniture. `Log` is
  where they are, with the gear card, which was already the same kind of fact. There are no
  placeholders on it for anything else.

`Ride` replaced `Map · Speed` in the same move: the middle dot was load-bearing while the
name was a list of two figures, and it is dead weight beside three one-word siblings. The
section is the ride — where it went and how fast — and the two figures on it are how it says
so.

**Every scroll anchor that existed keeps working, and two changed section rather than name**:
`hr` is on `takeoffs`, `gear` is on `log`. A jump to an anchor — a deep link, a screenshot
hook (`UI_SCROLL_TO`), the divergence banner's tap — **must select the anchor's section
first and then scroll**, because a scroll into an unselected section's subtree reaches
nothing at all, silently. The rule is `SessionSection.tabChange(for:current:)`, and it
returns nil for an anchor already on screen and for `key`, which is above the switcher and
therefore on every section.

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
  is the raw-output panel (`Data`) rather than an empty one; an honest label beats a matching
  one.
- **The web still carries the pre-re-cut ids** (`mapSpeed` … `effort` on `data-section`)
  until it is re-cut to match. The two apps are meant to be the same product and this is a
  known, temporary divergence: the analyzer has no HR card and no gear, so `Log` and the
  Takeoffs merge do not transfer unchanged, and the re-cut is an iOS commit.

### The HR card's own title

The card under the takeoff content is headed **"What pumping cost"**, not "Effort — what
pumping cost". The tab it used to sit on carried the first two words, and a card that repeats
its section's name in its own heading is decoration that says nothing (§ "Tables over tile
walls"). The section already says Takeoffs; the heading only has to say which half of the
takeoff question this half answers.

### The divergence banner is one line, and it links

The watch-vs-phone banner sits under the key-metrics block, as it did, and it is now a
**one-line warning with a chevron**: the four-column table it used to unfold in place is on
`Log`. Tapping the banner selects `Log` and scrolls to the table. The dismiss X is unchanged
and still per session and per divergence (`DivergenceDismissal`). A disclosure that put the
most technical thing on the page in the second most prominent place on it was the wrong
weight for a provenance footnote; a banner's job is to say there is something and to take you
to it.

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
says nothing. **5×10 s highlights all of its windows** — up to five disjoint runs, five
glows on the track and five bands under the chart — because the record *is* the five and
one segment misnames it (iOS drew only the top run until 6 Sep 2026; the web always drew
the list). **The session header carries no numbers**: it is the date, the discipline badge
and the wind line, because duration and distance are the block's first two cells eight
points lower and the block is the contract the card mirrors (6 Sep 2026).

## All-time records — two tables, one page

The **speed table** is the nine GP3S kinds above, and it is the only one that can carry the
`uncertified` mark (§ "Uncertified speed"). Under it sits the **session records** table: the
best *afternoons* rather than the best windows, in this order on both platforms —

`Longest flight` (with its distance in the row, because six minutes downwind and six minutes
of pumping in a lull are not the same flight) · `Most flights` · `Highest on-foil share` ·
`Most clean jibes` · `Best CPH` · `Best clean-jibe rate` · `Longest dry streak` · `Longest
flew streak` · `Longest session` · `Most distance`.

- **CPH is `jibesSuccessful / (durationS / 3600)`** — clean jibes per hour of session time,
  the elapsed hour and not the on-water one, so the number a rider quotes is the one the
  afternoon actually cost him.
- **The clean-jibe rate needs at least five jibes**, and the row says so. Four out of four is
  a good afternoon; it is not a rate. The floor is one constant on each side
  (`SessionRecordKind.minJibesForRate`, `library.MIN_JIBES_FOR_RATE`).
- **No certification here.** A degraded recording can misreport a speed; the number of jibes
  it holds and the minutes it lasted are not claims its speed channel makes, so the badge
  the speed table wears would be answering a question nobody asked.
- Same filters and the same exclusions as the speed table (spot / gear / since; the example
  session, a provisional row and a friend's afternoon count in neither), and the same tie
  rule: **a tie goes to the earliest session** — the record was set then, not re-set later.
- **Absent is never zero**, and here it bites twice: a stored row written before the counts
  existed (web digest schema 5, iOS schema v10) has no clean-jibe count and no streaks, and
  a kind nobody has a positive value for is dropped from the table rather than shown as a
  dash or a flattering `0`.

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
| 2 | `hours` | hours on the water | Σ `summary.durationS` (the engine's cleaned span) |
| 3 | `distance` | distance | Σ `distanceKm` |
| 4 | `flights` | flights | Σ `flightCount` |
| 5 | `foilPct` | on foil | Σ foil time ÷ Σ **on-water** time |
| 6 | `cleanJibes` | clean jibes | Σ `jibesSuccessful` |
| 7 | `cph` | CPH · clean jibes per hour | clean jibes ÷ hours |
| 8 | `turns` | turns | Σ counted turns |
| 9 | `cleanJibeRate` | clean-jibe rate | Σ clean ÷ Σ jibes, ≥ 5 jibes |
| 10 | `wph` | WPH · swims per hour | Σ fell-in flight ends ÷ hours |
| 11 | `best2s` | best 2 s | max |
| 12 | `best10s` | best 10 s | max |
| 13 | `longestFlight` | longest flight | max |
| 14 | `longestDryStreak` | longest dry streak | max |
| 15 | `spots` | spots visited | distinct clusters |

- **Rates over a period use the summed denominators, never the mean of the per-session
  rates.** Ten minutes with one clean jibe and three hours with three is not "6.0 and 1.0,
  so 3.5 an hour"; it is four clean jibes in three hours and ten minutes. The same rule
  already governs the library totals' on-foil share and the gear rollup's.
- **The hours are the engine's own session spans** — `summary.durationS`, the *cleaned*
  first-to-last span every per-session rate divides by (docs/algorithms.md "Session rates").
  It is deliberately **not** the row's other duration: the analyzer's `durationS` is the
  FIT's `total_elapsed_time` and the iOS row's is the raw sample span, and on the corpus's
  Rheinstetten afternoon those are 10338 s against 7742 s. A month holding a single session
  has to report that session's CPH and not a second opinion about it, so both platforms
  store the engine's span beside the other one (digest schema 7 `rateDurationS`, GRDB v12).
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
  block's half of "a missing value is absent, never 0", and it is also what lets a card
  preset be a strict subset: anything the block did not produce was never there to keep. A
  measured zero is still a value and prints as one (`0.0` swims per hour).
- The formatters are the key-metrics block's own (`KeyMetrics.duration` / `km` / `knots` /
  `rate`, and their Python twins), so a duration on a period card reads the way a duration
  reads on a session card.

### The period card

**A second card kind, and deliberately the same card.** Same three shapes at the same pixel
sizes, same footer — mark, wordmark, `analyze your wingfoil sessions free — cleanjibe.org`,
QR — same title-and-one-caption header, same two presets. Everything in "The share card
carries the same block" above holds here unchanged; what differs is only what is being
described.

| | session card | period card |
|---|---|---|
| stats | the key-metrics block | the aggregate block |
| `lean` | duration · distance · max 2 s · tally | sessions · hours · clean jibes · CPH · best 2 s |
| date line | the session's day | the period's span |
| title default | the session's name | the period's title |
| artwork | the track outline | **the period's outlines, stacked** |
| map background | optional, off by default | optional, off by default — **offered only where the period is one place** |
| speed disclaimer | on a class-(c) source | never |

- **A preset may only drop entries**, held as keys (`PeriodBlock.leanKeys`,
  `library.PERIOD_LEAN_KEYS`, `PERIOD_LEAN_KEYS` in `js/cardstats.js`) — the same rule and
  the same reason as the session card's.
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
cannot pin the phone to an answer the analyzer no longer gives. `verify_library.py` §6 asks
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
- Splash evidence comes from the engine's submersion flags (turns, flight ends); the UI
  never re-derives it.

## Filter semantics

Turn filters are type (`both | jibes | tacks`) × side (`both | port | starboard`), ANDed.
**Side means the ENTRY tack — the tack you came into the turn on — never the rotation
direction.** UI copy must say "Port entry / Starboard entry"; bare "left/right" is a
misread waiting to happen. Both turn fields exist in the schema (`side`, `direction`);
filters and trends read `side`. Anything that draws a side in colour uses the `side.*`
tokens above and nothing else.

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

**The chips under the numbers**, in order: the outcome, `clean` where the engine says so,
`pumped out` where `pumped`, `wrist under` where `submerged`.

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
| 7 | `cleanAndFast` | `success && score ≥ 0.85` | clean, and barely slowed |
| 8 | `cleanButSlow` | `flew_through && score < 0.7` | flew through, and it cost |
| 9 | `slowedEarly` | low point before halfway | the speed went before the mid-point |
| 10 | `slowedLate` | low point at or after halfway | carried it in, lost it on the way out |
| 11 | `plain` | nothing above, or no usable geometry | the three numbers, said plainly |

Rungs 1 and 7 are the same score test read from the two sides of the outcome, which is what
keeps `cleanAndFast` honest without a `clean` clause of its own: every fall and every
touchdown has been taken by a rung above it, so by the time the ladder reaches 7 the turn
flew through, and for a jibe that is exactly `clean` (engine 0.12.0). `fellInFast` exists
because that turn — the speed held all the way round, the foil gone in the recovery tail —
is the one the old rule called clean, and the one sentence that must say both things.

"Halfway" is where the sweep has turned through **half its cumulative heading change** — not
half its `netDeg`, because a sweep that overshoots and comes back has swept more than its net,
and not half its duration. A jibe's halfway point is called the **downwind point**, a tack's
**head-to-wind**, and an unnamed sweep's the **middle of the turn**. Rules 4/5 and 8/9 need it;
where the window has too few usable bearings to say, no rule that depends on it may fire and
the ladder falls through to `plain`.

iOS: `TurnSlice` + `TurnCoach` + `TurnSpeedRamp` in the kit (pure, `TurnSliceTests` /
`TurnSpeedRampTests`), drawn by `TurnDetailView` / `TurnDetailMapView` /
`TurnDetailStripView`. The drawing is a SwiftUI
`Canvas` and deliberately not a `MapKit` map: the frame has to rotate, and the ticks must not
move under the reader on a camera settle. There is no ground under it — a satellite tile at
30 m across is a photograph of water, and it would bury all six of the things the drawing says.

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
