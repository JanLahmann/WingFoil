> Part of `docs/presentation.md`. Engine 0.24.0.

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
(`SessionAnalysis.submersions`, engine 0.16.0, docs/algorithms/pumping.md "Submersion episodes") and
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

