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

**A clean jibe is a counted jibe you fly all the way through, carrying your speed, and stay
up for ten seconds after — no touchdown, no swim, at or above the success threshold of your
entry speed.**

That is the engine's per-turn `clean` flag, and every surface reads it rather than
re-deriving it: `counted && type == jibe && success && outcome == flew_through`, plus a quiet
`turnCleanQuietS` after the sweep (`docs/algorithms.md`, "The quiet tail"). The metric was
called "turn success" or "carried through" or "held speed" on four screens and is called one
thing on all of them.

**The quiet tail is the third clause, and it arrived on 7 Sep 2026** (engine 0.17.0). Jan:
*"an additional requirement for a clean jibe: no touch down or fall within 10 s afterwards.
This only applies to clean jibe, not to carried through."* A turn's outcome window closes as
soon as the rider is flying again, so a jibe powered straight out of is judged over two
seconds and the touchdown at +7 s belongs to the flight-end channel — right for the ladder,
wrong for the word. On the corpus it costs 15 clean jibes in 278. Only `clean` moves: the
outcome chip, the score, the counts and both streaks say exactly what they said before, which
is why a rider who reads "flew through" over a jibe with no star has to be told why — see
"Turn detail".

**Until engine 0.12.0 clean was the `success` flag alone** — the score verdict, deliberately
independent of how the turn *ended*. That let a jibe be starred as clean on the map and
listed as a swim in the table six rows below it, which is what happened to 2026-08-29's jibe
13: 71 % of its entry speed held, 54 s off the foil, in the water. The word had to mean what
a rider means by it, so the outcome joined the verdict and the clean counts fell on eleven of
the seventeen fixtures.

**The rider has two tiers, and `success` is not one of them** (7 Sep 2026). What a rider
reads is:

| tier | what it asks | engine |
|---|---|---|
| **flew through** | did the foil survive the turn *and* the recovery out of it — no touchdown, no swim | `outcome == flew_through` |
| **clean** | that, **and** did it hold its speed, **and** were the ten seconds after it quiet — a jibe word | the per-turn `clean` flag |

`success` / `turnsSuccessful` / `successPct` / `tacksSuccessful` — the score verdict on its
own, over every counted turn — is an **internal** quantity. It is the input to `clean` and
it is never a label: no card, row, chart, caption, column or total may print it under any
name. It was briefly to be called "carried"; that name is retired, and the word does not
appear on a surface. What *is* rider-facing is the **score** itself — "held 71 % of entry
speed" — because that is a number and its meaning is on its face; a boolean derived from it
is a verdict the rider did not ask for.

Where a surface used to print the score verdict, it prints the **outcome** instead: the
session grid's card is "Flew through" over the jibe share, the trend chart is
"Flew-through rate" over every counted turn, the library totals row is "Flew through", and
the per-turn table keeps `score` and `clean` and dropped its boolean column.

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
| `splash` | **wrist under** — one cyan diamond per submersion episode | visible | engine 0.16.0: one mark per *episode*, not per flagged turn/end. Rider-facing name is "wrist under"; the id stays `splash` |
| `direction` | course-of-travel chevrons along the track | visible | decimated by on-screen spacing |

Layer visibility persists on iOS (hidden-set; unknown ids must decode harmlessly so old prefs
survive new layers) and is transient on web. Legend chips are the only toggle surface; a
struck-through chip means hidden.

### "Wrist under" — one mark per submersion, on every map

Jan, 7 Sep 2026: *"do we see all 'watch / arm in water' events on the map?"* The answer was
no. The layer drew the `submerged` **flag** on a turn or a straight-line flight end — one
mark per maneuver that happened to own a dunk, at the maneuver's own start — so the 29 Aug
session showed four marks where the barometer had seen thirty-five submersions, none of them
where the wrist actually went in. The engine now carries the episodes themselves
(`SessionAnalysis.submersions`, engine 0.16.0, docs/algorithms.md "Submersion episodes") and
the layer is one mark per entry. Five rules, and every surface obeys all five:

- **The name is "wrist under."** Chip, legend row, layer options, callout title, docs. The
  *id* stays `splash` — it is what the stored preferences, the token catalogue and both
  platforms' goldens are written in, and this is a rider-facing rename, not a data one.
- **The mark is the cyan diamond**, the one the thumbnails and the share card have always
  drawn (`effort.splash`, #3fc4d8, `diamond.fill` / the web's `diamond`). It replaced a drop
  glyph so that map, thumbnail and card are one picture; the colour token did not move. Shape
  as well as colour, for the reason the thumbnail already gave: a submersion usually sits on
  the fell-in verdict it belongs to.
- **It is placed at `ts`** — the first submerged sample, the moment the pressure stepped —
  and never at the turn's start or the flight end's.
- **It is on all three maps and visible by default**, on Ride, Turns and Takeoffs alike. The
  overlay set is consistent across the three maps by standing decision, and Turns gained it on
  7 Sep 2026: a rider who finds a diamond on the ride map has to be able to find the same one
  on the page that is about the maneuver he went under in. Deliberately **not** filtered by
  the Turns page's type/side segments — an episode belongs to the afternoon, not to the subset
  the page is currently asking about. Default-visible is the point of the whole change: Jan
  asked for this layer because he could not find it.
- **The legend tally counts episodes**, and so does `splash` in the presentation goldens.

**The callout** (tap, like every other mark — `TrackContent.onMarkTap` on iOS, the tooltip
and the row block on web), worded identically on both platforms:

| line | text |
|---|---|
| title | `Wrist under · 4 s` — the episode's `durationS`, dropped rather than printed as "0 s" when the run rounds to nothing (at 1 Hz a single sample is an instant caught once, and a zero would read as a measurement) |
| detail | `during jibe 7` (its `turnIndex`, numbered the way the turn sheet numbers it: the rider's *n*-th turn of that kind) · `after flight 10 ended, stopped 6 s` (its `flightEndIndex`; the stop is dropped under 1 s) · `while off foil` (neither — a real answer, not a missing one) |

**The turn page's chip carries the length too**: `wrist under 4 s`, from the longest episode
attributed to that turn, and plain `wrist under` where the flag is set but no episode is
named — the same "never a fabricated zero" rule the `pumped out` chip beside it obeys.

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
  | `turns` | `direction` · `cleanJibe` · `flewThrough` · `touchdown` · `fellIn` · `courseChange` · `splash` |
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
| events | **clean jibe** · flew through · touchdown · fell in · course change · takeoff · wrist under |
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
- **The count is of layers this session actually has any of.** A rider who hid "wrist
  under" months ago is not told something is off on every session he never went under on; the
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
takeoff · wrist under
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
  once and the floating legend live. **The screen it opens is titled `Map`** (19 September
  2026, pattern A): it used to wear the session's name, which named the session and not the
  screen, so its only name was the label on this door. The session's name is the caption
  under it.

## Map style — the ground under the track

Four grounds on iOS, one choice: `standard` · `muted` · `satellite` · `hybrid`, persisted per
rider in `mapStyle.v1` (`MapStyleChoice`, `MapStyleStore`). Standard is the default and is what
every map used to be. The web has two, and they are the two it has — see "The web's ground"
below.
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

**The web's ground: Map or Plain.** The Ride tab's track map draws over the same
OpenStreetMap raster tiles the share card uses (`web/js/trackmap.js` on `web/js/cardmap.js`),
under the same `MAX_TILES` ceiling and with the same no-retry rule: a failed tile is a hole,
a wholly failed fetch is the plain figure. It is **off until the rider presses Map**, and the
choice is remembered per device in `wingfoil.trackMap.ground.v1`. There is no four-way picker,
because the layer has no satellite twin and a control offering four names for one ground would
be a control that lies. The toggle and the `© OpenStreetMap contributors` credit sit in the
legend's utilities group, where the iOS legend keeps its own style chip, and the credit is
drawn in the figure's corner as well — the figure travels into a screenshot and the legend
does not.

With tiles behind it the fit is **Mercator's**, not the engine's local metres, so the
breadcrumb sits on the earth the tiles are pictures of; the framing is chosen so the ride
lands in the box it would have occupied on the plain figure. The readability rule is the
card's rather than the phone's: rather than flipping any ink, the ground is drawn *into* the
dark surface at half opacity and the two phase runs gain a casing in the surface's own colour,
so every ink stays exactly where "Colour and glyph vocabulary" put it.

**The web's full-screen map is the same map.** "Open map full screen" moves the figure and its
legend into a full-viewport shell and draws them at the window's size — same camera, same
playhead, same layer chips, Escape or Back to leave. Not a second map: a second map would be a
second camera and a second playhead to keep in step with the first. Rotate is not offered, as
the figure is north-up by construction and the wind arrow and the chevrons are read against
that.

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
pumping = indigo (spans) · takeoff = blue (glyphs) · wrist under = cyan (diamond) ·
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

## Text size and theme — the app follows the phone

**There is no app appearance setting, and there is not going to be one.** The iPhone app
follows the system's light/dark appearance and the system's text size, and both of them all
the way down: the chrome is system materials, every surface is a semantic colour
(`Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `.primary`, `.secondary`,
`.tertiary`, the accent), and every string is set in a text style rather than a point size.
Two screens set `preferredColorScheme(.dark)` and only two — the **splash** and the
**Welcome** screen — because both are painted in `Brand.navy` rather than on a system
background, and the system controls and the status bar drawn on top of that navy have to be
told what is underneath them. They are the launch screen continued; everything behind them
is the phone's own appearance.

**A text field the app draws is drawn by the app, not borrowed.** `.textFieldStyle(.roundedBorder)`
fills itself with `systemBackground` — pure black in dark mode — and the intervals.icu key
field sits on the setup card's `secondarySystemBackground`, a near-black grey. Two
almost-identical blacks with a hairline between them is a solid bar, not a field: nothing
tells the rider where to tap, and an empty `SecureField` has no dots to give the game away
either (Jan, build 58, dark mode only — in light mode the same two tokens are white on light
grey, which is why half the phones never showed it). So any field the app draws on a surface
of its own wears `appTextFieldChrome()`: a `tertiarySystemGroupedBackground` fill, a step
*lighter* than the card in dark (#2C2C2E on #1C1C1E) and a step *darker* than it in light
(#F2F2F7 on white); a hairline `separator` border, so it is still a field where the fill
matches its background; and explicit `.primary` text with an accent caret rather than
whatever the enclosing card set. Two fields wear it — the **intervals.icu key** and the
**period card's title and caption**, which sit in a plain `ScrollView` and had the identical
problem.

**The same mistake one level out: a semantic colour is only semantic against the background
it was named for.** The empty library's setup card painted itself `secondarySystemBackground`,
which in light mode is the same #F2F2F7 as the *grouped* list it is a row of — a card with no
edges, on the one screen a rider meets first. That card is the **ways-in card** now
(`LibraryView.waysInCard`, dev 70); it and its intervals.icu problem note use the **grouped**
pair (`secondarySystemGroupedBackground` / `tertiarySystemGroupedBackground`), white on
#F2F2F7 in light and #1C1C1E on black in dark, and so does the "What CleanJibe does" row
above it. The
plain `secondarySystemBackground` cards elsewhere — the key-metrics block, the summary grid,
the HR card, the turn and takeoff tables, the scrubber, the help topic's glossary block, the
share composer — all sit on `systemBackground` in a `ScrollView`, where that token is the
right one and reads in both themes. Fields **inside a `Form` or
`List` row are left alone**: there the row is the field's background and the system already
gets the contrast right in both themes (gear's name and notes, the rename alerts, the rider
prompt). The **session share composer's** two fields are deliberately unchromed — the title
is edited at `.headline` as the session's own name, and it is `.primary` on the sheet's own
background, which reads in both themes.

**Point sizes are for figures, not for text.** A literal `font(.system(size:))` survives in
exactly four places, and each is a picture rather than a paragraph: the **share card** and
the **reel's clip cards**, which are rendered at a fixed pixel size into a PNG and an MP4 and
must look identical on every phone; the **map annotations** (the outcome dots, the takeoff
arrow, the clean-jibe star, the map legend) and the **turn page's canvas figures**, whose
glyphs are sized against the drawing and not against the reader; and the cinema's 3·2·1
countdown, one digit already larger than any text size would make it. The turn strips' small
words are the one middle case: they scale, and stop at 1.6×, the point at which two
neighbouring captions in a 1.5 s-wide band start to print over each other.

**What is capped, and why.** Everything a rider reads as prose scales to `.accessibility5`.
A row that is three or four *columns* wide cannot — at 310 % the columns alone are wider than
the phone, and the result is a truncated table rather than a large one — so those rows stop
at `.accessibility2`, roughly double the default and the last size at which a row is still a
row (`denseRowTypeSizeCap()`, one name so every capped surface caps at the same place). The
capped surfaces are: the **key-metrics block**, the **speed-records table**, the **all-time
records table**, the **turn list** and the **takeoff list**, the **watch-vs-phone
divergence table**, the **library row's two figure strips** (the row's title and date above
them scale the whole way) and the **gear row's five figures**. The **splash** is capped for a
different reason: its words
hang in a 320 pt block — the width of the narrowest supported phone — and "CleanJibe" set in
`.largeTitle` fills that at about `.accessibility2`, past which the wordmark would hyphenate,
which is the one thing it may not do. Everything on it is repeated on the Welcome screen,
which scales without a ceiling.

**Columns grow with the type** (`scaledColumn(_:relativeTo:)`, a `@ScaledMetric` frame): a
92 pt record-name column pinned to `.subheadline` grows in step with the `.subheadline`
inside it, so the table stays a table instead of truncating the very name the width was
chosen to hold. Card grids scale their `.adaptive` minimum the same way, so a two-up grid
falls to one column of full-width cards exactly when two stop fitting. **Label-and-value
pairs stack** at accessibility sizes rather than squeezing: the gear card's rows and the wind
card's rows put the value under the label instead of beside it, and the key-metrics tiles go
two to a line instead of three.

**And two surfaces give the table up rather than shrink it.** Scaled columns hold to about
`.accessibility2` and no further, so past the accessibility threshold the **all-time records
row** stops being four columns: the name takes the width it needs, the value keeps the right
edge, and the delta leads a second line with "when · where" behind it — the header
disappears with the columns it named, because a heading over nothing is worse than none.
The **spot/gear filter bar** on Records and Trends becomes a horizontal scroller for the same
reason: "All spots" truncated to "All s…" is a filter that no longer says what it filters.

**Data colours do not change with the theme, by design.** The generated palette in
`DesignTokens` (`design/tokens.json`) is the contract — the outcome ladder (flew through /
touchdown / fell in), the clean-jibe mint, the effort inks, the phase tints, the entry-tack
brown — and the speed ramp's five authored stops. Those are *meanings*, not decoration: the
same green means "flew through" in light and in dark. `TrackHalo.ink` (55 % black under a
track drawn over satellite imagery) is fixed for the same reason, and `Brand` — the navy, the
green, the paper — is fixed because the surfaces it paints (the exported card, the splash,
the confetti) have no system background to adapt to. Everything that is *not* a data colour
is semantic and flips with the theme; see "Colour and glyph vocabulary" above for which is
which, and `TrackHalo.ink(_:on:opacity:overImagery:)` for the one place a semantic ink is
resolved against the ground instead of the theme.

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
  resolved has no jibes at all, so it falls back to every counted turn ("of 51
  turns") — an empty ladder over an afternoon of turns would read as "nothing
  happened". The tally is a verdict, so it may wear the
  ladder, and the **library row** wears it too — over every counted turn there, which is
  what a row scanned against its neighbours has to be. The web rows carried no tally at all
  until §5.6, on the more prominent of the two library surfaces; a row from a digest
  written before the field existed renders "—" rather than three zeroes.
  - **The clean count rides in the caption, not in a cell.** It is `jibesSuccessful` — the
    clean count — against the jibe ladder, and **the turn fallback carries no clean clause
    at all**: it read `turnsSuccessful` there, which is the score verdict over every counted
    turn printed under the word for a stricter, jibe-only one, and a session whose wind axis
    named no jibes has no clean jibes to report. The fallback caption is "of 51 turns", full
    stop (7 Sep 2026). A fifth cell on row 3 is a cell the streaks pair would lose, and the
    count is a *qualification* of the tally rather than a metric standing beside it. It stays
    in neutral ink — see "Clean jibe" above.
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
  - **The floor is on the records table too**, not only on the celebration (7 Sep 2026).
    `SessionRecordKind.bestCph` and `library._cph_record` apply it; before that the table
    had no floor and the confetti did, so "Best CPH" could name two different afternoons
    in one app. It bites on this corpus: the highest CPH of all belongs to a session under
    eleven minutes, and `verify_library.py` asserts that it does not hold the row.
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
- **Row 4 degrades JPH to TPH, not to zero — and CPH goes with JPH.** When the wind axis
  named **no jibes** while turns were counted, the row shows `turnsPerHour` labelled TPH,
  **and no clean-jibe cell at all**: CPH is a jibe rate, and "0.0 clean jibes per hour" over
  a session that named no jibes would be the precise lie the TPH fallback exists to avoid.
  Where jibes *were* named, a `0.0` CPH is a measured verdict and is printed as one. WPH
  needs no fallback: a fell-in flight end is a fall whatever the wind was doing. A session
  with a duration and genuinely no turns keeps JPH and CPH at `0.0`, because those are
  measured zeroes.
  - **The gate is `turns.jibes > 0 || turnsPerHour <= 0` — the jibe *count*, not the jibe
    *rate*** (7 Sep 2026). It was `jibesPerHour > 0`, and a rate cannot tell "the wind axis
    named no jibes" from "it named fifteen and he swam out of every one": both read
    `jibesPerHour == 0` beside a positive TPH. The second is a session made entirely of
    jibes, and it was getting the TPH fallback and no CPH cell — the exact inverse of the
    rule above. `turns.jibes` is what row 3's tally already gates on, so the two rows can
    never disagree about whether the afternoon had jibes in it. No corpus fixture is that
    session, so both platforms write it down: `card_parity.mjs`'s `allWetJibes` case
    (asserted by `verify_presentation.py` §5a) and
    `PresentationTests.keyMetricsKeepBothJibeRatesWhenEveryJibeWasSwum`.
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
  | `device` / offset NULL | the existing **no timezone in this file, times shown on your own clock**, which is already the honest sentence: this is not the session's zone at all |

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

**The picture travels with one sentence** (`shareCaption` in web/js/sharecard.js and its twin
`ShareCaption.line` in the kit, 14 September 2026 — **both platforms**): the card's own title,
its date line, the foil share and the clean-jibe count, then “— analysed with CleanJibe, free
at cleanjibe.org”. That is the one em dash either platform is allowed in a shared string; it
separates the report from the offer, and everything inside the report is separated by “·”. It
is passed as `text` and `url` beside the file on the web and as `ShareLink`'s `message:` on
iOS, so a forwarded card carries what it is and where it came from in quotable words rather
than only in 9.5 pt type in its footer — and so a notification, a reply quote or a screen
reader, none of which has the picture yet, still says the afternoon. Built from what the card
is already holding, so it can never describe a different session than the picture; the two
numbers are read off the session row rather than off the card's cells, so a `lean` card and a
`complete` one of the same afternoon carry the same sentence. The clean count is gated exactly
as the tally's caption is (no named jibes, no clean clause), and an absent number drops its
clause rather than printing a zero. `ShareLink`'s `subject:` is the same sentence **without**
the offer — a subject line is a name for the thing, and an invitation in one reads as an
advertisement. Where the browser will not carry text beside a file
(`navigator.canShare({files, text})` false), the file still goes and the sentence goes on the
clipboard instead, with *Caption copied* under the dialog's buttons.

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

**An imported name keeps its own capitalisation.** A derived title is read back out of the
middle `_`-part of the archived filename, which is where the importers put the source's own
activity name — Strava's and intervals.icu's alike. That part used to be lower-cased on the
way in and then given a capital per word on the way out, so Strava's "Wingfoil am Nachmittag"
reached the library as "Wingfoil **A**m Nachmittag" and "Hallbergmoos Surfen" was a rewrite of
a name a person chose. The slug now keeps the source's case
(`SessionNaming.activityNameSlug`), and the title rule reads it: **if the stem carries any
capital at all, that capitalisation is the source's and is left alone**; a stem that is
entirely lower-case carries no information to preserve — the watch's `nago-torbole-windsurfen`,
the app's own slug of a bare spot name — and is the one case that gets a capital per word.
That is the whole of "title-case only a name the app built itself". A workout imported from
Apple Health has no name from anywhere, so its filename carries `_wingfoil_` and it derives as
"Wingfoil"; before that its stem had no `_` at all and the date was read as the name, which
printed **"08 30 Health"**.

**The Recording card's `sport` is the source's word, unbent** (`SessionNaming.sportLabel`).
Five spellings are translated because their raw form is not a word a rider would recognise
(`43` → Windsurf, `44` → Kitesurf, `32` → Sailing, `stand_up_paddleboarding` → SUP, `walking`
→ CIQ app); everything else keeps the source's own capitalisation, with underscores and
run-together `CamelCase` split into words — Apple Health's `surfingSports` reads
"surfing Sports", where `.capitalized` used to make it "Surfingsports". A source that said
nothing at all reads **Unknown**, which is the honest answer and was, until engine 0.19.0,
also the answer for every Strava import: `StravaImport` wrote the activity's sport into the
GPX's `<trk><type>` and the GPX parser never read it back. It does now (`caps.sport`), and it
is still provenance and never a discipline — ADR-004 files a wingfoil afternoon under sport
43, and `Discipline.resolve` does not take a sport code as an argument.

The card's outline carries three semantics and no more (`TrackThumbnail.Mark`): the track
tinted by foil state, a dot per **counted** turn on the verdict ladder's inks, and the
barometer's submersion evidence as a cyan **diamond**, one per episode — shape as well as
colour, because a submersion usually sits on the fell-in verdict it belongs to. Course changes get no dot, by the
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
**~144 px at 1080 width** from a **nearest-neighbour** upscale with a four-module quiet zone,
because the generator emits one pixel per module and any smoothing turns every module edge
into a grey ramp for a decoder to guess at after a chat app has recompressed the picture; and
it carries the **brand mark in its centre**, below. iOS renders it with `CIQRCodeGenerator`
(`BrandQRImage` in the kit, drawn by `ios/WingFoil/Features/Share/BrandQRCode.swift`) at
correction level M — a short URL, a clean digital image, and bigger modules matter more here
than damage tolerance. The web draws the same symbol from a committed 33 × 33 PNG
(`web/icons/qr-cleanjibe.png`, one pixel per module, quiet zone included) with
`imageSmoothingEnabled = false`: the URL is fixed, so a QR library in the bundle would be a
dependency to draw a constant.

**It grew from 99 px to 144 px** (`QR_SIZE` on the web, `ShareCardView.qrSide` on iOS —
33 → 48 layout points on the web, 32 → 48 on iOS; both changed 14 September 2026). 96 px was
iOS's old export and the floor `BrandQRTests` was calibrated against; it stays in that suite's
`exportSizes` even though nothing exports at it any more, because every card already sitting in
somebody's chat thread was drawn at it. 99 px was three whole pixels a module and read
perfectly at 1:1 — and too small where a card is actually met, as a thumbnail on somebody
else's phone at arm's length. Angular size beats crisp module edges for a camera, so the whole
upscale is no longer an integer: 144 over 33 modules is 4.36 px a module, most of them four
pixels wide and every twelfth five, hard-edged throughout, with level M's parity absorbing the
edges that land a pixel out of true. The footer's height derives from `QR_SIZE`, so the tall
shapes give the track 15 pt and the wide one gives the wordmark 15 pt of width.

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
that carries positions but no speed channel — **every GPX** (engine 0.9.0), a **TCX without
`Extensions/TPX/Speed`**, and the occasional converted export — has its speed differentiated
from positions instead, which is noisier and biased upward on a bad fix. Those records are
still shown, because they are still the rider's session; they are shown **marked**, because an
all-time best is exactly where a number nobody can verify does the most damage.

A TCX *with* that element is class (b) and certifies like any FIT, which is also why the
class-(b) badge says **"measured speed channel"** rather than "standard Garmin recording": a
Polar, Suunto or Coros session arriving through intervals.icu never came off a Garmin, and the
thing the class asserts is that the file measured its own speed.
that carries positions but no speed channel — **every GPX** (engine 0.9.0), **every session
imported from Strava** (ADR-023, which is a GPX by the time the app sees it), and the occasional
converted export — has its speed differentiated from positions instead, which is noisier and
biased upward on a bad fix. Those records are still shown, because they are still the rider's
session; they are shown **marked**, because an all-time best is exactly where a number nobody
can verify does the most damage.

Since engine 0.20.0 the shortest of them is *also* checked against the same track's best 10 s
before it is reported at all (docs/algorithms.md, "The plausibility gate"): a best 2 s more
than 1.2× the best 10 s is one bad fix rather than a run, and the record falls back to the
fastest 2 s that the 10 s can account for. Nothing on the page changes — the number is simply
one the engine can stand behind, and it still wears the mark, because the source is still a
source that could not prove it measured anything.

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

## Session video — the reel, and the clock it is drawn on

A second thing that leaves the phone, beside the card and the shared FIT: **a 9:16 video of
one session**, 1080 × 1920 at 30 fps, H.264, in which the breadcrumb draws itself over a
still map while the afternoon's highlights are called out as they pass, and which ends on the
key-metrics card. "Export video" sits under the share card in the share sheet
(`ShareComposerView`), and it is a **rider feature on both builds** — a card, a FIT and a
video are the same kind of thing, something a rider makes to show somebody, and none of them
is a threshold.

**It is not the cinema clip, and the two do not merge.** The clip (`ReplayCinemaView`,
`ReplayRecorder`) records the live glass with ReplayKit, at whatever the phone's screen is,
with the rider free to pan and zoom the map while it runs — it is *his* replay, captured. The
reel is rendered offscreen frame by frame (`ReelRenderer`: `AVAssetWriter` +
`AVAssetWriterInputPixelBufferAdaptor`, Core Graphics into the pixel buffer) and is the same
video from every phone: one fixed size, one fixed type scale, no Dynamic Type, no notification
banner in frame, no camera moves, faster than real time. That also makes it the only one of
the two a Mac can check, since `RPScreenRecorder` writes a zero-byte file in the Simulator
(docs/testing.md).

### The cut

Default **20 s**, settable 15 / 20 / 30 in the export sheet. The last **3 s** are the end
card; the rest is map.

**The whole session draws over the cut, and the clock is not linear.** `ReelPlan` (kit, pure,
tested) lays an *attention density* over the session's span: 1 everywhere, rising to **5×** in
a raised-cosine bump of half-width `halfWidthS` around every moment worth stopping for. Reel
time is that density's integral, normalised to the length of the map section:

```
reelTime(t) = mapS · ∫ d / ∫ d          (from the span's start to t, over the whole span)
```

so the clock **slows around the highlights and speeds up between them**, the whole track
draws (nothing is ever skipped), and both ends land exactly. The plan answers in both
directions — `sessionTime(atReelTime:)` for "where is frame 317", `reelTime(ofSessionTime:)`
for "which frame is this jibe on" — which is the one thing `ReplayDriver` cannot do: the
cinema replay's warp is a rate field ticked forward one frame at a time, right for a live view
and useless to a renderer that wants random access.

**The moments** are read off one analysis, all of them:

| moment | where | slows the clock |
|---|---|---|
| the **longest flight's takeoff** | `flights`, longest by time, ties to the earlier | yes |
| **every counted jibe** | `turns` where `counted && type == "jibe"`, with its outcome and its `clean` flag | yes |
| **each record window** — 2 s, 5×10 s, alpha 500 | `records.windows`, at the window's own start | yes |
| **every submersion** | `submersions` | **no** |

Every counted jibe, not a selection: a jibe drawn at 200× is a smear and at 20× it is a
maneuver, which is a statement about drawing rather than about narration — and it is why the
reel's list is a third list beside `ReplayBeats` ("where can I scrub to") and
`ReplayCommentary` ("what would a friend say"). A submersion gets its callout but no bump: it
is evidence rather than an event, it usually already belongs to a turn
(`SubmersionRecord.turnIndex`), and slowing twice for one moment is slowing wrong.

**The bump shrinks.** Forty jibes at three seconds each is two minutes of premium inside a
twenty-second cut, and the dips would merge into one flat slow reel that never gets anywhere.
`halfWidthS` starts at `span / 8` and halves until the extra density mass is at most **60 %**
of the whole — the same move `ReplayPacing.budget` makes, for the same reason — with a floor
of 0.75 s, below which the warp is near-linear, which is the right answer for a session where
nothing is special because everything is.

### The ground and the track

**One `MKMapSnapshotter` snapshot**, taken once at the region the whole track fits in, and
every frame draws over the same pixels: a reel is a breadcrumb drawing itself over a
photograph of the water, not a moving map. The framing arithmetic is the share card's
(`ShareCardMapper.frame`, and the same attribution band asked for and cropped away), and the
**rider's own `MapStyleChoice` is honoured** — a reel of a session is a reel of his map.
Taken in points at 2× rather than pixels at 1×, so MapKit draws labels and coastlines at the
weight a phone shows them at.

The track is drawn in **the map's own phase colours**, through the map's own code path:
`MapLayerVisibility.lineStyle(flying:)` → `TrackContent.color(_:on:)`, so a rider who has
hidden a phase on his map gets the same neutral line here, and `TrackHalo` puts the dark outer
edge under everything on imagery, in one pass under the whole track. Marks are the same
vocabulary every map draws — the outcome ladder as dots, a clean jibe as a **star**, a
submersion as the **cyan diamond** — popping to size over their first half-second on the
session clock, so an outcome lands as it happens.

### The overlays

- **The live strip**, along the bottom: *elapsed* (`FlightPairing.clock`), *speed* in knots,
  and the **on-foil flag** — a filled foil-teal pill while he is flying, an outline while he
  is not, the same ink as the track under it. Under them the counters that only go up:
  `"5 flew · 11 dry"`, and `"· 3 ★ clean"` when there are clean jibes to count. *Dry* is
  flew-through plus touchdown, the same set JPH counts, so the strip and the end card's rates
  are about the same turns.
- **Callouts**, one at a time, popping for **1.5 s of reel time** on a dark plate with the
  moment's own ink down its leading edge — `ReplayCommentaryBubble`'s shape, so a rider who
  has watched the replay has already learned to read it. `takeoff` · `jibe · flew through` /
  `jibe · touchdown` / `jibe · fell in` · `clean jibe` · `best 2 s 13.47 kn` · `wrist under`.
  Every word is borrowed — `TurnOutcomeKind.label` for the verdicts, `RecordKind.windowLabel`
  for the records, `KeyMetrics.knots` for the number — so the reel cannot invent a second
  vocabulary on the one surface that leaves the phone. The window opens at the moment's own
  instant and never before it: a callout that appears before the thing it names is a spoiler.
  When two are open the latest wins, because two labels over a moving map is two things to
  read and time for neither.
- **The header**, top left: the session's title and date line, from the same `ShareCardStats`
  the card's header uses.
- **A progress hairline** across the very bottom.
- The **uncertified mark** rides on the strip on a class-(c) source, exactly as it rides on
  the card: the video leaves the device, so it cannot be read as a speed claim.

### The end card

The last three seconds are **`ReplayOutroCardView`** — the cinema clip's own closing card,
which is drawn against a 390 × 700 reference and therefore lands at 9:16 without a layout
change — rendered once through `ImageRenderer` and cross-faded in over the finished track.
Using the clip's card rather than drawing a new one is what guarantees the footer is *the
share card's*: the mark, the wordmark, **the call to action and the QR**, in that order and
character for character (`Branding.callToAction`, `BrandQRImage`). Its numbers are
`ShareCardStats.outro` — duration, distance, avg speed, max 2 s, the flew · touchdown · fell
tally with its clean caption, the longest flight, and JPH / CPH / WPH.

### Where the file goes

The caches directory, under `Reel/`, named the way the shared FIT and the cinema clip are
(`FitShareFilter.filename`), so a rider's three exports of one afternoon sort together. The
sheet plays it back, hands it to the system share sheet, and **clears the directory when it
closes** — the share sheet has already taken its copy by then, and a video nobody asked to
keep is ten megabytes of somebody's phone. The render runs off the main actor, reports
progress, and cancels at whatever frame it is on.

## Sections — how a session divides

Both apps open on the key-metrics block and then **switch between four sections**, in this
order: **`Ride` · `Turns` · `Takeoffs` · `Details`**. The ids and the words are `SessionSection`
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
  most riders dismiss. Three facts about the *record*, filed as page furniture. `Details` is
  where they are, with the gear card, which was already the same kind of fact. There are no
  placeholders on it for anything else.

`Ride` replaced `Map · Speed` in the same move: the middle dot was load-bearing while the
name was a list of two figures, and it is dead weight beside three one-word siblings. The
section is the ride — where it went and how fast — and the two figures on it are how it says
so.

**`Log` became `Details` on 19 September 2026** (pattern A: a title names what the screen
does). "Log" reads as a logbook, a list of afternoons, and the section is not a list of
anything: it is the four facts about *this* session — the kit, the wind, where the recording
came from, and where the watch and the phone disagree. No narrower word covers all four, and
`Details` is exactly as wide as the section. The case, the anchors and the `app-shell.json`
id stay `log`, so every deep link written before the rename still lands.

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
- **The web has the same four, at every width, since 19 September 2026.** Jan: *"iOS is the
  reference, the web is the port"*. The analyzer's `data-section` ids are `ride`, `turns`,
  `takeoffs`, `log` (`web/js/sections.js`), its chips carry these four words, and the
  switcher no longer hides above 760 px. The earlier rules — the desktop session view as a
  single scrolling document, and `mapSpeed` … `data` as the web's own ids — are retired with
  it; the review's §3.4 note was written while the analyzer was a lab tool, and it is a tab
  of an app now. `docs/copy/app-shell.json` carries the four for both surfaces and
  `web/tools/verify_app_shell.py` reads `SessionSection.swift` from the other end, so
  neither side can rename a tab alone.
- **A section the web cannot fill says so in one line.** Takeoffs has no HR card here and
  `Details` has no gear card and no divergence table, so each prints one sentence naming the
  phone. A tab that is quietly half of what its name promises is worse than one that admits
  the half it has.

### The HR card's own title

The card under the takeoff content is headed **"What pumping cost"**, not "Effort — what
pumping cost". The tab it used to sit on carried the first two words, and a card that repeats
its section's name in its own heading is decoration that says nothing (§ "Tables over tile
walls"). The section already says Takeoffs; the heading only has to say which half of the
takeoff question this half answers.

### The divergence banner is one line, and it links

The watch-vs-phone banner sits under the key-metrics block, as it did, and it is now a
**one-line warning with a chevron**: the four-column table it used to unfold in place is on
`Details`. Tapping the banner selects `Details` and scrolls to the table. The dismiss X is unchanged
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
bestNm, alpha500`. **The ninth GP3S record, `bestHour`, is deliberately not among them** —
a one-hour window lights the whole track, so highlighting it says nothing — which is why
the picker has eight and the all-time speed table below has nine
(`RecordWindowSelection.catalogue`; `library.RECORD_KINDS` gives it `window_key = None`).
Default highlighted window: `best2s`. The picker: tapping a record
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

`Longest flight` (captioned `max N m in one flight` — `summary.maxFlightM`, the **furthest
any one flight went**, because six minutes downwind and six minutes of pumping in a lull are
not the same flight. Deliberately not the winning flight's *own* distance: the number never
was that, and until engine 0.13.0 the caption said it was) · `Most flights` ·
`Highest on-foil share` ·
`Most clean jibes` · `Best CPH` · `Best clean-jibe rate` · `Longest dry streak` · `Longest
flew streak` · `Longest session` · `Most distance`.

- **CPH is `jibesSuccessful / (timerTimeS / 3600)`** (engine ≥ 0.13.0) — clean jibes per
  hour of **timer** time: the hour the recorder was running, not the elapsed span it was
  running across, so a paused break does not quietly deflate the number a rider quotes.
  `durationS` is still what the row prints as the session's *duration*.
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

**The empty screen says why it is empty, and never blames a filter nobody set**
(15 September 2026, `ExampleOnlyNote`). The one-tap first run — install, *Try the example
session*, an analysed session two seconds later — used to end on Records reading *"No
qualifying speed window under this filter"* with no filter applied, and on Trends reading
*"Widen the range or clear the spot and gear filters"* on a library of one row whose range
and filters could not have helped: the example is excluded from both on purpose (the bullet
above; `LibraryStore.clause`), and no control on either screen reaches it. That exclusion was
written down for Apple's reviewer (`ios/store/appstore.md`) and for nobody else.

Both screens now branch three ways — **nothing at all** (import or sync a session), **only
the example** (`SessionStore.hasOnlyExampleSessions`, the clause restated on the in-memory
list), and **a filter that really is set**, which keeps the sentence it was written for. The
middle branch says the fact in the rider's words and ends on the step that changes it: *the
example session is on loan, not ridden, so it is kept out of your personal records on
purpose. Import a .fit file, or connect intervals.icu in Settings, and your own bests appear
here.* Its title is a promise rather than a fault — *Your records start with your first
session* — because nothing is broken and nothing is missing; the records have not been earned
yet. Trends says the same in its own terms, and neither title mentions a range.

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
Rates are additive (docs/algorithms.md, "Session rates"): TPH says how busy the afternoon
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
  `cleanJibesPerHour` and `wetPerHour` divide by since 0.13.0 (docs/algorithms.md, "Session
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
as integers (docs/algorithms.md, "The crossing, as an event"). One row because the two angles
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

The engine writes a **code** (`turn.outcomeReason`; docs/algorithms.md, "Why") and the words
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

**The aborted turn says nothing extra, on purpose** (engine 0.21.0, docs/algorithms.md, "The
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
carrying `flightEnds` (docs/algorithms.md, "Flight-end outcome"), and the map has drawn each
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
`UI_OPEN_FLIGHT_END=<index>`, which selects the Details tab first — a sheet attached to an
unselected tab's subtree never appears.

## One clock — every duration a rider sees is the engine's cleaned span

**A session's length is `summary.durationS`, everywhere it is printed.** That is the
engine's own cleaned elapsed span: last minus first *cleaned* sample, gaps included. It is
already the denominator of all four session rates and of average speed, and as of
7 Sep 2026 it is also the number every surface *shows*.

There were four clocks in circulation and three of them reached the rider:

| clock | what it is | where it used to be printed |
|---|---|---|
| **cleaned elapsed span** (`summary.durationS`) | the engine's own | the key-metrics block, the period block's hours |
| raw sample span | last − first *raw* sample, pre-clean | iOS `SessionRow.durationS`: the library row, the Distance card's caption, "Longest session", the widget, the week histogram, the gear rollup |
| FIT `total_elapsed_time` | the file's own field | the web session tile's "Duration", the web "Longest session", the week bar's tooltip |
| FIT `total_timer_time` | the file's own field | the web tile's "moving …" note — **still there, and correct**: that note is about the file's moving time |

They are not close. On the corpus's Rheinstetten afternoon the cleaned span is **7742 s**
and the raw one **10338 s** — 43 minutes — so the block said `2:09 h` while the tile eight
points below it said `2:52:18`, of a different clock, and the same rider's "Longest
session" record was a different number on the phone and on the web.

- **iOS** reads `SessionRow.rateSeconds` (`rateDurationS ?? durationS`, schema v12 — the
  column already existed for the period block). `durationS` stays exactly where it was: it
  is the dedupe key and the stored id, and neither may move.
- **The web** reads `summary.durationS` on the session page and `library._rate_duration_s`
  (`rateDurationS ?? durationS`) over stored digests.
- **Rate denominators are a separate question, and since engine 0.13.0 a separate clock.**
  The rule, in one line: **every displayed duration is T1 (the cleaned elapsed span), every
  rate denominator is timer time (T2, total minus pauses).** `foilPct`, `avgSpeedKmh` and all
  four per-hour rates divide by T2 (`docs/algorithms.md`, "Session rates"); everything in
  this section is about the other half, what is *displayed*.
- **A period obeys the same split**, which is what closed the last gap on 7 Sep 2026: the
  block's "hours on the water" sums T1 and its CPH and WPH divide by summed T2, so a month
  holding one afternoon prints that afternoon's own rate. Stored as `timerTimeS` on both
  sides — digest schema 9, GRDB v13 — because a rate a *library* computes has to reach the
  same denominator as the session page without re-reading the recording. The accessors are
  `library._timer_s` and `SessionRow.timerSeconds`, and their duration twins are
  `library._rate_duration_s` and `SessionRow.rateSeconds`; a call site picks by asking what
  the number is, not by which one is nearer.

**One duration formatter per platform**, the one this document already specifies —
`M:SS min` under an hour, `H:MM h` at or above one, rounded not truncated, unit inside the
value: `KeyMetrics.duration` (Swift, public for exactly this reason), `hm`
(web/js/cardstats.js), `library._f_clock` (period blocks), and `_hm` in
`verify_presentation.py` as the independent third spelling. `Fmt.duration` (`1 h 24 m`),
`hms()` (`h:mm:ss`) and `FlightPairing.clock` survive only for a **clip or a flight** clock,
which is minutes and seconds by design and is commented as such where it is used.

## Label table — one spelling per metric

The same number answered to five names across four surfaces. It has one now, and this is
the table. Where a name is a *record*'s, `design/tokens.json` is the machine-readable copy
and both platforms are checked against it (`PresentationTests.designTokensCarryTheSame
CataloguesAsTheCode` on iOS, `verify_presentation.py` §1 for the analyzer).

| metric | the spelling | notes |
|---|---|---|
| the speed records | **`Best 2 s`, `Best 10 s`, `Best 5×10 s`, `Best 100 m`, `Best 250 m`, `Best 500 m`, `Best 1 NM`, `Best hour`, `Alpha 500`** | tables, chips, the picker, the divergence banner |
| the same, *in a sentence* | the window without the prefix — "13.47 kn over 2 s" | `RecordKind.windowLabel`; a table stutters at "over Best 2 s" |
| the key-metrics block's row 2 | **`max 2 s`**, `5×10 s`, `alpha 500` | the one sanctioned divergence: a lowercase caption naming the *window*, not the record |
| the period block | lowercase captions (`best 2 s`, `on foil`, `hours on the water`) | the block's own caption voice, pinned by `fixtures/periods/periods.expected.json` |
| flying, as a duration | **`Foil time`** | minutes; the watch and FIT field 21 agree |
| flying, as a share | **`On foil`** | the percentage; the iOS card that showed a percentage under "Foil time" was renamed |
| the outcomes, as nouns | **`flew through`** · **`touchdown`** · **`fell in`** | `touched down` only inside a sentence; the compact tally keeps `flew · touchdown · fell` |
| the strict jibe verdict | **`clean`** / **`Clean jibes`** | see the spelling contract above |
| the score verdict | **`Speed kept`** | 20 Sep 2026. Printed on the watch, in FIT `turn_success_pct` and in Garmin Connect, and **nowhere on the phone**. `success` and `carried` stay internal |
| every fall of the session | **`Fell in`** / **`fell in`** | the flight-end channel, straight-line swims included — the row, the block, the card and the session-page card, one number |
| getting up | **`Takeoffs`** and **`Attempts`**, and **`Got up`** for the share | `Success rate` is retired; `Planing starts` is the windsurf lexicon's spelling of `Takeoffs` |
| the speed unit | **`kn`** / **`km/h`**, from Settings → Units | one formatter (`Speed`); the engine stays in knots |

**The glossary is held to this table too, since 15 September 2026.** `MetricGlossary` — and
therefore `docs/copy/glossary.json`, the welcome screen's four highlights and `/learn`'s
definition list — taught **`Foil %`** and a verdict list reading *"flew through, touched
down, or fell in"*. Both rows above had already decided otherwise, and every *screen* already
obeyed them: the shared source was the one surface still teaching the spelling the table
rules out, on the one screen where a stranger learns the word. The entries now say `On foil`
and `touchdown`; the participle stays where it belongs, inside a sentence
(`WelcomeGuide.lede`, both store descriptions, and each entry's own `sentence` field).

### The definitions round — 20 September 2026

Jan: *"the definitions of the numbers are important to clarify, make transparent, and
consistent across all surfaces."* A tester had read three numbers about one afternoon —
*Turn success 29 %* in Garmin Connect, *93 % flew through* on the website, 44 % on the
phone — and three more that did not agree with his memory. What changed:

1. **One glossary, one source.** `MetricGlossary` gained `places` (where a term shows),
   `labels` (every spelling a surface may print) and `fit` (the developer field behind it).
   `docs/copy/glossary.json` is its artefact; the app's *What the numbers mean* topic and
   `/help/#numbers` are both rendered from it, and `GlossaryLintTests` fails on a
   rider-facing metric label that is in no entry and on no allow-list.
2. **The score verdict is `Speed kept`** (see the label table above and docs/fit-schema.md's
   box on field 34). The phone's takeoff *success rate* became **`Got up`**, and the turn
   outcome stays **`Flew through`**. Three measurements, three words.
3. **Falls are the session's falls.** The library row offers a `fell in` cell
   (`RowMetric.falls`, from `wetExits`), the key-metrics block and the share card carry a
   `fell in` cell with the split in its caption, and the session page's card reads the
   flight-end channel on both halves so the caption adds up to the value. The turn tally is
   unchanged and its caption still says what its three counts are out of.
4. **Takeoffs and attempts are printed side by side** on the session page, each naming the
   other, because the watch counts attempts and the phone counted flights.
5. **Settings → Units** is on the phone as well as the browser. Every speed the phone prints
   goes through `Speed`; `SpeedUnitTests` scans for a second formatter. **The rule now covers
   every surface** (21 September 2026): the four Swift Charts axes convert their *series and
   their domain*, not only their label, so the ticks are round numbers in the unit on screen;
   the narrated and accessibility sentences, the records table and its margin column, the turn
   map's ramp legend, the share card, the home-screen widgets (the unit rides in
   `WidgetSnapshot.speedUnit`) and the Apple Watch app (the phone sends it as a
   WatchConnectivity application context) all read the picker. The only places allowed to
   spell a unit are the three formatters — `Speed`, and its two documented mirrors in the
   widget extension and the watch app, neither of which links the kit — plus the help prose
   that teaches the setting and the dev workbench, which reads the engine in the engine's
   units on purpose. `SpeedUnitTests.noSurfaceSpellsTheUnitItself` scans every Swift string
   literal on iOS and holds the list.
6. **Settings footers are one line each** (pattern K). Every `Section(footer:)` prints its
   `SettingsCopy.lead` and a row that opens the section's help topic. The seven-paragraph
   Notifications footer is `HelpTopicID.notifications`; the Analysis footer's rig paragraphs
   were already in `HelpTopicID.windsurf`, and its wind paragraphs in `.turnTypes` and
   `.windAxis`.

**Percentages: one rule.** A share prints **one decimal below 10 %, none at or above it,
always with a space before the sign** — `47 %`, `4.5 %`. The magnitude switch is for the
small numbers: a 0.4 % clean-jibe rate at no decimals is `0 %`, which reads as "none", and
one clean jibe in three hundred is not none; above ten points the decimal is noise and
costs a character in the narrowest cell on the row. The space is what every other unit in
both apps already gets (`2.6 km`, `13.47 kn`, `10:45 min`). One implementation per surface:
`Fmt.pct` and `PeriodBlock.percent` (iOS), `pct` / `pctDigits` in web/js/viz.js, and
`library._f_pct`.

**Distance is one decimal**, everywhere: `12.8 km`. The web session tile and the library
list printed two, eight points from a block printing one.

## Discipline lexicon — the same table, in the words of the rig (EXPERIMENTAL)

A windsurfer on a fin does not fly and has no foil to lose. Every word below is a word the
engine has no opinion about — the numbers, the verdicts and the map layers are identical, and
only their spelling changes — so the swap lives in presentation: `DisciplineLexicon` in the
kit, `web/js/lexicon.js` on the site, one table, and **the wingfoil column is the strings both
already printed, character for character**. `.wingfoil` is the default of every function that
takes a discipline, so a surface that has not been taught about disciplines is unmoved.

| wingfoil | windsurf (both presets) | where |
|---|---|---|
| `flying` | `planing` | map legend chip, track tint |
| `Foil time` / `foil time` | `Planing time` / `planing time` | the Foil card's caption, the divergence table |
| `On foil` / `on foil` | `Planing` / `planing` | the Foil card's title, the period block |
| `Takeoff` / `Takeoffs` | `Planing start` / `Planing starts` | the section tab, the attempt map and list |
| `lost the foil` | `stopped planing` | the outcome ladder, in a sentence |
| `off the foil` | `off the plane` | `TurnAnalytics.outcomeText`, the turn page's "why" line |
| `Foil` (the card) | `Planing` | the Ride tab's flight facts |
| `Flights` | `Planing runs` | the same card |

**Not translated, on purpose:** the whole turn vocabulary. *tack*, *jibe*, *flew through*,
*touchdown*, *fell in*, *clean*, *dry*, *wrist under* mean the same thing on either rig, and
"clean jibe" is the phrase this product is named after (see the spelling contract above).

**Pumping is absent, not zero.** On a windsurf preset the pump channel was never run
(docs/algorithms.md "Disciplines"), so the pump chips, the "pumps to takeoff" tile, the pump
strokes, the failed-attempt headline, the attempt filter, the stroke column and the whole "What
pumping cost" card are **not drawn**. A dash is a measurement that failed; nothing was
measured. The Takeoffs tab reduces to two tiles — how many planing starts, and how long the run
to planing took — and a list with no stroke column.

**The chip.** A windsurf session wears `windsurf · experimental` in amber beside the discipline
badge, on the session page and in the library row. Beside it and never instead of it: the badge
says what the *recording* is, the chip says how it is being read and that the reading is not one
anybody has checked yet.

**The badge.** `Wingfoil`, `Windsurf foil`, `Windsurf fin`, or the word the recording's own
`discipline` field used (`Kitefoil`). Three rungs, the engine's own (`SessionDisplay.badge`):
the rider's answer, then the recording's field, then the preset the import settled on. The
session page carries it always; **the library row carries it only when it says something**
(`DisciplineReview.showsBadge`) — with the switch below off, a library of one rig spelling
`Wingfoil` on every row is a column of noise, while the rows that disagree with it (a session
read as windsurf back when the controls were visible, a recording that names its own rig) keep
theirs. The FIT **sport code is no longer the fallback** — it was, and it is the one
piece of evidence that is systematically wrong here, so every `…-windsurfen…` afternoon in
Jan's corpus wore a `Windsurf` badge over a wingfoil session's numbers. The code still appears,
once, as a hint on the review row below, where it is shown as what a watch said rather than as
what the session is.

### Behind one switch — Settings → Analysis → "Windsurf (experimental)"

**Off on a fresh install** (Jan, 13 Sep 2026: *"windsurf should be hidden. Maybe enable with a
switch"*). One `UserDefaults` bool, `windsurfEnabled.v1`, exposed on the store
(`SessionStore.windsurfEnabled`) so the two kit-facing rules read the same flag —
`DisciplineReview.pending` and `…showsBadge` / `…showsGuessMark` — and its footer is the honest
version of *experimental*, in the order a rider needs it: "Analyse sessions as windsurf foil or
fin. Untested: jibes and tacks work, pumping is off, planing thresholds are provisional."

With it **off** the app is the wingfoil-only one it was before the preset existed: no "I mostly
ride" row (the rider default is wingfoil, whatever a stored value from earlier says, and the
Analysis footer drops the paragraph that explained it), no "Analyse as" card on the Details tab, no
review sheet after an import, no library banner, no `?` on any row, and no **Windsurf
(experimental)** topic on the Help index or in its search (`HelpCatalog.indexTopics` — the topic
stays *in* the catalogue, so a `?` on a windsurf session and any deep link still open it).
Imports are wingfoil and are written down as **confirmed** rather than as guesses
(`SessionIngestor.windsurfEnabled`); a recording that states its own discipline is still
believed, because that is the file talking and not a setting.

**It hides controls and nothing else.** A session already analysed as windsurf keeps its
preset, its numbers, its badge and its amber chip — switching the switch off is not the rider
saying that afternoon was a wingfoil afternoon, so nothing is re-derived in either direction.
Nor does turning it back on raise a review of everything imported meanwhile: those rows are
confirmed, and the rider who wants one of them read differently has "Analyse as" on the session
that matters. `UI_SHEET=discipline` turns the switch on before it imports the fixtures, because
the question is asked at import time.

### Where the override lives

**Session → Details → "Analyse as"** — with the switch above on — a three-way segmented control
(Wingfoil / Windsurf foil / Windsurf fin) under the Recording card, with the footnote:

> Experimental. Windsurf analysis is untested. Jibes and tacks work. Pumping is off and
> planing thresholds are provisional. Send feedback on what you see.

Details rather than Ride, and a row rather than a prominent control, because Jan's brief was to
*hide it a bit*: the rider looking for it will find it, and the rider who is not will never be
offered a choice he has no way to evaluate. Details is the tab about the *record* rather than the
riding, which is the question this row asks — not "what did you do", but "how should this be
read". Changing it re-derives **this session and nothing else** (docs/algorithms.md,
"Disciplines"); the anchor is `discipline`, and `UI_DISCIPLINE=windsurfFin` sets it for a
screenshot. Help: **Windsurf (experimental)**, under "Where the numbers come from" — on the
Help index only while the switch is on, and reachable from this card's `?` either way.

**The web has no override.** There is no per-session settings place on the session page to hang
one on, so a session is read in whatever preset its `discipline` developer field asked for —
`meta.analysedAs`, written by `web_entry.analyze_bytes`. Trends and Records are untouched:
windsurf sessions sit in the library like any other and there is no separate record set, which
the help topic says out loud.

### Confirming the discipline on import

**Wingfoil is not a sport anywhere but here.** Garmin, Strava, intervals.icu and Apple Health
have no code for it, so a recording can only arrive saying one of two things: the CleanJibe
watch app's `discipline` developer field, which is authoritative and is never asked about — or
nothing, dressed up as `windsurfing`, which is the profile ADR-004 files a wingfoil afternoon
under. So the import *states* a preset and then owns up to having guessed it.

**The rider default.** Settings → Analysis → **"I mostly ride"**, a three-way picker (Wingfoil
· Windsurf foil · Windsurf fin) above "Most of my turns are" — which rig, then which turn. It is
on the screen only while the windsurf switch is on (a picker with one answer is a row that takes
up space to say nothing), and with the switch off the default *is* wingfoil, whatever a value stored
while it was on says. It decides the preset for every imported session whose source does not say, and it changes nothing
at all on a wingfoiler's phone: wingfoil is what the resolver already fell back to. It applies
to **future imports only**, which the footer says out loud — declaring a habit is not a
statement about any particular afternoon, and silently re-reading two years of sessions off a
Settings row would be the app answering a question nobody asked.

**The review step**, and only with the switch on. After an import the rider asked for — files, a ZIP, Apple Health, a
pull-to-refresh sync, a Strava import — a sheet lists what just landed with an unconfirmed
preset: date · spot · source, the sport-code hint where there is one ("Filed as windsurfing.
A Garmin files a wingfoil session the same way."), and a three-way picker per row. Above
two rows it also offers **"All N as …"**, which is what makes a two-hundred-file ZIP one
decision. **Confirm** clears the question and re-derives nothing; **Not now** keeps every guess
— nothing is lost, and the session page can change any of them for ever.

*After* the import, not before it, and that is the opposite of the rider prompt next door: "whose
session is this" gates Records and Health and cannot be taken back, while this one is re-derived
from the archived recording the moment the preset moves. It is also the only order a bulk import
survives — a question per file would stop on the first one.

**Automatic pickups never raise it.** A Health auto-import, a Strava poll, an intervals.icu
pickup: the rider did not ask for those and may not have the app in his hand. They leave the
library's quiet banner instead — *"3 new sessions analysed as Wingfoil · Review"* — which names
what was already done rather than asking a question, and opens the same sheet when tapped. The
banner counts only sessions he has not skipped past; the `?` below outlives a skip, the banner
does not.

**Three badge states**, in the library row with the switch on: `Wingfoil` (confirmed, or stated
by the recording), `Wingfoil ?` (the preset came from the rider's default and nobody has said),
and the amber `windsurf · experimental` chip beside either where the preset is a windsurf one.
The `?` goes when he answers, whichever way he answers — agreeing is an answer. Its
accessibility label spells it out: "Analysed as Wingfoil, not confirmed". With the switch off
there is no `?` at all and no `Wingfoil` capsule — only a badge that disagrees with wingfoil is
drawn, and the chip stays wherever a windsurf preset is still in force.

Storage is one column, `session.disciplineGuessed` (schema v15), false on every row that
existed before the question was asked and on every row imported while the switch is off: a library imported under the old rule has been lived
with, and a banner offering to review two years of afternoons is a chore, not a confirmation.
`UI_SHEET=discipline` raises the sheet for a screenshot. Help: **Windsurf (experimental)**.

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
- **A date outside the current year prints its year.** `Sun 30 Aug, 14:07` for this season's
  afternoon; `Sat 11 Oct 2025, 15:23` for the one two seasons back. A weekday and a day-month
  are a complete answer for last week and a trap for 2025 — a library is full of both, and
  the row that lies about it is the one a rider scrolls past fastest (Jan, build 58). One
  rule, decided in one place (`Fmt.date`), so every surface that prints a session's clock
  obeys it without knowing: the **library row**, the **session page's date line**, the
  **feedback mail's facts**, the Health and Strava import lists, the discipline review, the
  re-add sheet, *Last sync* in Settings and *Last summary* on the watch page. The comparison
  is made in the *session's* own zone on both sides, so a session recorded at 00:40 on
  1 January in Auckland is a New Year's session on a phone in Munich. `Fmt.shortDate`
  (`30 Aug 2026` — records' "when · where", gear's *last used*, a spot's *last*) has always
  carried the year and is unchanged, and the widgets' `WidgetChrome.shortDate` has followed
  the same conditional-year rule all along.
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
- **Emphasis in rider copy is markdown, and it is drawn by a markdown-aware `Text`.**
  `**bold**` and `*italic*` are how every long footer and every help paragraph marks the
  word that carries the sentence — but SwiftUI parses markdown only in a
  `LocalizedStringKey`, which is to say only in a literal, and all of this copy is assembled
  at run time (a `+` chain, an interpolation, a paragraph out of `HelpCatalog`). Drawn with
  `Text(_: String)` it printed the asterisks, on eleven screens at once, until the release
  walkthrough of 14 September 2026 found them. One renderer now: `Text(markdown:)`
  (`ios/WingFoil/App/MarkdownText.swift`) parses with `AttributedString`,
  `.inlineOnlyPreservingWhitespace` — the interpretation that keeps the blank lines these
  footers are built from — and falls back to the string verbatim if the parser refuses, so a
  stray bracket costs the emphasis and never the sentence. Every help string goes through
  it, and `PresentationTests.everyHelpParagraphParsesAsMarkdown` holds the other end.

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

**What it is.** Settings → Tuning puts 27 of the docs/algorithms.md parameters on controls so
a threshold can be tried against a real library in a minute instead of an afternoon: turn
detection and scoring (`turnMinAngle`, `turnClassifyMinAngle`, `turnAxisBeforeDeg`,
`turnAxisAfterDeg`, `turnCleanQuietS`, `turnMaxDuration`,
`turnPeakRate`, `turnContinueRate`, `turnMinArc`, `turnMinRadius`, `entrySpeedWindow`,
`minSpeedLag`, `turnSuccessPct`), the stop ladder (`turnStopSpeedFloor`,
`turnTouchdownMaxStop`, `turnFallStop`, `turnOutcomeLookahead`, `turnRecoverPct`,
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
  set the flight rows read *default 20.0 km/h* and *default 15.0 km/h* (docs/algorithms.md,
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
the interesting part is the minute of swimming `turnOutcomeWindow` is measured over. The two
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

## The watch's event flash — every buzz also paints

Since Garmin app 0.9.11 (Jan, 15 September 2026: a buzz through a hood is easy to miss and
impossible to re-read) every on-water alert that vibrates also shows itself, in two parts:

- **The flash, 1.5 s.** The whole glass takes the event's ink with one glyph and one word in
  black on it, pulsing on frame parity like the PB flash: a resolved turn as *FLEW*, *TOUCH*
  or *FELL* with the outcome symbol the Turns page already draws, a clean jibe as *CLEAN* with
  the star, a dry-streak mark as the number and *DRY* (5, then every ten), a new longest
  flight as its duration and *LONGEST*. A pumped takeoff is a **ring** only — a thick circle
  inside the bezel for 0.7 s, the page left readable — because it is frequent. The speed PB
  keeps its own orange flash with the value.
- **The afterglow, 20 s.** A line at the top of whatever page is up keeps the last event:
  *JIBE · flew*, *TACK · touch*, *TURN · fell*, *CLEAN JIBE*, *10 DRY*, *LONGEST 2:14*. On the
  main page it is the top row itself, in the event's ink, where the clock and PAUSED live; on
  every other page it sits where the pause banner sits, black on the ink. A running flash and
  PAUSED both take precedence over it.

Colour and shape carry every event together, so it reads on the MIP palette and to a rider
who cannot tell the ladder's green from its red. The inks are the ladder's for the three
verdicts (the one place outside the Turns page allowed to borrow it: these *are* turn
outcomes), the clean-jibe ink for a clean jibe, the phase teal for a takeoff and a longest
flight (phase, not verdict), the ladder's green for a dry streak (a run of verdicts). Not
flashed on purpose: straight-line flight ends (the Timeline page shows them), interval
alerts and the wind lock.

One switch, *Show alerts on screen*, on by default; the per-alert switches gate the picture
exactly as they gate the buzz. The visual half is never debounced — a new event replaces the
one on screen, which is what one screen means — and save or discard clears the strip with
the session. `EventFlash.mc` is the module, `AlertManager` fires it beside each buzz.

## The watch's Tacks & jibes page

Jan, 21 September 2026, from a tester practising tacks. The Turns page says how the maneuvers
went — flew through, touched down, fell in, the streaks, the dots. Nothing on the watch said
**which maneuvers they were**, although the watch has counted tacks and jibes apart since the
first wind axis. Since 0.9.17 the standard set has an eighth page, straight after Turns, and
the large set has two more screens.

The page is two halves, jibes on top and tacks below. Each half is that kind's count as a
giant, the word under it, and beside the word how many of that kind he **flew through**, in
the outcome ladder's own green:

```
        wind ~NNE
           52
      jibes  flew 38
           41
      tacks  flew 29
```

Four decisions in that shape:

- **stacked, not side by side.** The pair band is the other available shape and was measured
  and rejected: two halves of one chord leave each count about 95 px on a 240 px glass, which
  steps both giants off the number ladder on exactly the watches the app was widened for. A
  count that is not a giant is the Turns page's tally row, which is one screen back. Stacked,
  each giant gets the whole chord at its own depth and the two halves straddle the equator.
- **the fly-throughs are the ladder's green**, because they *are* the ladder's green count
  asked of one kind: same numerator rule, narrower question. The count itself is white — a
  tally of maneuvers is not a verdict on them.
- **the header names the axis.** The split exists only where a wind axis does; without one
  every turn is a generic turn and both counts are 0. The page says *wind NNE*, marks an axis
  the watch estimated with a leading `~` exactly as the Turns header does, and says *wind not
  set* when there is none. Otherwise the page reads as broken on the session where it is
  merely uninformed.
- **aborted turns are on neither half.** A sweep the classifier rejects is a course change,
  not a maneuver, and the watch has no twin of the engine's aborted-turn count at all.

The row sheds *content* before size, like every other row on the Turns page: the word names
the half and stays, the *flew N* half is what a narrow chord gives up. And *flew 0* is never
drawn at all — the same never-a-flattering-zero rule the clean-jibe row keeps.

The counts come from `TurnDetector.tackCount` / `jibeCount`, which already ride the FIT
session; the fly-throughs are two new counters (`tackFlewCount`, `jibeFlewCount`) incremented
where the outcome resolves, because the kind is fixed when the sweep closes and the outcome
when the window resolves and `_resolve()` is the only place that knows both. They are **not**
backfilled by the auto-wind lock, exactly as `cleanJibeCount` is not: a pre-lock jibe becomes
a jibe but not a jibe he flew through. No new FIT field — the split the phone needs is the
tack and jibe counts, which have been in the file since 0.9.0.

## The watch's two page sets — standard, and large text

"I need my glasses" (Jan and a tester, 20 September 2026). The standard set packs four to six
numbers onto a screen, which is the right answer on a dry wrist and the wrong one at 25 kn
with spray on the glass. Since 0.9.16 there is a second set, and **one Garmin Connect enum
picks between them** — *Data screens: Standard / Large text* (`pageSet`). One setting, no new
property per page, and it is in **every stream**, which matters because the per-page editor
below is not (see docs/channels.md).

The large set is **seven screens, one number each** (five until 0.9.17):

| # | the number | the word under it | also on the page |
|---|---|---|---|
| 1 | live speed | `speed km/h` (or `kn`) | — |
| 2 | foil share | `on foil` | the foil-% bezel arc, earned the ordinary way |
| 3 | turns | `turns` | the outcome ladder as three coloured counts |
| 4 | jibes | `jibes` | `flew 38`, in the ladder's green |
| 5 | tacks | `tacks` | `flew 29`, in the ladder's green |
| 6 | time of day | `time` | — |
| 7 | best 2 s | `best 2s km/h` | — |

Three rules make it bigger rather than merely emptier:

- **the giant gets the whole stack.** A hero page spends a unit line and up to two sub-rows
  under its number, so the number sits above the equator and takes the chord at *that* depth.
  A large page has two rows, so the giant straddles the centre, where the chord is widest.
  The layout suite asserts the large giant is never *smaller* than the same value on a hero
  page, on any glass.
- **the word is FONT_LARGE, four rungs above every caption on the standard pages** (71 px of
  line against 37 on a fenix 8; 37 against 19 on a fenix 7S). A number nobody can name is not
  readable however big it is, so the word carries its unit too — this is the only place on
  the watch where a caption does. It steps down the ordinary ladder on a narrow chord and the
  suite asserts it never falls below FONT_SMALL, the readability floor.
- **no rings.** A flight ring costs 10–16 px of every radius, about 7 % of the digits on a
  240 px glass, and this set's whole trade is radius for digit height. Only the foil page
  keeps its arc, because the arc *is* the number the page already shows.

There is deliberately no map, no timeline and no table in the large set: a page you have to
read is not a page this set is for. And there is no editor for it — the seven pages are a
fixed table (`PageModel.buildLarge`) that reads no property at all, which is exactly what
lets it be the one page control every stream has. The two kind screens carry one line under
their word for the same reason the turns screen carries its tally: a count of jibes without a
verdict on them says nothing on its own.

**The text-size headroom of the standard pages was reviewed in the same round** and the answer
was to take no rung there (`standardPagesTextHeadroom` logs the measurement per glass). Every
pinned caption — the hero unit line, the records labels, the foil column headers and row keys
— *fits* a rung up in its chord on every glass, and *the stack* holds the taller line only on
the fenix 5 Plus family, whose number fonts carry no leading. Taking the rung would mean two
different page geometries per font set. The MAIN giant's inline unit/caption block cannot move
at all: on that same family it is already the taller box of its band, so a rung up reaches
into the clock row, which is the 0.9.13 bug exactly. The rung went to the large set instead,
where the page spends no rows on anything else and can afford it.

## The after-save pages and the live ones

A saved page and a live page showing the same number must be the same piece of code, or the
two start disagreeing about one session. The post-save review has eight pages since 0.9.17;
this is where each of them stands.

| after-save page | verdict | why |
|---|---|---|
| S1 **Verdict** (foil % + arc, SAVED pill) | **genuinely post-save** | it is the landing page and its subject is the session as a whole. The SAVED pill and the phone line live here and nowhere else |
| S2 **Speed** (best 2 s giant, 10 s and km under it) | **genuinely post-save** | the live Records page is the same two numbers, but the saved page also carries the session odometer, which has no other home once the Track page is conditional. A unification that drops a number is not a unification |
| S3 **Foil** | **unified, 0.9.16** | was a bespoke "Flights" hero (longest flight, its distance, the count). Every one of those numbers is on the live foil table already — `max` is that flight's two numbers under the two columns that name them — and the table says four more besides. The **flight count came back to the table's title row** (`foil · 31`) so the unification drops nothing; it is dropped rather than shrunk when the row cannot hold the pair, XTINY being already the bottom of the ladder |
| S4 **Turns** | **unified** (since 0.9.2) | `drawTurnsBody(dc, c, live=false)` — one flag, and it only changes the streak row, because "the run he is on" stopped meaning anything when he pressed save |
| S5 **Tacks & jibes** | **unified, born unified** (0.9.17) | `drawKindsBody`, with no flag at all: two counts and how many of each he flew through are the same four numbers before and after the save. Shown only when the session has a tack or a jibe to name — without a wind axis both counts are 0, and a page that would say 0 is not a page |
| S6 **Takeoffs** | **genuinely post-save** | no live twin exists; the watch has no takeoffs page on the water |
| S7 **Story** | **unified** (since 0.8.1) | the timeline, verbatim. `history` is complete and untouched by the save, and a coffee-in-hand read of the session arc is what it was always for |
| S8 **Track** | **unified** (since 0.9.2) | `TrackDraw`, the same renderer as the live map page, minus the position marker — the rider is ashore |

What is **not** unified, and deliberately: the SAVED pill does not ride the reused pages. S4,
S5, S7 and S8 look exactly like their live twins, and adding the eyebrow to them would mean
finding a free top arc on four pages whose top rows are already a header, a header, a caption
and a map — which is the 0.9.13 overprint waiting to happen on four pages instead of one. The
page-position dots along the bottom are what says "this is the review, not the water", and
they are on every one of the eight.

## The watch's per-page editor — and the switch that puts the pages back

**Dev stream only since 0.9.16** (docs/channels.md, "The watch"). The eight data screens are
configured in Garmin Connect (layout and five metric slots per page, `pg1Layout` … `pg8s5`),
and a stored property beats `properties.xml` on an installed watch: the defaults are written once at install, and an update never touches them. So a
rider who rearranged his pages and wants the shipped set back had two ways, both poor —
setting every row by hand, or reinstalling. Since 0.9.11 there is a third: **Reset pages to
defaults**, a switch in the app's settings that behaves like a button. Turned on and saved,
the watch consumes it in the settings callback (`AppSettings.consumeResetPages`), writes the
eight defaults back into its property store (`PageModel.restoreDefaults`, from the same
`DEF_LAYOUT` / `DEF_SLOTS` table `build()` falls back on), rebuilds the pages and turns the
switch off again, so the next sync shows it off. Every page key is written, off pages
included: the rider gets exactly the fresh-install set — Main, Foil, Records, Turns, Tacks &
jibes, Clock, Timeline, Map — and never a mixture. A dev watch that already carried the seven
older pages keeps them and picks up the new eighth key, so its map page arrives twice until
it takes the switch; a fresh install gets the shipped order straight away.

All of that is the dev build's. A release or beta watch has neither the Garmin Connect rows,
nor the strings behind them, nor the code that reads them: `PageModel._store` is a `(:notdev)`
twin that answers with the default table, and `AppSettings.consumeResetPages` a `(:notdev)`
false. Those builds therefore show exactly the eight pages the table holds — and their page control is the **page set** enum above, which is the
setting a rider asking for bigger text was actually looking for. Moving the editor up to beta
is one jungle line and one resource move; docs/channels.md names it as the candidate it is.

## The direct transfer's progress, on the glass (0.9.16, dev)

The recording crosses to the phone in 8 KB pages over about twenty seconds on the beach, and
until this round nothing on the watch said so. `DirectSend.statusLine()` is that sentence —
`phone 4/13` while pages are moving, `phone ok` when the stream is whole, and null when there
is nothing to say, which is what a release or beta build always gets.

It is drawn in two places, both in the eyebrow font and both in the dim ink, because it is a
machine's progress and not the rider's session:

- **on the SAVED screen**, under the pill. The pill and the line are a pair: with a line to
  show the pill lifts by one eyebrow line and the line takes the band it vacated, so the two
  together end exactly where the pill alone used to and nothing else on the page moves. Where
  even that does not fit, the line falls to the bottom band above the page dots; where neither
  holds it, it is dropped. It is never drawn over the verdict's digits — measured per glass
  (`phoneProgressLineNeverTouchesWhatMatters`): drawn at the top on fenix847mm and fenix7s,
  dropped on the fenix 5 Plus family, whose hero block starts 16 px higher than everyone
  else's and leaves neither slot free.
- **on the start screen**, in the air under the hint row, while pages from an *earlier*
  session are still waiting. `DirectSend.restore()` brings an unfinished stream back over an
  app exit, so a rider who walked away from the beach mid-transfer opens the app the next
  morning to the one screen that can tell him yesterday's session is still in the queue. The
  four-line stack is required to leave a quarter of the glass empty, so the line rides in the
  air rather than taking a fifth row — the mirror of where the brand mark rides above the
  title — and is dropped rather than clipped when its corner will not clear the glass.

And **one short buzz** when the stream is whole, on a channel of its own (`CH_PHONE`). It
lands while the rider is walking up the beach reading the SAVED screen, which is exactly when
nothing else is buzzing; a floor shared with the turn verdicts would have swallowed it on the
one session where the last jibe and the last page arrive inside the same five seconds. Behind
no toggle, like the auto-wind lock: the transfer itself is the switch, and a rider who turned
it on wants to know when he can walk away.

## The watch's words for a stranger (0.9.11)

The audit of 15 September 2026 walked the watch as a first-time rider and found four places
where the glass assumed knowledge it never gave. Fixed in 0.9.11-dev4, each as a string that
fits where it can and falls back where it cannot:

- **The Turns header says `flew · touch · fell`**, the names of the three counts under it, with
  the wind axis after them where the row has room at FONT_XTINY. It said `tack / jibe` — a
  leftover from a giant that once counted tacks and jibes — over the outcome ladder, so a
  stranger read 35 tacks and 12 jibes. The watch never draws the tack and jibe counts; the
  phone does.
- **The Main tally carries its words**: `35 flew · 12 touch · 4 fell`, the caption in
  FONT_XTINY after each count in the count's own ink, whenever the row can afford them on top
  of the separators and the verdict. They are the first thing dropped as a session gets wide
  (`tallyContent`), so a thirty-turn tally still reads as digits and never clips. Colour is a
  reinforcement now, not the only key.
- **BACK is named.** START toggles pause; BACK opens the session menu with Save. The start
  page's hint says `START records · BACK saves` where the row fits it (240 px glasses keep
  `START to record`), and the paused banner says `PAUSED · BACK saves` while that keeps the
  banner in the top third of the glass — the moment a rider who pressed START to finish is
  looking at exactly that word.
- **The summary says `NOT SAVED`**, in red and without the badge, when `Session.save()` returned
  false; it drew `SAVED` regardless until 0.9.11. **Discard asks once**, with the firmware's own
  yes/no dialog, and the session menu stays under it until the answer is yes.

## The watch link — Settings → Garmin watch

One section, and every row in it is a fact the rider can act on: which watch, whether it is
reachable, when a summary last came through, and the two things this phone can push to it.
There is no "connect" button, because there is nothing here to connect — Garmin Connect
Mobile owns the Bluetooth link and this app is a guest on it, so each state says what is
missing (`CompanionLinkState.headline` / `.detail`) rather than that something failed.

**Send wind to watch.** An eight-point compass, not a 0–359 field: nobody knows the wind to
the degree, the watch only uses it to decide which side of the axis a turn happened on, and a
wrong 12° costs nothing while a wrong 120° relabels every tack as a jibe. Manual by decision
(ADR-013).

**Send map to watch.** The watch cannot have a Garmin map — the firmware's own map view kills
the app on the fenix 8 (docs/watch-map-snapshot.md, GitHub #4) — so the phone draws one for
it: a coarse land/water/road mask of a 3 km box around a spot, a kilobyte or two, blitted
under the breadcrumb. The row names **the two maps it would send** — `Nago-Torbole ·
Fehmarn` — so the rider can see which ground is about to go over, and it opens the page that
chooses them.
Under it, the last result in one line: `sent 2.1 KB · 14:02`, or `Already on the watch ·
14:02`, or the failure in the rider's words. The button re-sends unconditionally and shows a
spinner while MapKit draws, which on a cold tile cache is a second or two; a row that said
nothing for that long would read as a row that did nothing. The push is also automatic — at
launch and after every import — and **silent**, because the answer is "nothing to change"
almost every time and a line that announces that on every launch is a line the rider learns
to stop reading. Nothing goes over the radio unless the mask's hash differs from the one this
watch last acknowledged.

**Map for the watch** — the page behind that row. Three sections of ticks, because two slots
is a fact about the watch and not a shape for a form: a rider who wants one map should not
have to fill a second picker with "none". **Automatic** holds one row, *Two most-ridden
spots*, ticked until he says otherwise — the rule that has always run, still the right answer
for a library with a home spot in it, and the thing a tap here goes back to. **Spots** lists
every spot in the library that has a coordinate, most-ridden first (the same order the
automatic rule picks in, so the row above and the list below tell one story), each with
`31 sessions` under the name. **Now** holds one row, *Where I am now*, with a location pin:
the phone's own position, for the afternoon at a lake the library has never seen and can
therefore never name. Its caption says what it costs — *Asks this phone for its position
once, each time a map is sent* — and ticking it asks straight away, so the permission sheet
lands under the finger that asked for it rather than surprising him mid-send; if location is
off, one footnote under the row says so (`Location is off for CleanJibe in iPhone Settings`)
and nothing else changes. The footer is the rule in the rider's words: *The watch holds two
maps. Pick up to two. A third replaces the oldest pick.* A third tick is never refused — a
picker that goes dead on the third row reads as broken — it drops the oldest pick, because
the one he just made is the one he is thinking about. The phone never tracks him: one fix on
a tap, one per send, never in the background, and the automatic launch pass never prompts
at all (docs/watch-map-snapshot.md).

**The card, on the session page, before the recording.** A summary the watch sent lands in
the library as a provisional row (ADR-013) with the blue line *From your watch — the
recording has not synced yet* under its title. Opening it is **not an error**: the page
shows the card's own numbers first — time on the session clock, foil %, flights, best 2 s,
the outcome tally and the distance, each read off the row the card filled and never printed
as zero where the card carried nothing — and then one block headed *From your watch* that
says how the rest arrives: pull down on Sessions once intervals.icu has the activity, or
share the `.fit` into CleanJibe, and the page fills with the map, every turn and the records.
The first card ever to reach Jan's phone (14 Sep 2026, build 50, a 20-second test with no
GPS fix) opened on *Could not open this session … the stored file is damaged*, which was the
archive being asked for a file it could not have. Share is disabled on that page; there is
no analysis to draw a card from yet.

## Not a session — the recording that was never an afternoon

Some recordings are not sessions: the rider presses start on the beach, walks to the water,
changes his mind, presses stop. Jan's library held thirteen of those on 14 September 2026 —
0:00–0:24 min, 0.0 km, 0 % on foil — and every one of them was inside "44 sessions", inside
the period and gear totals, and at the right-hand end of the Trends *on foil* line, which it
pulled to zero. The engine now says which is which (docs/algorithms.md, "Not a session":
no foil time **and** under 120 s or under 200 m). This is what the rider sees of that.

**Nothing is deleted, refused or hidden.** Not on import, not later, not ever. A recording is
the rider's; the app's job is to stop counting it, not to decide he should not have it. The
row is in the list, its page opens, its map draws, its own numbers are on its own page.

**The row carries four quiet words.** `No riding detected`, in the row's secondary colour, on
the line under the date — no capsule, no colour, no icon. It is a footnote and not a badge:
the badges on that row say what the session *is* (whose, which rig, from the watch), and this
says what the library is *not doing* with it. A provisional row does not get it: that row
already says "the recording has not synced yet" in blue, and one row does not need two ways
of saying "not yet".

**The page says why in one line**, directly under the key-metrics block, in the footnote size
and the secondary colour:

> No time on the foil, 0:24 long and 0 m covered — so this looks like a recording rather than
> a session. It is kept, and left out of totals, trends and records.

Three rules that line keeps. It **names the two numbers that decided**, so a rider whose real
session was mis-read can see the evidence and disagree with it rather than being told a
verdict. It says **kept**, because the first question a missing session raises is whether it
was thrown away. And it uses no engine vocabulary — not `isSession`, not `foilTimeS`, not
"success" or "carried". Distance under a kilometre is printed in metres: "0.0 km" is what put
the row on the screen, and saying it back is no answer.

A provisional row's version of the same line is about the recording, not the riding:

> Your watch says this afternoon happened, but its recording has not arrived yet — so it is
> not counted in totals, trends or records until it does.

**What excludes it, in one place per platform.** `LibraryStore.clause` on the phone —
alongside the example, the provisional row and a friend's session, the fourth of four — and
`counts_towards_records` on the web. Everything downstream inherits it: Trends and its week
histogram, the session and all-time records tables, every period and season block, the gear
totals, the spot's visit count, the "last session" and the week on the home-screen widget,
the clean-jibe personal bests, and the import screen's default gear.

**The count and the list are two different questions.** The list shows every recording; every
"N sessions" line counts the ones that are sessions (`LibraryListing.riddenCount`) — the
library footer, and each group header. A **provisional** row *is* counted there: the rider
counting his week does not care that the FIT is still in the air, and that row's
`no_recording` verdict is read past in this one place and nowhere else.

## Spots — how a place gets its name, and when it stops existing

A spot is a cluster of session start coordinates (`SpotClusterer`, 500 m). It is born nameless
— `Spot 1`, `Spot 7` — and gets a real one from a reverse geocoder.

**Naming is automatic, and runs wherever the set of spots can change.** Every import, sync,
restore, delete and re-cluster ends in the same library reload, and the naming pass hangs off
that, so a new place is named within a second or two of arriving. It used to run at launch
only, which is why a library synced from intervals.icu in one sitting showed "Spot 1 … Spot 7"
beside sessions that all said "Nago Torbole Wingfoil": the sessions were named from their
filenames, and nothing had asked the geocoder since before they existed.

**It retries when the network was not there.** A pass that resolved nothing schedules another
at 20 s, then 60 s, then 180 s, then stops and waits for the next launch, import, or the
rider's own tap. Three attempts because the failure this covers is a phone in a van in the
Alps, not an outage; stopping because a phone with no signal must not be asked sixty times.

**Only a placeholder is looked up.** The candidate set is "auto-named **and** still called
`Spot N`". `autoNamed` on its own means "the rider has not renamed this", which stays true
after a successful lookup — so asking on that flag alone re-geocoded every spot in the library
at every launch, which is a network round trip and one coordinate leaving the phone for an
answer already on the screen. **Look up names again** is offered only while at least one
placeholder is left.

**Re-clustering keeps every name somebody chose or looked up.** It rebuilds the table from the
sessions and re-matches each new centroid to the nearest old spot within the radius, carrying
that spot's id, name, creation date and `autoNamed` flag across. The test is
"is it still a placeholder", not "did the rider rename it" — the older rule discarded every
*geocoded* name on every re-cluster and put the numbers back on the screen. A named spot can
only be inherited once per rebuild; a second cluster that would claim it takes a placeholder
and is looked up like any new place.

**A spot with no sessions does not exist.** `session.spotId` carries no foreign key — on
purpose, so spots can be rebuilt without touching sessions — so the cascade is written down:
deleting a session and finishing a re-cluster each prune every spot no session points at, in
the same write. (An import cannot orphan one: a session is attached to its spot in the same
breath as the spot is created.) That is what "Spot 1 · 0 · Never sailed" was — a place left
behind by sessions the rider deleted — and migration v16 clears the ones already in a library.
After a re-cluster the count is exactly the number of places his sessions fall into, every
time, in any order, which is what makes 7 → 5 a result rather than a surprise.

**Placeholder numbers never repeat.** A new spot takes one past the highest `Spot N` in the
table, not `COUNT(*) + 1` — which minted a second "Spot 2" in any library where one spot had
been renamed and another removed.

## What leaves the phone — the privacy notes

The rule the app is built to and the privacy page states: the analysis runs on the device,
there is no account and no server of ours, and sessions are never uploaded. Every exception is
named, here and on the page, and the two say the same thing. Two of them are the rider's own
connections — **intervals.icu** and **Strava**, each only after he connects it, each carrying
his own credential to that one service. Two are Apple's **MapKit**: the map under a session,
and the coarse picture this phone renders for a Garmin watch. And one more, which the app
makes by itself:

> **Naming a sailing spot uses Apple's geocoder.** When CleanJibe finds a new place in your
> sessions it asks Apple's reverse-geocoding service what that place is called, so the spot
> reads "Nago-Torbole" instead of "Spot 3". What is sent is a single coordinate — the centre
> of that spot, rounded to about 110 m — and nothing else: no session, no track, no name, no
> identifier, and no account. It happens once per new spot, never for a spot that already has
> a name, and never at all if you name your spots yourself. Apple sees roughly where you sail,
> under Apple's own privacy policy.

The mechanics behind that sentence, so it stays true: it is `CLGeocoder.reverseGeocodeLocation`
(`SpotNamer`, in the kit) — Apple's framework, Apple's service, no third-party geocoder and no
HTTP client of ours anywhere in the project. The coordinate is rounded **before it is sent**
(`SpotNamer.roundedForLookup`, three decimal places), not merely on the way into a cache key,
because a privacy sentence that describes a rounding the code does not do is a false one. One
request per unnamed spot, at least 1.2 s apart, results cached. It needs no location
permission: the coordinate came out of a file the rider imported, not from the phone's own
GPS.

**This sentence is required wherever the network promise is made.** That is the privacy page
(`web/privacy/`, "The iPhone app — what leaves your phone"), and the App Store description's
privacy paragraph. Both currently name intervals.icu, Strava and Apple Maps; neither names the
geocoder, and until they do, both are incomplete.

## The first screen of a fresh install is "What CleanJibe does"

The welcome screen is the app's answer to the question a new rider actually has, and it is
owed to **every** install that has never had a session in it. Release candidate 58 opened on
the Sessions tab with the intervals.icu setup card instead — four steps and a key field in
front of somebody who had not been told what the app does — and the cause was the keychain:
iOS keeps keychain items across an app delete, so a reinstall gets the intervals.icu key
handed back before the first screen is drawn, and the rule counted a stored key as evidence
that this install had been welcomed already.

**Only a session is evidence** (`WelcomePrompt`, and its tests). A key says something
survived a delete; a session says the rider has been through the front door. So
`isAlreadyWelcomed(sessionCount:)` takes the library and nothing else, and both the silent
mark — the upgrade path, which stops a rider mid-season being greeted as a stranger — and the
decision to show the screen turn on it. `hasKey` is gone from all three functions. Everything
else about the screen is unchanged: it is shown at most once per install, the flag is written
the moment it goes up rather than when it is answered, another modal defers it rather than
cancelling it, and Menu → *What CleanJibe does* replays it without re-arming anything.

**One install can be owed it twice, and only one door does that**: Settings → Beta → *Start
over*, which writes `welcomeRequested.v1` after its wipe. A request beats both rules above —
see "Start over" — and the screen's own offers work from it exactly as on a first run, *Try
the example session* included: the example imports, and a rider who already owns that
recording lands on his own copy of it (`loadExampleSessionAndOpen`, which is unchanged and
never depended on the library being empty).

**The second offer is named for what it does** (15 September 2026). It read *"Connect your
Garmin"* and connected nothing: `onConnect` calls `dismissWelcome()` and that is the whole of
it, because on a genuine first run the four-step intervals.icu card is already the thing
underneath. A first-run button whose only visible effect is that the screen disappears reads
as a tap that failed. It is **`Set up intervals.icu`** now — the same name Settings and
`GettingStartedGuide.settingsIcu` give the same thing — and its detail keeps the *why*
(Garmin has no open API for a personal app) and adds the *what*: the screen closes, and the
4 steps are in Settings → intervals.icu, which the empty library's first row opens (reworded
on dev 70, when the steps left the first screen). The flow is unchanged and deliberately so: the excursion into
intervals.icu is intrinsic, honestly priced at *about five minutes, once*, and the
chicken-and-egg it used to cause is already solved by the first offer.

**And the empty library leads with the same two ways in.** When the library is empty and the
welcome has been dismissed, the Sessions tab shows one short row first: the welcome's own
headline, *Every flight, every jibe, every swim.*, and two buttons, **What CleanJibe does**
(the welcome screen again) and **Try the example session** (the same call the welcome's first
offer makes, so both doors land on the same session). Deliberately a row and not a second
card: the card under it is the thing to *do*, and this is the thing to read first. On a
genuine first launch the welcome cover is in front of it, so on that run it is simply what is
underneath.

### The ways in — the empty library's one card (dev 70)

Under that row sat the four-step intervals.icu card: the steps, the key field, the example
offer and two help links. It was the first screen of a first launch and it named **one** way
in. Jan, on dev 70: *"initial sessions page mentions icu but not Strava"*, and *"better refer
to Settings than repeat the setup"*. A rider who owns a Suunto, a Strava account or a single
FIT file read four steps about a service he does not use, and the one screen in the app that
should say *there are four ways in* said *there is one, and here it is in full*.

It is **one row per way in** now (`LibraryView.waysInCard`), under the heading *How your
sessions get in*. Each row is an icon, the action, and one line of at most twelve words:

| row | line under it | where it goes | channel |
|---|---|---|---|
| **Set up intervals.icu in Settings** | Garmin has no open API. intervals.icu is the bridge. | Settings | release |
| **Record on your Apple Watch** `BETA` | The session comes to the phone by itself. | the help topic *Recording with the CleanJibe Apple Watch app* | beta |
| **Set up Strava in Settings** | Strava hands over positions. Records are uncertified. | Settings | release, and only where the build carries Strava keys |
| **Import a file** | A FIT from any watch. AirDrop and Files work. | the file picker, `ImportView.importableTypes` | release |

Five rules hold that table together.

* **The order is the order a rider meets a watch**, Apple straight after Garmin. They are the
  same doors `GettingStartedGuide.routes` carries — `garmin`, `appleWatchApp`, `strava`,
  `fit` — so the empty state, the Getting started topic and `/start` name the same four. The
  generated guide is reordered from the web side, so nothing in the app reads that array by
  position: the rows are declared here, and the route ids are the seam.
* **The rows name the action, the routes name the door.** This is a list of things to *do*;
  the guide is a list of things to read. *Set up intervals.icu in Settings* and
  *Any watch that writes a .fit* are the same door said to two different readers.
* **Two rows end in Settings and say so in the label** (*Import does, Settings configures*,
  build 63). The sheet opens on intervals.icu and Strava, the form's first two sections, so
  there is no anchor to scroll to and nothing to miss. Both take the one action the library
  already hands down, `openIcuSettings` — the same door Import's `SetUpInSettingsRow` and
  Help's *Open CleanJibe Settings* use.
* **A build with no Strava keys shows no Strava row.** Settings would answer it with
  *"Not available in this build"*, and the first screen a rider meets does not offer a door
  onto that sentence — the same rule the filter menu keeps.
* **The Strava row is not called "Connect Strava".** Strava's guidelines reserve the connect
  action for their own button artwork and their own wording, *Connect with Strava*
  (`StravaBrand`, rule 1), and that button lives in Settings → Strava. This row is the way to
  it, so it is named the way the intervals.icu row above it is.

**The four steps have one home**, and it is Settings → intervals.icu: the caption, the key
field, *Get a key in 4 steps* and *Sync not working?*. `IcuSetupGuide` is still the one source
both the Settings rows and the help topic render — nothing was deleted from Settings, and the
first screen simply stopped repeating it. The intervals.icu **problem banner** came with the
card rather than with the steps: a key that has been typed and refused is the one thing a list
of doors cannot say for itself, so `.problem` still prints the cause, the fix and *What to
check* above the rows.

## Gear & spots — one page of named things

A spot is the same kind of object as a wing: a named thing sessions reference, and a
top-level filter chip on both Records and Trends. The tab that owns the rider's named things
therefore owns both, **on one page** (Jan, build 58). Spots arrived here from four levels
down the Settings sheet as a row that pushed a sub-page of their own, which is one tap to
find out there is nothing to find out; they are now the first section of the same list, in
the three gear groups' own shape:

- **header** — an icon and a name, like *Wing* / *Board* / *Foil*;
- **one row per spot** — the name, a ✨ where the map named it rather than the rider, a
  chevron, and underneath the same caption figures a gear row carries: `12 sessions`,
  `last 30 Aug 2025`. Tapping a row renames it, in an alert with a field in it, because a
  rename is one short string and not a screen. The coordinates that the old sub-page printed
  are gone: a centroid to four decimal places is a fact about the clusterer, not about the
  place;
- **the section's own actions at its foot**, where every gear group keeps *Add wing*:
  **Re-cluster spots** and **Look up names again**;
- **the footer** — tap to rename, a typed name survives a re-cluster, sessions within the
  cluster radius are one spot, names come from the map when the network allows.

**A spot with no sessions is not listed.** Clustering can leave one behind — a session
deleted, a re-cluster that moved its afternoons into a neighbour — and an empty spot is a
name with nothing under it that still turns up in every spot filter. The count is the whole
of the evidence, so the count is the whole of the filter, on this page and in the *Manage
spots…* sheet the Records and Trends spot chip still opens (`SpotsView`, which is now reached
from there and nowhere else).

**The tab is called "Gear & spots".** It said *Gear*, because four labels share a 390 pt bar
— but spots are half of what is behind it, and a rider looking for the place his spots are
named has no reason to open a tab called Gear. The bar scales the label; the name tells the
truth, and it is the screen's own title as well.

## Session list — group by, and the filters that narrow it

A library is a list of afternoons until it is about forty of them, at which point the
questions a rider brings to it stop being "what did I do on Saturday" and start being about
*sets*: how many afternoons in August, everything at Torbole, what came in from Strava.
Flat and newest-first, the list answered those by scrolling. Two controls answer them
instead — **group by** at the top of the list, and one **filter** menu in the toolbar — and
both live only on the Sessions tab.

**Group by: All · Month · Year · Spot.** A segmented control at the top of the list,
because there are four fixed answers and the one in force is worth seeing without opening
anything. The first segment is **All** and not "None" (Jan, 14 Sep 2026): beside Month and
Year it names the whole library in one piece, where "None" read as nothing being shown. The
value behind it is still `none` — that is what `library.groupBy.v1` holds on every phone
already, and what `UI_GROUP_BY` takes. Groups are list sections, **newest group first**,
sessions inside a group newest first like the flat list they came from, and the header
carries the count: `August 2026 · 9 sessions`, `2025 · 41 sessions`,
`Nago-Torbole · 31 sessions`. Month names are written out in full and in en-GB, the same
table the period headings use ("Formatter rules"), so one month reads the same on both
screens.

Under **Spot**, sessions with no spot — and sessions whose spot the table can no longer name,
which is the same thing as far as a heading goes — fall into a last group called **No spot**.
Last whatever its dates say: it is not a place, so it has no place in the sequence.

The default is **Month from twenty sessions up, All below**, counted over the *unfiltered*
library. A library of nine is a screen and headings on it are furniture; a library of two
hundred is already being scrolled by month. The count is the whole library on purpose: the
default is a fact about how much the rider has, not about what a chip is showing him this
second, and a list that ungrouped itself because a filter narrowed it to nineteen would be
answering a different question at every tap. Once he moves the control the choice is
remembered (`library.groupBy.v1`), because "I read my library by month" is a fact about the
rider; the *filter* is not remembered, because a narrowing is a question and not a setting.

**The filter menu** is one toolbar menu next to Import, with four sections and a single
choice in each:

| section | entries |
|---|---|
| Spot | **All spots**, then every spot in the library |
| Source | **All sources**, then the doors this library actually holds — intervals.icu, File, Garmin export, AirDrop, Garmin watch, Apple Watch, Apple Health, Strava, Example |
| Discipline | **All**, Wingfoil, Windsurf foil, Windsurf fin — shown only with the windsurf switch on |
| Date | **All time**, This year, Last year, Custom range… |

A door that brought nothing in is not offered: a filter that can only ever empty the list is
not a filter, it is a trap. The demo doors (the bundled example, the repo's fixtures) are
hidden until the library holds such a row and are then called **Example** — "fixtures" is a
thing this repository has, not a thing the rider imported. **Source is containment, never
equality**: `session.importSource` is a `+`-joined set (`file+icu` once the same afternoon has
arrived twice), so a session that came in both ways answers to both doors — and `watch` never
matches `applewatch`, which is a Garmin summary card being mistaken for an Apple Watch
recording. Discipline reads the preset the session is *analysed* under, the rider's override
first and the recording's own tag second, so the menu agrees with the chip on the row.

Dates are read on **each session's own clock** where it recorded one: an evening session
either side of midnight belongs to the month the rider had, not to the month the reader's
phone is in. The two ends of a custom range are the other way round — they are days picked
off the reader's own calendar — and they are **inclusive at day granularity**, with the
Periods screen's own sentence under them: *Both dates count.*

**The chips say what is on without being opened.** When any filter is active a row of
capsules sits under the title, above the group-by control, one per narrowing, in menu
order: `Nago-Torbole ×`, `Strava ×`, `2025 ×`, `12 Jul – 3 Aug ×`. Tapping a chip clears
that one; from two chips up a plain **Clear all** sits at the end. A whole calendar year is
chipped as the year, because there is no second way to have picked 1 January to 31 December.
The failure this row exists to prevent is a list quietly three sessions long because a chip
was left on last week.

The footer counts what is shown against what there is — `3 of 41 sessions · pull to sync
intervals.icu` — and a filter that matches nothing gets its own empty state, **"No session
matches these filters"** with a **Clear filters** button. Not the fresh-library card: telling
a rider with forty sessions that he has none is the app being wrong about him.

**Records, Trends, Periods, the gear rollups and the widget keep reading the whole library**
(docs/decisions.md ADR-025). The filter is a view of one list. A chip that hides half the
list must never be able to hide half a personal best — "best 2 s: 24.1 kn" that quietly meant
"…at this spot, this year" is a number the rider would go on quoting long after the chip was
forgotten. Those screens have their own spot and gear pickers, which say so on the screen
they narrow.

iOS: `LibraryListing.swift` in the kit (`LibraryListFilter`, `LibraryGrouping`,
`LibraryGroup`, `LibraryDateWindow`), pinned by `LibraryListingTests`; the list itself is
`LibraryView`, the menu and the chips `LibraryFilterMenu.swift`. Not on the web session
viewer, which has no library to group.

### The row's three numbers, and the words under them

A row carried `37 % · 3 · 13.25 kn` under three glyphs and `4 · 1 · 0 · 2.1 km` under none.
Jan read the middle glyph — a turning arrow — as his jibes, and it was drawing the **flight**
count (Beta 75; pattern H, docs/review-checklist.md). A number a reader has to decode is a
number the row is not carrying, and a glyph is a guess until it has been read once with its
word beside it.

So **every number on a row has its word within reach**. The three metric cells put the word
directly under the value in caption type, which is how the watch draws the same three facts,
and the outcome tally spells itself out: `4 flew · 1 touch · 0 fell`, each word in its own
number's ink. The key-metrics block is unchanged — its three counts already stand under a
caption that says what they are out of.

And **which three is the rider's**: Settings → Session list → *Row shows*, three pickers in
the order the row draws them. The options are `RowMetric` in the kit — foil, flights, jibes,
clean, turns, best 2 s, best 10 s, distance, time, dry streak — and each case owns its word,
its glyph and how its value is spelled, so the picker, the row and the session page cannot
drift apart. The default triple is **foil · jibes · best 2 s**: what the list always drew,
with the middle cell corrected to the jibes its glyph always promised. The choice is one
stored string (`sessionRowMetrics`), and a slot that cannot be read falls back to the default
rather than leaving the row a cell short (`RowMetricTests`).

## The session page: source, name, neighbours

The header names where the recording came from in one line under the date
(`SessionProvenance.line(importSource:)`: *Apple Watch · CleanJibe*, *intervals.icu*, *Strava*,
*Apple Health*, *File*) — provenance used to live on the Details tab only, so an Apple Watch
recording and a Health import looked alike. The title is a button: a tap opens a rename sheet
writing the same `customTitle` the share composer's field writes, so renaming is not a
side-effect of sharing. A swipe moves to the next or previous session in the list's own order
(`SessionStore.visibleSessionIDs`), with a greyed ‹ › pair beside the date at the ends; the
drag needs a horizontal intent (dx over 2.5 × dy) so the inline map keeps its pan.

**The finger drags the content**: a drag left takes the page left and brings in the *next*
session in the list's order, a drag right walks back to the previous one — the platform's
rule, and a sign that is read right and written backwards, so it is `SessionPaging` in the
kit with `SessionPagingTests` on it rather than a ternary in a gesture closure. The page
**slides** rather than swapping (Jan, Beta 75): it follows the finger while the drag is on
the glass (`SessionPaging.follow`, rubber-banded, and barely moving at the ends of the list
where there is nothing to turn to), then the outgoing page leaves by the edge it was pushed
towards while the incoming one arrives from the other. The ‹ › pair runs the same animation —
both go through one `turn(_:)`. A short flick counts when it was thrown hard enough
(`predictedEndTranslation`), the way a paged scroll view reads one.

The library row's track outline can sit on a map: Settings → Session list → *Map behind the
track in the list*, off by default, an `MKMapSnapshotter` image per session cached beside the
thumbnail and rebuilt with it. The snapshot is a picture of **the square the outline is drawn
in** — the tile's shorter side less one inset on both edges — widened to the tile's own shape
and centred on the track's bounding box (`TrackTileRegion`, pinned by `TrackTileRegionTests`).
There is one inset constant (`ListMapBackdrop.inset`) and the row hands it to the outline
view: it was two numbers, so the map was computed for a 40 pt square under a line drawn in a
34 pt one, and the track sat off towards an edge of a map of somewhere slightly else. The app-wide menu (What CleanJibe does · Getting started ·
Settings · Help · Support & ideas) is one `AppMenuButton` on all four tab roots (pattern M).

## Import — the doors a session comes in by

The Import sheet is a list of doors in **one order, the getting-started order** (pattern J,
docs/review-checklist.md): intervals.icu, the Apple Watch app, Apple's Workout app, a file,
Strava, and the Garmin GDPR ZIP **last** — `ImportDoor.ordered(channel:)` in the kit, asserted
against `GettingStartedGuide.routes` per channel. Every door is always drawn (pattern E/G): a
Strava section without keys, a Health section before the first import, a sync row without a
key all keep their row and change only their label and footer. Each footer says **what the
door brings in, in one line** (pattern K, at most 25 words) with the recording class above it
and a link to the help topic below; the *how* lives in the topic, not in the footer.

Until 18 September 2026 the order was the ZIP first, the Strava and Health doors appeared only
once used, and the footers explained the mechanism in four paragraphs. The three rules above
replaced all of that at once; the doors' wording is `ImportDoor.footer(channel:)` and nowhere
else, and Import → Apple Health carries the Apple Watch door's own sentence so a rider who
recorded on the watch is told her session arrives by itself rather than left to look for it.

### Import does, Settings configures

**Every row on this screen is an action** (Jan, build 63). It was not: *Sync intervals.icu*
sat there greyed out on a phone with no key, saying nothing about why, and the Strava section
carried a *Connected as …* line, which is an answer about an account and not a door. A screen
that both imports and sets up is two screens sharing a scroll, and the rider who taps the
disabled row learns nothing at all.

So the split is by verb. Import holds the four doors and nothing else — the file picker
(*FIT, GPX, TCX or ZIP…*, *FIT or ZIP…* in the release), **Sync intervals.icu**, **Import from
Strava…**, **Import from Health…** (beta), with the Garmin ZIP above them (beta). Settings
holds the two accounts: the intervals.icu key with *Save & check*, the last sync date and the
two help rows; Strava's *Connect with Strava*, who you are connected as, and *Disconnect*.

**A source that is not set up replaces its action with one line**, not with a disabled button
and an explanation under it: **Set up in Settings → intervals.icu** and **Set up in
Settings → Strava** (`SetUpInSettingsRow`), in the app's own path notation, and tapping one
*goes* there — the library owns the single sheet both screens are (`LibrarySheet`), so
Settings replaces Import rather than stacking on it, through the same `openIcuSettings`
action the help topics' *Open CleanJibe Settings* uses. There is no anchor to scroll to: the
sheet opens at the top and intervals.icu and Strava are its first two sections. A build with
no Strava keys says *"Not available in this build"* in both places, in the same words.

**And the footers stay on their own side of the split.** Import's say what the door brings in
— the recording class, then the prose (`ImportClass`) — and Settings' say what the account is
for (`GettingStartedGuide.settingsIcu` / `settingsStrava` as the section's first line, the
detail underneath). One string moved with the buttons: the Strava footer opened on *"Connect
your Strava account and import the sessions you pick…"* and now opens on *"Imports the
sessions you pick from your Strava account…"*, because the connecting is no longer on the
screen the sentence is printed on. Nothing else in it changed. **"Sync now" is gone from
Settings** for the same reason: fetching sessions is an import, and Import's *Sync
intervals.icu* and a pull on the Sessions list are the two doors onto that one call. There
was a third, *Sync now* on the first-run setup card, and it went with the card on dev 70.

### The recording class opens every footer

Every section footer now **begins with the class the door brings in**, in the names
docs/channels.md settled on and cleanjibe.org prints (`RecordingClass` in the kit, one source
for the app, the help catalogue and the website):

| name | the door that brings it | one line on what you get |
|---|---|---|
| **Class A · Garmin watch app** | Full history, Single sessions | everything, the wrist included |
| **Class B · any speed-certified file** | Full history, Single sessions, Apple Health | everything except pump strokes and takeoff attempts; speed records certify |
| **Class B+ · Apple Watch app** | *no import at all* — named in the Apple Health footer, because that is where an Apple Watch owner is standing | everything class B gets, plus the wrist at 50 Hz |
| **Class C · positions only** | Strava; the picker's GPX and TCX in the beta | the analysis, with speed records estimated from positions and marked uncertified |

The letters were kept out of the copy for months, deliberately — "class b" names a bucket in
somebody else's taxonomy and answers nothing a rider asked. What changed on 14 September 2026
is that the question moved *in front of* the import: cleanjibe.org and /watches print the table
as "what you need, what you get", so a rider arrives at this screen looking for the row he has
already read. The rule that replaced the old one is that **the letter is never alone** — it is
always the letter and the thing, "Class A · Garmin watch app", which reads as a label to
somebody who has seen the table and as a plain description to somebody who has not. A bare
lower-case "class b" is still forbidden, and `PresentationTests` still asserts it.

The **Single sessions** footer names the classes its picker can actually open: A, B and C in
the beta, A and B in the release, which has no GPX or TCX door (docs/channels.md). The help
topic *What your recording can and cannot show* carries the same four, in the same words.

**The release footer names no beta.** It used to close on *"Their own GPX and TCX files are
read by the CleanJibe beta"*, which answers a Polar owner's question with a build he does not
have; since 14 September 2026 it closes on the two doors this binary actually has — *"Polar,
Suunto and COROS sessions come in through Strava, or through intervals.icu"*. The beta's own
footer is unchanged: there the picker really does open the file.

### Import from Strava

Strava is the second cloud source (docs/decisions.md ADR-023), and the one that reaches a rider
with no Garmin account and no intention of setting up intervals.icu. Its section is **under**
intervals.icu, deliberately: for the same afternoon intervals.icu hands over the original file
off the watch and Strava hands over positions, and the footer says so in one sentence — *if the
same session is on intervals.icu, take it from there instead.*

* **Connect with Strava / Disconnect** — **Settings → Strava**, and only there since build
  63 ("Import does, Settings configures", above): Import's Strava section shows *Import from
  Strava…* once an account is connected and one line back to Settings while it is not.
  Connecting opens Strava's own consent screen; CleanJibe only ever **reads**, and the words
  say so on both screens. A build with no API keys behind it shows *"No Strava application
  configured"* and where the keys go — a Connect button that always fails would be worse than
  no button. (`StravaImportView` still carries its own connect and unconfigured states, which
  are now the fallbacks of a screen reached with a connection in hand.)
* **The list**: the matching activities of the last two years, newest first, each one marked
  *In your library* where the ±60 s key or the remembered Strava id already knows it. Tap to
  pick, or **Import all new**. Once one session has arrived this way the automatic-pickup
  toggle appears, exactly as it does for Apple Health and for the same reason: a toggle for a
  source the rider has never used is a question about nothing.
* **Which activities** — Strava has no wingfoil type, so the rider picks the set once
  (Windsurf, Kitesurf, Surf, Workout on; Sail and Stand-up paddling off, because for most
  people those buckets hold boats and flat water). Whatever is picked, an activity whose *name*
  says wing, foil, kite, surf or SUP is offered too.
* **Both ceilings are said out loud, and neither says the app is unfinished** (reworded
  14 September 2026). Strava answers **two hundred** requests every fifteen minutes — the real
  number, in the same words on the Import screen and in the help topic, which used to disagree
  with each other — and a run that hits it stops and reports *"Strava asked us to wait"* rather
  than retrying into the quota. The rider ceiling is its own sentence too, but a neutral one:
  *"Strava lets a new app connect a limited number of riders. If connecting is refused because
  CleanJibe is full … Menu → Support & ideas is the way to say so, and Strava is asked for
  more."* It used to read *"Strava has not reviewed CleanJibe yet"*, which tells an App Store
  rider that the app in his hand is waiting for permission to exist. A server error is neutral
  in the other direction as well: *"Strava answered with an error (HTTP 502)"*, never the
  response body, which can echo a request — and a token — straight back at the screen.
* **Strava's brand, used Strava's way** (developers.strava.com/guidelines, read 14 September
  2026; `ios/WingFoil/Features/Import/StravaBrand.swift`). Three rules, and breaking one can
  cost the application and with it a whole import door: (1) the connect action is **Strava's
  own button artwork**, unaltered and unrecoloured — the orange PNGs at 1× and 2× out of
  `1.1-Connect-with-Strava-Buttons.zip`, in the asset catalogue under `Strava/`, 48 pt tall,
  wearing Strava's wording *"Connect with Strava"* and not ours; (2) **attribution wherever
  Strava data is shown** — the *Compatible with Strava* logo sits in the Import screen's Strava
  section header, **beside** the section's own name and never above the CleanJibe mark, because
  the guideline is that Strava's logo may not be given more prominence than the app's own;
  (3) **a link back** — *View on Strava* on a Strava-imported session's Details tab, under the
  Recording card, in Strava orange `#FC5200`. The activity id it needs is read back out of the
  recording's own filename (`StravaImport.activityId`, the first field of
  `<id>_<slug>_strava.gpx`) rather than stored in a column of its own: the fact is already on
  the row, and a migration to duplicate it would backfill from this same string. A build whose
  asset catalogue has lost the artwork falls back to the same spec drawn by hand — `#FC5200`,
  white text, 48 pt — and never to a label of our own spelling.
* **Class (c), and the mark that follows from it.** A Strava session is positions-only, so
  every speed record it produces wears the `uncertified` chip and the session badge names both
  absences. Nothing about that is special-cased: the mapper writes a GPX, and the rest of the
  app has never known the word Strava.

### Share from the vendor app straight into CleanJibe

The door for a rider whose watch is not a Garmin and not an Apple Watch. Every vendor's phone
app can export a recording as a file, and CleanJibe declares the UTIs for all three of them
(`ios/project.yml`: `de.lahmann.wingfoil.fit`, `.gpx`, `.tcx`, all `CFBundleDocumentTypes`), so
**Open in CleanJibe** appears in the iOS share sheet wherever one of them is offered. Save to
Files and sharing from there is the same path with one more step, and it is the fallback the
help names for the case where the app row is short.

One rule covers the choice of format: **take the FIT.** A FIT carries the receiver's own speed
and certifies; a GPX or a TCX carries positions and does not. Everything else — foil time,
flights, turns, the map, the wind axis — is identical either way.

The paths below are the help topic *Share from your watch app straight into CleanJibe*
(`HelpCatalog.shareFromWatchApp`), verified against the vendors' own current help pages on
**13 September 2026**. The date is a **comment over the items** in the catalogue rather than
part of what a rider reads (Jan, dev 70): a term that read *"Suunto, verified 13 Sep 2026"* is
a fact about the author printed where the reader is scanning for his own watch. The term is
the brand alone now — **Garmin, Suunto, COROS, Polar** — Garmin first because it is the
popular watch and the one answer nobody expects, and each caveat opens its own detail:
*"No phone export. On a computer: …"*, *"Not on the phone. On flow.polar.com: …"*. Anything
that could not be confirmed is still labelled unverified rather than dressed up:

| app | path | formats | verified |
|---|---|---|---|
| Suunto | Calendar → the workout → ⋯ top right → FIT | FIT, GPX (Workout), GPX (Route) | ✅ 13 Sep 2026 |
| COROS | Activities → the activity → ⋯ top right → Export → FIT | FIT, GPX (TCX/KML unverified) | ✅ 13 Sep 2026 |
| Polar | **not on the phone.** flow.polar.com → Diary → the session → Export → FIT | FIT, TCX, GPX, CSV | ✅ 13 Sep 2026 (web only; mobile Safari unverified) |
| Garmin | **no phone export at all.** connect.garmin.com on a computer → the activity → gear → Export File | original FIT (plus TCX, GPX, KML) | ✅ 13 Sep 2026 |

Garmin is the row that matters most, because it is the popular watch and the answer is "you
cannot do it from the phone": every export path Garmin documents begins with signing in to
connect.garmin.com in a browser. So the topic sends Garmin owners to the two doors that do work
without a computer — intervals.icu, or the CleanJibe watch app — and names the computer path
for completeness, with the current menu wording (**Export File**; the label read *Export
Original* until Garmin renamed it, and the Import screen's own footer still says the old words
where it describes that page).

### No watch at all — recording with a phone

The topic beside the vendor one (`HelpCatalog.phoneOnly`, *Recording with a phone only*), for
the rider who owns none of the three things this app has a door for. It answers the question
the vendor topic cannot: how the track gets recorded in the first place.

**It names no other platform and no other app, since 14 September 2026.** It used to list five
trackers by name, three of them Android ones — which App Store guideline 2.3.10 does not allow
an iOS app to do, and which the release walkthrough caught. The answer is the *kind* of app and
the file it writes: **any GPS-logging app on your phone that writes a .fit or a .gpx**. The one
name that stays is **Strava**, because it is a door in this app rather than a recommendation —
Strava's phone app cannot export a recording as a file, so connecting *is* the export, and it
is the one path that works in every channel. The file route is written in terms of the format
rather than the channel: CleanJibe reads a `.fit` everywhere, `.gpx` and `.tcx` open in the
public beta, and the sentence names Strava and intervals.icu as the route that works today —
because a release reader must not be told that the answer to his question is a build he does
not have. It says where the phone goes — a waterproof pouch on
the upper arm or high on the chest, not a hip pocket that spends the bottom of every jibe
underwater — and it says what it costs: Class C · positions only.

### Which watches work with CleanJibe

One table, in the help (`HelpCatalog.whichWatch`), so "will my watch work" has one place to be
answered instead of a third of an answer in each of five topics. Two axes and nothing else:
**certified speed** (did the file carry the receiver's own speed) and **pump strokes and
takeoff effort** (was a wrist accelerometer recorded, which only the CleanJibe watch apps do).

| what you ride with | how it gets in | speed records | pump / takeoff effort |
|---|---|---|---|
| Garmin + the CleanJibe watch app | intervals.icu | certified | yes |
| Garmin, any other profile or app | intervals.icu, or the FIT from a computer | certified | no |
| Apple Watch (Workout app) | Strava or intervals.icu; Apple Health in the beta | certified where the watch's own speed came with it | no |
| Apple Watch + the CleanJibe watch app | straight to the phone (beta) | certified | yes |
| Polar / Suunto / COROS | intervals.icu, or a FIT through the share sheet | FIT certifies; GPX and TCX do not | no |
| Anything that reaches Strava | Import → Strava | uncertified | no |
| A phone in a pocket | Strava, or the file: .fit anywhere, .gpx in the beta | uncertified | no |

**Every row of it is true in every channel** (14 September 2026). The Bluetooth summary card
is a dev door and the Health import and the Apple Watch app are beta doors, so the rows that
used to promise them — *"or over Bluetooth as a summary the moment you stop"*, *"Import →
Apple Health"* — now either name the door that exists in every build or say plainly where
the other one lives. A `HelpTopic` body cannot branch on the channel (the catalogue is pure
data, and the channel-bound filtering is on the *index*), so a sentence in it has to be true
and complete everywhere: a fact about where a feature exists is allowed, a promise is not.

The **same table is public**, at cleanjibe.org/start#watches since 19 September 2026
(cleanjibe.org/watches until then, and a redirect to it since), beside one generated
sentence about the watch app’s Connect IQ product count — so “will my watch work” has one
answer for a rider who has installed nothing yet and the same answer inside the app. The
family-by-family product list is gone from the site: it was `garmin/manifest.xml` typed out
by hand, and the store’s own install button is the only honest answer to “is mine on the
list”. The public copy carries one column
this one does not: the **recording class** (a / b / b + wrist / c, docs/channels.md), printed
above it as its own table — “what you need, what you get” — and repeated on the homepage,
since the question arrives before the import rather than after it. The CleanJibe Apple Watch
app is **b + wrist**: class b speed, plus the 50 Hz wrist accelerometer (ADR-016) the phone
analyses afterwards, which is why its row here says *yes* to pump and takeoff effort and
Apple's own Workout app does not. The public page also answers *no watch at all* with real
instructions: which phone apps record a track and can export it. The public release notes live beside
it at cleanjibe.org/invite#whats-new, generated from `docs/copy/whats-new.json`.

**Where the public vocabulary lives, since 14 September 2026.** Jan: *"The entry web page is
quite long."* The homepage (`web/index.html`) is now the short half — the share card as the
hero, the three product names at one line each, the recording-class table, and the channel
lists — and everything a reader goes *looking* for moved to **cleanjibe.org/learn**
(`web/learn/index.html`): the three pieces in full, the FAQ, **"What it counts"** (the eleven
glossary entries and the track motif that is their key — the same four path strings the iOS
welcome screen and `web/tools/social_card.html` carry, character for character), and "How it
is built". **On 19 September 2026 that page went too**, and this time nothing was rewritten
on the web at all: cleanjibe.org/help is `HelpCatalog` rendered, out of `docs/copy/help.json`
by `web/tools/make_help.py`, opening with the same eleven glossary lines. /learn/ redirects
to /help/#numbers. A page that answers the app's questions in the website's own words is the
drift this file spent September ending. Nothing was reworded in the move, so every metric name on that page is still the
one this file fixes. Beta-channel features carry a small `beta` pill wherever they appear on
the site — the homepage pieces, /start, and /help, where the pill is written from the
exported topic's own `channels` — written from
`docs/channels.md` and from nowhere else, with one line of legend per page: *"beta: in the
public beta today, not yet in the App Store release."* Release features are unlabelled.

## One copy, many surfaces — `docs/copy/`

**The same wording, wherever it is said, pinned from both sides** (15 September 2026).

The website, the App Store description and the app said the same things in different words,
and they had already drifted apart in fourteen places: the web's beta list still promised a
feature that had shipped seven hours earlier, the phone's own clean-jibe definition was a
version behind the engine it shipped with, and the dry streak had four spellings across five
surfaces. Nothing was wrong with any single sentence. What was missing was a mechanism.

`docs/copy/` is seven small JSON files — `channels`, `recording-classes`, `glossary`,
`feedback`, `icu-setup`, `phrases`, `verdicts`, plus the generated `garmin-devices` — each
holding one piece of wording that more than one surface says. Its README carries the schemas
and who authors each key; the rule is short:

* **The kit is the author** for anything the app says, `docs/channels.md` for the channels,
  the manifests for the devices. The JSON is the artefact, never a second draft.
* **Both sides are pinned.** `CopyContractTests` asserts every kit constant equals its JSON,
  so a kit edit that moves a fact **fails the kit tests** until `docs/copy` moves with it.
  The web verifier asserts the pages carry the same strings, so the website has to catch up
  before the check goes green. `docs/copy/check_release_copy.py` asserts the release copy
  names no door the release lacks, keeps the Strava rule and uses none of the banned
  vocabulary (*carried*, *no-fall streak*, *clean-jibe percentage*, *swim rate*,
  *success rate* — CLAUDE.md).
* **Regenerating** after a deliberate rewording, from `ios/WingFoilKit`:

  ```sh
  COPY_WRITE=1 swift test --filter CopyContractTests
  ```

  which rewrites the kit-owned keys in place and leaves the hand-authored ones — the
  forbidden lists, the lexicon, the two store names, and each glossary entry's `short` and
  `sentence` — exactly as they were.

**A glossary entry grew to six fields and a scope** (15 September 2026), because `{ id, term,
line }` serves two surfaces and the product has four and two stores:
`{ id, term, short, expansion, line, sentence, surfaces }`. `term` is the label the phone and
the web print; **`short` is the same word at the watch's width** — at most seven characters
wherever `surfaces` names `watch`, which is what a MIP cell holds and what three shipped
watch labels already exceed. The watch is not given an exemption, it is held to the contract
at its own width, and `CopyContractTests` asserts the budget, so it fails a test instead of
failing a rider. `expansion` is the half the phone and the web append after `" · "` —
`KeyMetrics` built `"CPH · clean jibes per hour"` out of two halves that existed nowhere as
data, and now reads both from the entry. `sentence` is the clause the two store descriptions
print instead of the label (*"how much of it you spent on the foil"*, hand-copied into four
files until now). `surfaces` says who may demand the word, so a watch scan never asks for
`alpha500`, which the watch does not compute. `short` and `sentence` are hand-authored beside
the kit-owned keys, the way `lexicon` and `ciqListingTitle` already are.

**Three entries were added in the same pass**, each a label the app prints on every session
and no surface defined: `tph` (CLAUDE.md — *rates are additive: keep JPH and TPH beside CPH*;
the number was additive, the glossary was not), `best5x10s` and `alpha500`. Eleven entries
now, and `/learn`'s definition list carries all of them.

**`feedback.json` gained `doors`.** One door had five names — `Support & ideas`,
`Menu → Support`, `Settings → Send feedback`, `Something off? Send feedback`,
`Send feedback` — across the app's Help, four website pages and the two store texts, and one
of them named the Settings row **deleted in build 58**, inside the app's own instructions.
`FeedbackDoors` is the list: `app` (`Menu → Support & ideas`), `footer`
(`Something off, or an idea? Send feedback`), `share`
(`Report a problem with this session…`), `testflight` (Apple's `Send Beta Feedback`) and
`web` (the address). The app target's three labels and the Help topic's sentence are all
built from it, so a renamed door renames its own instructions.

**What it deliberately does not pin.** The `HelpCatalog` bodies against `/learn`: the app's
help is reference material behind a `?` and the web's glossary is eleven one-liners for a
stranger — same terms, different depth, so the terms and the one-liners are pinned and the
bodies are left alone. The privacy page against the app: a GDPR document does not belong in a
Settings footer, so the app *links* it (Settings → About → Privacy, and the help topic *What
leaves your phone*) rather than mirroring it. The feedback `mailto:`'s two extra questions:
a browser cannot fill in the watch and the build, and the app can. And the store texts' voice
and length, which are marketing prose — what they must not do is name a door the release
lacks, and that is a check rather than a single source.

## The library menu — one menu, in the order a new rider needs it

The Sessions tab's top-left button (`line.3.horizontal`, "Menu") is the app's one menu. It
used to be a gear with two rows; it is a menu now because a gear promises switches and the
first thing a new rider needs is not a switch. Five items, two dividers, one line of small
print, in this order and for this reason:

1. **What CleanJibe does** — the welcome screen again (`SessionStore.replayWelcome`). First
   since dev 65 (Jan): *what is this* is the question that comes before *how do I start it*,
   and the row that answers it had been sitting below the door to the feedback mail.
2. **Getting started** — the first-session guide as a help topic (`HelpTopicID.gettingStarted`,
   its own first help section, every channel). Second, under the screen that says what the
   app is, because it is what "I just installed this" is looking for next. Since
   15 September 2026 the instructions live IN the app (Jan: never send a rider to the
   website for them): one sentence on the real test — one session on the
   water, read the turn verdicts against what you remember — then the routes as items,
   Garmin with the CleanJibe watch app first, any .fit second, Strava third, the
   three-to-five-minute walk as "if you cannot wait for wind", where to send what you find,
   and the web page named last as the same guide. The two Apple routes are beta topics it
   links to, so the release never names them. Word budgets are enforced by `HelpBudgetTests`.

   **The guide has one source, and it is `docs/guide/getting-started.json`** (Jan, 15 Sep
   2026). The topic and cleanjibe.org/start had been written separately, so the app's last
   item — *"the same guide, on the web"* — named a page that said different things. That file
   now holds the framing, the routes in order with their channel and their steps, the two
   closing notes, the two Settings captions, and the web-only troubleshooting and report
   lists; `web/tools/make_start.py` writes both copies from it — the kit's
   `Help/GettingStartedGuide.swift`, which this topic's `summary`, `body` and `items:` are,
   and the block of `web/start/index.html` between its `<!-- guide:begin -->` and
   `<!-- guide:end -->` markers. The app shows a route's **title and summary**; the web shows
   **title, summary and the numbered steps**, which is why the last item reads *"The same
   guide, with every step, on the web"*. `make_start.py --check` fails while either copy is
   stale and `web/tools/verify_links.py` runs it; `GettingStartedGuideTests` fails if the
   topic stops being the guide, so a route typed straight into `HelpCatalog` is caught too.
   **Channel filtering is the source's `channels` list through `items(for:)`, and since
   dev 65 the app's own channel decides.** The two Apple routes are `.beta`. The catalogue
   is a static array and cannot ask which build is reading it, so it is declared with the
   *release's* list — and until dev 65 that was the answer in every channel, which meant the
   beta's two Apple routes (its watch app, and Apple's Workout app) were named on no page a
   rider would look for them on. `HelpCatalog.topic(_:channel:)` rebuilds a topic's **items**
   for the asking channel (`resolved(_:channel:)`, the one topic that needs it), the sheet
   passes `AppChannel.channel`, and `indexTopics`, `relatedTopics` and `search` resolve the
   same way. The release still names three routes and reaches the two Apple topics through
   nothing at all — `relatedTopics(of:channel:)` drops them — the beta and the dev name five.
   `GettingStartedGuideTests` counts the items per channel.
3. **Settings** — the switches, the watch, the accounts.
4. **Help** — the Help index. It read *What the numbers mean* until 15 September 2026, and
   that was a name for one of its ten sections rather than for the screen: the index opens
   with *Getting started* and *Getting set up*, and closes on *Sharing* and *Quality* — a
   rider looking for how to connect Strava or what a share card carries had no reason to
   open a row that promised arithmetic (Jan, build 63: *"Help is good"*). The icon is
   unchanged (`questionmark.circle`), and so is everything behind the row; *the numbers*
   keep their own headings inside, where they are a section and not the whole screen.
5. **Support & ideas** — the feedback mail (`feedbackMail(on:)`, the same composer as the
   page footers' *Something off, or an idea? Send feedback*, the share sheet's "Report a
   problem with this session…" and, since dev 65, the *Sending feedback* help topic's own
   **Send feedback…** button; `FeedbackDoors.menuRow` is the label). Last of the five since
   dev 65: the two screens above it answer a question on their own, and the rider still
   asking after them is the one this row is for. It said **Support** until 14 September 2026,
   which a rider reads as *the place you go when something is broken*: Jan's point is that a
   wish is as welcome as a fault and nothing in the app had ever said so, and the name of the
   door is the cheapest place to say it.
6. The build line, not tappable: *CleanJibe 0.15.0 (45)* with " · beta" or " · dev" after it
   on those channels — the same string as Settings → About, and the first question of every
   support mail.

**Two dividers, and they group the five.** The first separates the two an arriving rider
reads once — *What CleanJibe does* and *Getting started* — from the three he comes back to:
where the switches are, what the numbers mean, and who to write to. The second holds the
build line under the menu proper, because it is small print and not a row.

**Six rows, and no seventh.** The release channel carried *What is being tested* straight
under **What CleanJibe does** until 15 September 2026, and it is gone from here (Jan, build
58): the menu answers what a rider needs *now* — what the app is, how to start, where the
switches are, what its numbers mean, who to write to — and a list of what this build does not
have is none of those. It has one home, Settings → **Coming in a future release**, described
under "Settings" below.

**The welcome screen closes.** Replayed from the menu it has a circular ✕ at the top right,
because its three buttons are *ways in* and a rider who came back to read it is not choosing
one; a page whose only exits are labelled "Try the example", "Connect" and "Later" reads as a
gate (Jan, 13 Sep 2026). ✕ does what "Later" does: nothing is armed or loaded.

**Every door on this screen is one sheet.** The Sessions tab used to hang seven
`.sheet(isPresented:)` modifiers off one view — Settings, Import, Help, a named help topic,
the release channel's page of what is coming, the beta's date-range editor, the dev build's
tuning hook. SwiftUI resolves sibling presentations on one view in order and drops the ones
that arrive while another is still settling, so the tap that set the *last* flag in the
chain — the help topic, which is what **Getting started** sets — landed on the floor whenever
the menu's own dismissal was still animating, and the row simply did nothing (Jan, build 58).
There is now one `@State` of one enum (`LibrarySheet`) and one `.sheet(item:)` over it: two
writes to one property cannot race, the second replaces the first, and every entry point —
the menu, the toolbar's Import, the empty-library card, the actions Help hands back
(`openIcuSettings`, `loadExampleSession`) and every `UI_SHEET` screenshot hook — writes that
one property. The `UI_SHEET=help|settings|import|tuning|discipline` and `UI_HELP_TOPIC` hooks
are unchanged from the outside.

**The browser's copy of it, and of the tab bar** (19 September 2026). The web app is the
port, so `/app/` wears one bar and it is the app's: the mark, the name and the same **Menu**
button in the same corner (`web/app/index.html`, between `<!-- appheader:begin -->` and
`<!-- appheader:end -->`). The marketing site nav — *Get started · Help · Open the app · Get
the beta* — is on the six reader pages and on none of the app, because two navigations
stacked over the app's own tab bar is what Jan photographed that morning, and because *Open
the app* was a loud door to the page it was on. The two links it took away are menu rows
already, as *Getting started* and *Help*. `web/tools/verify_links.py` byte-pins the nav
across the six and holds `/app/` to the app header instead. The menu sheet itself is the
phone's: the five rows of `AppMenuRow.ordered` with the phone's symbols drawn as line icons,
the one divider above *Settings*, the build line as a footer under a hairline, and *Close*.
The **tab bar** carries the phone's four glyphs over its four words — `water.waves`,
`trophy`, `chart.xyaxis.line`, `bag` — the chosen tab is marked by ink rather than by a box,
and the bar's height is its content plus `env(safe-area-inset-bottom)`, paid once.

## Settings — switches and accounts, and nothing that is already in the menu

Settings opened with three rows — *What CleanJibe does*, *Help* (then still called *What
the numbers mean*) and *Send feedback* — under two paragraphs of footer, and all three are
rows of the library menu one
tap away. Two homes for one door is two wordings to keep in step and one more screen for a
rider to search, so the block is gone (Jan, build 58) and the menu keeps them. What is left
is what only Settings has: **intervals.icu**, **Strava**, deleted sessions, notifications,
analysis, storage, backup, about — switches and accounts.

**The two account sections open by saying why the account is there** (Jan, 15 Sep 2026). The
intervals.icu section opened on an empty field asking for something called an API key, and
the Strava section on a button; neither told a rider what the account was *for*, or whether
he could skip it. Each now has one footnote-sized line as its first row —
`GettingStartedGuide.settingsIcu`, *"Garmin has no open API for a personal app, so
intervals.icu is the free bridge: connect your Garmin there once and every session arrives
here by itself."*, and `GettingStartedGuide.settingsStrava`, *"The route that needs no file:
any watch that syncs to Strava. Positions only, so speed records are uncertified."* Both come
from `docs/guide/getting-started.json`, so the switches and the Getting started guide say one
thing; the longer intervals.icu version, which the help topic prints, is still
`IcuSetupGuide.rationale`. The footers under each section are unchanged and carry the detail —
what is downloaded, what is never written, the connection cap.

**Accounts, not actions** (build 63, "Import does, Settings configures" under Import). The
intervals.icu section is the caption, the key field with *Save & check*, the last sync date
and the two help rows — *Sync now* left it, because fetching sessions is an import and Import
has that button. The Strava section is the caption, *Connect with Strava* or the connected
athlete with *Disconnect*, and the footer. Everything either section offers is about the
account; everything either account is *for* happens one sheet away.

**Notifications say intervals.icu, because that is what is asked.** The switch read *Notify
on new Garmin activities* and the check behind it has never been a Garmin one: it is a call
to the rider's intervals.icu account, and every watch that syncs there — a Garmin, a Polar, a
Suunto, a COROS, an Apple Watch through Health — is announced by it. It is **Notify on new
sessions from intervals.icu** now, and the footer says the same in full. The app also makes
the offer **once by itself, the moment a key has been proved** — not the moment it is typed:
"Save & check" stores the key and *then* asks intervals.icu, and the alert used to fire on
the store, over the spinner and sometimes over a key the answer rejected a second later. The
alert's title is the switch's own label and its message is the switch's own explanation, word
for word (`SettingsCopy`), because it is the same feature; "Notify me" runs the same code
path the switch does, which is what puts the iOS permission sheet under the finger that asked
for it. `NewActivityPrompt.shouldAsk(… keyIsProven:)` holds the rule.

**"Coming in a future release"** — the channel list (docs/channels.md), read the way a rider
asks it. It was *Curious about what is coming* until 14 September 2026 (an App Store app that
opens by being curious about itself reads as an apology) and *What is being tested* until the
15th, which names the room rather than answering the question. What he is asking is when he
gets these things, so the row says it: **these functions come in a future release, and can be
previewed now in the public beta**. On the page, **How to join the beta is the first section
and a step, not a footnote** — *One tap. Your library is kept.*, a prominent **Open
TestFlight** button and `cleanjibe.org/invite` under it, with the footer explaining that
TestFlight is Apple's own app, that the beta reads and writes the same library, and that
going back is allowed. The **dev** doors are not on it in the release channel (`#if BETA`):
tuning, iPad, the Garmin link and windsurf are on a handful of hand-picked phones and are
promised to nobody. The beta shows the same list with the dev rows under it, as *Further
out*, and no join section — the reader is already through the door it offers.

**The list has one home, and this page is it** (Jan, dev 68). The beta and dev channels
printed the beta rows twice on one screen: checked off at the top of the **Beta** section,
and again one row below under *In the public beta*. The Beta section is **actions only**
now — *Request a feature*, *Send usage report*, *Check for a newer build* with its status
line, *Start over* — under one short footer: what the page below lists, what the two mails
do and that neither sends anything until Send is tapped, and what Start over takes, in two
sentences. The four paragraphs it carried are gone; what they said lives on that page, on the
usage report's own card, and in the Start over alert, which names every item.

**One test ask lives in that footer, between the two mails and Start over** (Jan, dev 70):
*"Testing the session video: keep the 20 s preset, wait for the bar, then share the clip."*
The session video is a beta door (docs/channels.md), and the ask used to be a step on
`/start`, which was cut. A beta door's ask belongs beside the beta's own feedback doors, so it
is one line here and not a section anywhere: the preset, the wait, the share.

## The status line — a toast, and toasts go away

One line at the foot of the Sessions list says what the app is doing or has just done:
*Importing 3 files…*, *Re-clustered into 4 spots*, *Backup ready — 65,9 MB*. Forty-odd places
write it and nothing used to clear it, so the last sentence any job happened to leave behind
sat there until another job replaced it — Jan found *Backup ready — 65,9 MB* still on the
list a quarter of an hour later, which turns a report of something finishing into a claim
about the present.

`SessionStore.status` now arms its own dismissal: **six seconds** (`statusLinger`), then the
line fades out. Two rules the timer keeps. **A message about work in progress outlives the
work** — `isBusy` holds the line and the clear is re-armed rather than fired, so *Packing your
library…* is up for as long as the packing is and the six seconds start when it stops. And
**only the message that armed the timer may be cleared by it**: every write bumps a
generation and a stale timer returns without touching anything, so a slow job's old toast can
never wipe out the one that replaced it. A tap on the line takes it down early, which is
allowed only while nothing is busy. Nothing else about the line changed — same place, same
`.bar` background, same spinner while work is running.

## Feedback mail — the report the app writes and the rider signs

One mail to `info@cleanjibe.org`, reachable from wherever the rider is when something looks
wrong **or when he wants something**: **Menu → Support & ideas** on the Sessions tab,
**Report a problem with this session…** at the foot of a session's share sheet, and a quiet
line at the **foot of every page** — *Something off, or an idea? Send feedback* under the last
row of Sessions, Records, Trends and Gear, and under the last card of a session
(`FeedbackFooter`). On the beta, a screenshot taken inside the app also offers Apple's
**Send Beta Feedback**, which carries the screenshot and the device logs.

**There is no Settings row, and no document may say there is.** The feedback block was
deleted from Settings in build 58 — Settings keeps switches and accounts, and the menu one tap
away already had the door — and the sentence *Settings → Send feedback* outlived it in the
app's own Help, on four website pages and in this file. Every name is `FeedbackDoors` now
(`docs/copy/feedback.json → doors`, pinned by `CopyContractTests`): the app target's three
labels, the Help topic's sentence and the beta footer's are built from it, so a renamed door
renames its own instructions.

**A wish is as welcome as a fault, and five surfaces say so in one sentence** (Jan, 14 Sep
2026). Every door to this mail was named and worded for something being *wrong*, and a beta
whose only invitation is to report faults gets faults reported and nothing else. The sentence
is written once — `FeedbackInvitation.sentence`, *"Ideas and wishes are as welcome as bugs."* —
and carried by the menu row's name, the footer line above, the welcome screen (with the way in
appended: `welcomeSentence`, *"· Menu → Support & ideas"*), Settings → Help's footer, and the
mail's own template. The release notes close on it too
(`ios/tools/testflight_publish.py`, both `WHATS_NEW` and `WHATS_NEW_INTERNAL`).
The session page's line carries the session, so the mail names the afternoon by itself; the
card is attached only from the share sheet, where it is already drawn. Every door climbs the
same ladder (`feedbackMail(on:)`): Mail, then the `mailto:` handler, then the copy sheet.
The subject is `CleanJibe feedback · build <N>[ dev] · <watch>` — the build number, not
the marketing version, because the two TestFlight variants of a release share the latter. It
said *beta feedback* until 14 September 2026: the same kit writes the App Store app's mail,
and a rider who joined nothing must not find his own mail calling the app he bought a test.
The build number still says which channel it is to anybody who needs to know.

**Two facts are left out where the channel has no door for them.** `Health import off` and
`No Apple Watch paired` are answers to questions the App Store build never asks — Health and
the watch app are beta doors — so the app passes both as `nil` outside `#if BETA` and
`FeedbackReport` omits a nil fact rather than printing it (`FeedbackFacts.Watch`).

**The body opens with three labelled blanks, and the facts are under a rule.** The template
was one word — *What happened* — and one empty line, which is a prompt for a paragraph rather
than for a report; what arrived was a paragraph, and the three follow-up mails it always cost
are now asked in advance (Jan, 14 Sep 2026). Each label owns two lines, one for the answer and
one of air:

```
What happened, or what you would like:


What you expected instead:


Which session, its date and spot, if it is about one:


Ideas and wishes are as welcome as bugs.

----------------------------------------
Below is what the app knows about this phone and build. It helps analysis. Delete any line you would rather not send.

App
  …
```

The first label asks two questions on one line on purpose: a rider with a feature wish must
not have to decide whether the form is for him. The third is **answered for him** where the app
knows — from the share sheet's "Report a problem with this session…" the date and the spot are
written onto the first of its two lines, and nothing else about the session is, because the
rest is diagnostics and diagnostics live under the rule. The rule's own sentence is what makes
the facts below it *deletable* rather than merely present: they include a phone model, a
locale, a library shape and sometimes a spot, which is a map pin to where somebody rides.

Everything the phone knows is *below* that rule: a mail that opens with twenty lines of
diagnostics makes the reporter scroll past them to write his report. Prefilled, in this order
(`FeedbackReport`, composed in the kit and asserted line by line in `FeedbackReportTests`):

| section | what it carries |
|---|---|
| App | marketing version and build, dev (TUNING) or public, `AnalysisEngine.version`, and the count of tuned thresholds — that last line only when there are some, and only on the dev build, which is the only one that applies them |
| Phone | the model identifier (`iPhone18,2`) with its marketing name in front of it where the table knows one, the iOS version, the locale |
| Watch | the paired Garmin's name from the companion link, the CleanJibe watch app's version decoded from the last BLE card's build tag (`APP_MINOR * 256 + FIT schema`), whether an Apple Watch is paired (`WCSession`, omitted when it cannot be asked), Health auto-import on or off |
| Library | how many sessions, and the count per door they came in by — a session merged from two sources is counted under both, which is the answer a duplicate report needs |
| Session | *only from a session page*: its date in its own zone, spot, discipline, duration, source-class letter, the `engineVersion` stamp (tuning fingerprint included) and the stable row id — with that session's **share card attached** as a PNG |

It closes with `sent from CleanJibe`. **Nothing leaves the phone until the rider taps Send**:
the mail is `MFMailComposeViewController`, every line of it is editable, and there is no
CleanJibe server for it to go to in any case. Where Mail is not configured
(`canSendMail == false`) the same subject and body go to the system's `mailto:` handler; where
that too goes nowhere, a sheet shows the report in full with one button that copies it. The
help topic is "Sending feedback", last in *Getting set up* — the section's way back out.

**And that topic offers the mail rather than only describing it** (Jan, dev 65). It named
three doors and had none: a page about sending feedback that asks the reader to go and find
one of them is a page he has to leave to use. It carries `HelpAction.sendFeedback`, and the
sheet draws **Send feedback…** wherever somebody can honour it — the Sessions list hands the
action down (`\.sendFeedback` in the environment, the same `feedbackMail(on:)` ladder Menu →
Support & ideas climbs), exactly as it hands down *Open CleanJibe Settings* and *Load the
example session*; anywhere else the button simply is not there. The topic keeps naming the
three doors, because they are where the rider starts next time. Its **invitation is said
once**: `FeedbackInvitation.sentence` opened the summary *and* the first paragraph, one line
under the other, and it now stays in the summary, which is the line the index shows.

### The beta's usage report

**Beta only** (`#if BETA`, docs/channels.md). The same mail with one more block at the foot of
it, under one sentence that says what the block is: *"The block below is what the beta counts
on this phone. It helps development and is a key part of being in the beta. Delete any line
you would rather not send."* The subject is its own — **`CleanJibe beta usage report`** — so a
mailbox sorted by subject does not file it as a bug report and answer it as one.

The block is headed **Usage and features** (`UsageCounters.report`, asserted line by line in
`UsageCountersTests`) and carries, in this order: the build, the first-launch date, how many
days the app has been used on and the day the mail was written; then one line per door that
has been opened — `share card · 12 · last 13 Sep`; then, on **one** line, every door that has
not been opened at all, which is the half that decides what ships (channels.md, rule 1);
then the failures this phone has shown, newest first, deduplicated by message with a count
beside each — the rider-facing sentence, exactly as it was on the screen.

Seventeen doors are counted, one call site each: app opened · the six import doors
(intervals.icu, file, Strava, Apple Health, share sheet, Garmin ZIP), counted in **sessions**
rather than in taps · session opened · turn page · share card · replay clip · session video ·
backup made · backup restored · settings opened · feedback mail · Strava connected. Counts and
a last-used date, never a timestamped trail: "share card · 12 · last 13 Sep" answers the
question the beta has, and a log of twelve moments would additionally describe a rider's
afternoons. They live in this phone's `UserDefaults` (`usage.counters.v1`), they are never
uploaded, and the only way a number leaves the phone is that mail.

**The ask.** After every fifth session imported, or a fortnight since the last ask — whichever
comes first — the library shows one card at the top of the list: *Help the beta: send your
usage report*, with **Write the mail** and **Not now**. A card in the list rather than an
alert, because the honest answer is often "not while I am standing on a beach": it waits where
the rider is already looking, and "Not now" buys a fortnight of quiet rather than ending the
conversation. Either button answers it and the card is gone. **Settings → Beta → Send usage
report** is the permanent door, for the rider who did not wait to be asked and the one who
said Not now and changed his mind.

### The beta's update reminder

**Beta and dev only** (`#if BETA`, docs/channels.md). TestFlight *offers* a build; it does not
insist on one, and a tester with notifications off goes on riding — and reporting — with a
build we have already read the reports of and fixed. The cost is reports against the wrong
build and a rider who believes a mended thing is still broken, so the app says so itself.

**One static file is the whole mechanism.** `web/app/version.json` on cleanjibe.org carries,
per channel, four things: `minBuild` — *the oldest build still worth a report*, not the newest
that exists — one sentence in Jan's words, a level, and where *Update* goes. Jan edits it by
hand and commits it with any other web change; there is no server, no account and no push, and
deleting a channel's entry is how a reminder is taken back off every phone
(web/app/version.README.md says who edits it and what the two levels mean).

**What the app does with it.** At launch and on every return to the foreground, at most once
every 24 hours, it fetches the file, looks up its own channel (`ChannelFeatures.channel`) and
compares `minBuild` with its own `CFBundleVersion`. The comparison is `UpdateVerdict.decide`
in the kit, where the suite holds it; the fetching, the remembering and the drawing are
`UpdateReminder` / `UpdateReminderViews` in the app. A build *at or above* `minBuild` sees
nothing, and so does a build *ahead* of it — a dev build cut this morning is never told to go
back. The last answer is kept in `UserDefaults`, so the line is on the first frame of the next
launch rather than only on the one launch in twelve that falls after the 24 hours.

**Two levels, and only two.** `remind` is one dismissable line at the top of the library, above
the empty state and beside the usage ask, with the message, an *Update* link and a ✕. The ✕ is
remembered against that `minBuild` and not as a flag, so the next raise of the number asks
again by itself; Settings still says a newer build is out. `insist` is one full screen with the
message and an *Update* button, in front of the whole app and not dismissable — the third
screen in the app argued for that way (`LibraryNewerThanAppView`, `StartOverRelaunchView`),
because behind a banner the four tabs would go on inviting the rider to record, import and
report with the build the screen exists about. It says plainly that nothing has been changed
and nothing is lost. A word in the file that is neither reminds rather than insists: a typo
must not be able to put a screen in front of every tester.

**Failure is silence, everywhere.** Offline, a 404, a half-written file, a build number the
plist does not carry: the rider is told nothing, the last answer is kept, and the app tries
again later. He did not ask a question, so he gets no error. The one place he *did* ask is
**Settings → Beta → Check for a newer build now**, which ignores both clocks and prints the
running build, the verdict in one sentence and when the file was last read — the only surface
that names all four verdicts, and the way back for the tester who closed the line and changed
his mind.

**What it costs him.** One GET of about three hundred bytes a day, to the site he installed
the app from, with no query string, no header of ours, no cookie store and no identifier — it
does not even say which build is asking, because the comparison happens on the phone. The
privacy page carries it as the ninth entry under "what leaves your phone". The release build
does none of this: the whole feature is behind `#if BETA`, and `strings` on the App Store
binary finds no `version.json` (docs/testing.md, "Three channels").

### Start over

**Beta and dev only** (`#if BETA`, docs/channels.md), last row of the Beta section, red, and
the only destructive button in the app. It exists because deleting the app does not do what a
tester means by it: iOS keeps keychain items across a delete, so the intervals.icu key and the
Strava connection come back with the reinstall and the fresh first run he was trying to see
never happens (Jan, 14 September 2026 — he deleted the app, reinstalled it, and found both
already there).

The confirmation names everything that goes, because a rider cannot check "all data" and
because the two items he would never guess at are the whole point: *your whole library —
every session, its analysis and its archived recording, the deleted-session memory and any
backup file still waiting on this phone; your intervals.icu key and your Strava connection,
both of which live in the iOS keychain, which is why deleting the app leaves them behind and
this does not; every setting — the welcome screen's flag, map style and layers, replay length,
framing and music, the notification choices, the map picks for the watch and the tuning
sliders; the beta's usage counters and the widgets' snapshot; cached thumbnails, imported
files and anything half-exported.* It closes with what is **not** touched — the sessions on
intervals.icu, the activities on Strava and the recordings on the watch are somebody else's
copy — and with "make a backup first if you want one", because there is no undo.

**It does not ask for a relaunch.** Settings closes, the library's GRDB pool is parked in
memory, the container, the defaults domain and the two keychain items go, a new pool is
opened on the same path where the migrator writes an empty schema, every property that
mirrors a default is read back from the now-empty domain, and the empty library is read —
which is the same event a first launch has, so `RootView` raises the welcome screen by the
ordinary route.

**And the welcome is promised to the next launch as well, in writing** (Jan, build 63: *Start
over, restart, and the app opened on Sessions — this is a mistake*). Everything above is an
argument from **absence**: no `welcomeShown.v1`, no sessions. A wipe can create an absence but
it cannot hand one to the next launch — the screen it raises in-process writes the flag again
the moment it goes up, and a library that has rows once more before the screen is raised (a
sync, a watch transfer, a re-import, or the relaunch the failed-reopen screen asks for) reads
as a *history*, at which point the upgrade path marks the screen seen on sight and the rider
never gets it. So `startOver()` writes one positive fact back immediately after the wipe —
`welcomeRequested.v1` — and `showWelcomeIfNeeded` honours it **first**, before the silent mark
and before the flag: a request outranks `hasSeen` and a library of any size, only a screen
already up defers it, and it is cleared the moment the welcome actually appears. So the
welcome happens exactly once after a Start over — now if nothing is in the way, on the next
launch otherwise — and the screen it appears on is the full-screen cover in front of the tabs,
not a sheet with Sessions in charge behind it. `WelcomePrompt.shouldShow(… requested:)` holds
the rule and `OnboardingTests` pins it at 300 sessions with the flag already written. The
`UI_RESET=1` screenshot hook deliberately does **not** write the request: it wipes before the
store exists so a first run can be photographed, and a staged welcome over a staged library
would be a screenshot of neither. The one thing that can fail is reopening the file, and there the app says so
rather than running on a library that is not on disk: one full screen, *"Start over done —
close the app and open it again"*, with no button, because iOS gives an app no supported way
to quit itself and `exit(0)` reads as a crash in the feature the rider just used.

## Start screen — the mark, held for two seconds

**The phone opens on the brand, and the handover is invisible.** iOS draws `UILaunchScreen`
(ios/project.yml) before a line of our code runs: the `SplashMark` asset on the
`LaunchBackground` navy, and — measured on the simulator rather than assumed — it draws that
image at its **natural point size, centred in the safe area**. The asset is therefore
140 / 280 / 420 px at 1×/2×/3×, which puts a 140 pt mark at the centre of the safe area on
every device, and `SplashView` opens with the same artwork at the same size in the same
place. Nothing moves when our own first frame replaces the system's; the mark carries no
shadow and no corner clip for exactly that reason, because a launch screen can draw neither.
(`LaunchMark` is unchanged and still the full-resolution artwork the share card, the QR's
centre mark and the welcome screen use.)

**The channel wears its own mark.** The beta's launch screen, splash, welcome page, icon and
watch start page show the mark with a red BETA label upper right; the dev app's show it
mirrored, wing upper right; the App Store app's is the mark as drawn. `CJ_SPLASH_MARK`
picks the launch image per configuration and `ChannelArt` the two the code names, so the
handover above stays invisible in every channel. The share card and the QR keep the
release mark (docs/channels.md, "Telling the channels apart").

The clock moves as little as the mark does: `UIStatusBarStyle: UIStatusBarStyleLightContent`
is what the *launch* screen reads and `preferredColorScheme(.dark)` is what the splash asks
for, so the status bar is white over that navy on both frames. It changes nothing afterwards —
`UIViewControllerBasedStatusBarAppearance` defaults to on, so the library keeps its own.

Under the mark, and the only thing that moves — they fade up over 0.35 s — the wordmark
**CleanJibe** and the share card's call to action *without its address*: "analyze your
wingfoil sessions free". Same line, one source (`Branding.callToAction`), minus the
`cleanjibe.org` that exists for a receiver who does not have the app yet. **The address then
follows on a line of its own** (`Branding.site`), so the screen reads mark · CleanJibe · what
the app is for · cleanjibe.org — the start screen should say where to find us and not only who
we are (Jan, 14 Sep 2026), and a rider showing the app to someone on the beach is the reader it
is written for. It survives landscape where the call to action does not, being one short line
rather than a wrapping sentence; the words hang off the mark as an overlay and grow
downwards, so neither line can move the mark off the centre the launch screen put it on.

**The three lines are set in points, and they were made bigger** (Jan, 14 Sep 2026: too small
on a phone). The first cut was `.largeTitle.bold`, `.footnote` and `.caption2` at 55 % of the
paper — 13 pt and 11 pt of small print on a screen whose entire job for two seconds is to be
read at arm's length, often over somebody's shoulder. Now, and named in `Splash` so the
lockup's proportions are one decision:

| line | portrait | landscape | ink |
|---|---|---|---|
| wordmark `CleanJibe` | **34 pt semibold** (`Splash.wordmarkPoint`) | 28 pt (`wordmarkPointShort`) | paper |
| tagline | **17 pt** (`taglinePoint`) | dropped | paper at 80 % |
| `cleanjibe.org` | **15 pt** (`sitePoint`) | 14 pt (`sitePointShort`) | paper at 80 % |

Semibold rather than bold: at 34 pt bold reads as a shout, and the mark above it is already
the loud half. Fixed points rather than text styles, and this is the one screen that earns
them — the lockup hangs under a mark the launch screen has pinned to the pixel, so it may not
reflow with Dynamic Type; at the largest accessibility size it would push the address off the
bottom of a phone in landscape, and the mark cannot move to make room. Every other screen in
the app follows Dynamic Type. The landscape column is the same lockup with the tagline gone and
the two survivors stepped down, which keeps the block inside the ~195 pt a compact height
leaves below the centred mark (140/2 + 16 + 28 + 6 + 14 ≈ 134 pt).

**It stays for max(2 s, the library).** Jan set the floor — *"Don't make it too short; can be
2 seconds or so"* — and the second half of the rule is what makes it honest: a cold start
still reading the library at the end of those two seconds goes on showing the brand rather
than handing over to an empty list (on a simulator stuffed with fixtures that is a minute or
more, by design). Then a **0.4 s crossfade** into Sessions — under Reduce Motion, a cut after
the same hold. It is **cold start only**: the view is built once per process, so a return
from the background shows nothing. It is one accessibility element labelled "CleanJibe", and
it dismisses itself on a clock, so VoiceOver has one thing to say and nothing to escape. The
simulator screenshot hooks switch it off outright — any `UI_` variable means an automated
launch, the hold is 0 s and the splash is never built, so every existing shot is unchanged.

**The watch has no splash, and the mark is simply on the start page.** A phone app opens into
a library that takes a moment to read; a watch app opens into a button the rider is standing
in the shallows waiting to press, and two seconds of brand there would be two seconds of
nothing at the worst possible moment. So `StartView` wears the mark above its own name — the
first thing seen, one lockup with the wordmark — and the GPS line and START are where they
always were. The mark is **a fraction of the glass** (14 %, clamped to 26–36 pt: 28 pt on a
40 mm SE, 35 pt on an Ultra) and the page **scrolls** now, both for the same reason: a 40 mm
watch has about 165 pt of usable height and the page had already spent it, so at a fixed size
the "Allow Apple Health to record heart rate" note lost its second line and truncated
mid-word. Nothing moves under the thumb when everything fits (`.basedOnSize`).

## Home-screen widgets — three, and what each of them says

Beta and dev only (docs/channels.md): the release app embeds no widget extension. All three
read one small JSON blob the app publishes after every library change and decode it and
nothing else — the extension does not link the kit and cannot open the library (ADR-011), so
every question that needs a library row is answered on the app's side and arrives here
already answered.

| widget | families | what it says |
|---|---|---|
| **Last session** | small · medium · large | the last afternoon **ridden**: its name, its date, on-foil share, best 2 s, flights, the turn tally, and the track behind the numbers |
| **This week** | small · medium | foil time over the last seven days — or, in a week with nothing in it, "since your last session" |
| **Personal bests** | small · medium | best 2 s, longest flight, best JPH, each with where and when |

**The last session is the last one ridden**, which is not the same as the newest row. On
14 September 2026 the newest row in Jan's library was a dry test recording and his home
screen read `FOIL 0 % · BEST 2 S — · FLIGHTS 0` while the afternoon before it sat one row
down. The rule is the newest non-provisional row with foil time on it
(`WidgetSnapshot.isRidden`), falling back to the newest row of all only when the library
holds no ridden session at all — a rider whose library is one dry test still gets his row.
A provisional row is excluded for the same reason it is badged in the library: it is the
watch's BLE card with no analysis behind it, and it has no numbers to print. The title is
the library's own (`SessionDisplay.title`: the rider's name for it, else the spot the
filename implies), the date under it, and the tally is shown only when the session has one.

**The track behind the numbers.** The session's outline is drawn as one thin line in the
brand green *behind* the block, at 38 % on medium, 45 % on large and 16 % on small, where
the numbers own every pixel. It is the app's own outline and not a second drawing: the
snapshot carries the cached `TrackThumbnail`'s vertices, already normalized into a unit
square with the aspect preserved by the same projection the list row, the map and the share
card use, thinned to ~150 evenly-spaced points and rounded to four decimals in the *builder*.
The widget owns no projection code and must not — a second projection is a second shape. A
session with no positions, or one whose thumbnail has not been built yet, simply has no
track, and the widget draws none.

**"Since your last session" — the week with nothing in it.** A week away from the water used
to render `0 m on the foil · 2 sessions · 0.0 h out`, which is both dispiriting and, with
two dry test rows in it, wrong. Both windows now count ridden afternoons only, and when the
seven days ending on the day the widget is *drawn* hold none of them the widget switches:

* **days since the last session**, counted against that day rather than against the day the
  snapshot was written;
* **the season so far** — the app's own season, 1 April → 31 March, labelled the way the
  Periods screen labels it ("Season 2026/27") — sessions, hours on the foil, clean jibes;
* **one rotating fact**, changing at midnight.

The rotation is the season's own bests — best 2 s, longest flight, best JPH, longest dry
streak — plus **on this day**: a session in the *same ISO week* of an earlier year, which is
the honest window for a sport whose calendar is weather ("Two years ago this week: Nago
Torbole, 11 flights, best 2 s 24.13 kn"). Before the first afternoon of a new season the
rotation falls back to the all-time bests rather than going blank. The fact of the day is
picked by **ordinal day of year**, so it stays put for the day it is the day's fact; the
timeline carries one entry per day for a week, which is also what turns "11 days" into
"12 days" at midnight without the app being opened.

**Personal bests are three, and JPH is one of them.** Rates are additive (CLAUDE.md): JPH
sits beside the speed and the flight here, and displaces CPH nowhere. The speed record is
**certified sources only** (`RecordBest.certified`) — a class (c) recording can misreport a
speed, and a personal best nobody can stand behind is worse than none — while the flight and
the rate take no such filter, because how long an afternoon flew is not a claim its speed
channel makes. JPH takes the same session-length floor "Best CPH" takes
(`SessionRecordKind.cphMinDurationS`): a rate a rider can set by going home early is not a
record. JPH itself is the engine's — dry jibes over timer hours, read back off the `turn`
table by `LibraryStore.jibeRates`, because the session index denormalizes CPH and not JPH.

**The words and the numbers are the app's.** The extension cannot call `Fmt` or
`KeyMetrics`, so `WidgetFormat` copies the four rules it needs and names, in each doc
comment, the kit function it may not drift from: the percent rule (`47 %`, one decimal below
ten), knots at two decimals, the `1:57 h` / `10:45 min` duration, and a rate at one decimal.
Rider vocabulary throughout — *flew through*, *touchdown*, *fell in*, *clean*, *dry*.

**When the widget shows nothing.** Two different empty states, and they say different
things: "No sessions yet." for an empty library, and "Open CleanJibe to finish setting up
the widget." when the shared container is not reachable, which is a setup fact and worth
saying out loud (ADR-011 — the App Store profile carries no app group today).

## iPad and Mac — one column, wider glass

The iPhone app **is** the iPad app (`TARGETED_DEVICE_FAMILY: "1,2"` on the app and the widget
extension, 13 Sep 2026), and because `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` is on by default
an Apple-silicon Mac gets the same binary from the App Store as **"Designed for iPad"**. There
is no third UI: one build, three shapes of window.

**What is deliberately unchanged.** The tab bar is still four tabs, the library is still a
list that pushes a session, and the session is still one scrolling page over the four-way
switcher of "Sections". There is no `NavigationSplitView`, no sidebar, no two-column
library-and-session, and no iPad-only screen. A sidebar would make the session page the
*detail* of a list, and the session page is the app — the tabs are four ways of asking about
the library, not four folders to keep open beside it. The phone layout is the answer at every
width; the iPad only changes how much glass one answer is entitled to.

**What changes at regular width** — and only at regular width in *both* axes
(`SizeClass.isWideScreen`, because a Pro Max phone on its side is horizontally regular and is
still a phone):

* **One readable column, centred** (`ContentWidth.column`, 740 pt — `readableColumn()`). Every
  scrolling surface takes it: the library, Records, Trends, Gear & spots, Periods, the session
  page, the turn and flight-end pages, Settings, Tuning, a help topic, both card composers.
  Without it the key-metrics block puts three numbers a hand's width apart, a card grid
  (`GridItem(.adaptive(minimum: 150))`) lays six tiles across a row that holds four facts and
  orphans the seventh, and a footnote runs twenty-five words to the line.
* **The figures buy their room back in height, not width** (`figureHeight(regular:compact:wide:)`).
  Inside a 740 pt column a phone-height map would gain nothing from an iPad at all, and an
  iPad has the vertical room a phone does not: the track map goes 260 → 380 pt, the speed
  chart 190 → 260, the turn map 260 → 340, the turn strip 170 → 220, the heading strip
  140 → 180, the baro strip 120 → 155, the focus map 240 → 330. The full-screen map
  (`FullScreenMapView`) is still full-bleed — it is the one surface whose whole point is all
  the glass there is. The one thing this costs is worth naming: on an iPad *in landscape* the
  map and the speed chart no longer both fit above the fold. They did not quite fit at the
  phone's heights either (a 1 024 pt window minus the key-metrics block leaves about 530 pt
  for a 260 pt map, its two control rows and a 190 pt chart), and the "one instrument" rule
  of "Pairing" is about the shared playhead and the shared tap, not about a scroll — which is
  why the compact heights exist for the one screen where it *is* about the fold, a phone on
  its side.
* **The speed table's fixed columns widen** (`RecordColumns`): 66 / 58 / 56 pt on a phone,
  112 / 78 / 64 on an iPad. The three fixed columns are what makes the table scannable, and at
  the phone's widths `Best 5×10 s` printed as `Best 5×…` with 300 pt of empty "when · where"
  beside it.
* **Sheets are pages, not form sheets** (`.presentationSizing(.page)`). A `.large` detent is a
  compact-width idea; on an iPad the system's default form sheet is about 570 × 640 pt, which
  is a *smaller* window than the phone's. The screens that are screens get `.page` — the turn
  and flight-end drill-ins, Settings, Tuning, the Help index and each help topic, both card
  composers, the clip setup and the video export (whose finished state is a 420 pt tall 9 : 16
  player with a share button under it). The sheets that are questions keep the form sheet,
  which is what a question should look like: the rider prompt, the discipline review, the
  re-add offer, the gear editor, Import.
* **All four orientations** (`UISupportedInterfaceOrientations~ipad`). An iPad has no wrong
  way up; the phone list still leaves upside-down out, because a phone flipped over hides the
  earpiece.

The **navigation bar belongs to the window, not to the column**: on the four tab roots the
large title and the toolbar buttons stay at the window's edges while the list under them is
centred. That is left alone deliberately — pulling the whole `NavigationStack` into the column
would centre the title at the cost of a 740 pt bar with hard edges and empty glass beside it
every time the content scrolls under it, which is a worse thing to look at than a title above
a centred card. The session page does not have the question at all: its title is inline.

**Widgets.** The extension ships for both families too. Its three widgets declare
`.systemSmall` and `.systemMedium` (and `.systemLarge` on the last-session one), every one
of which is valid on iPad, on the Home Screen and in Today view alike; the snapshot they
draw is the same JSON the phone writes.

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
