# Watch map page — analysis and suggestions

*Analysis only. No source file was changed. Written against `6885530` (watch 0.9.6).*

The question was "fix the display of the map on the Garmin watch". There are two different
things that can mean, and this document takes both:

1. **The page shows no map** — only the session's own breadcrumb on black. That is
   GitHub issue #4 ("map background would be nice"), and it is the state 0.9.2 chose after the
   firmware's native map view killed the app twice on the fenix 8.
2. **The breadcrumb itself is weak** — it degrades over a session in ways the screenshot rig
   never shows, and it gives the rider none of the reference points a map is for.

Section 2 is the evidence, section 3 the suggestions, section 4 a recommended order.

---

## 1. What the page is today

| | where |
|---|---|
| The renderer, shared by the live page and the post-save Track page | `garmin/source/ui/TrackDraw.mc` |
| The live page: box, "waiting for GPS", odometer caption, marker | `RecordingView.drawMapPage`, `RecordingView.mc:2088` |
| The post-save page | `SummaryView.drawTrack`, `SummaryView.mc:264` |
| The buffer: 128 points of `Float` lat/lon + a `Boolean` foil state, filled on a tick stride | `MetricsEngine._trackTick`, `MetricsEngine.mc:204` |
| Why the native map is gone | `docs/watch-ui-review.md` §12.1, `RecordingDelegate.mc:7-15`, issue #4 |
| The layout test | `mapPageFitsRoundDisplay`, `WingfoilTests.mc:3711` |
| The screenshot seed | `ShotSeed.seed`, `garmin/screenshots/source/ShotsApp.mc:178` |

The renderer is sound as far as it goes: bounding box, longitude squeezed by cos(lat), one
aspect-preserving scale into the square inscribed in the glass, one `setColor` per run of
equal foil state, north up. The box is roughly 270 px on a 454 px glass and roughly 140 px on
a 240 px fenix 7S (`mapPageFitsRoundDisplay` logs the exact figure per product).

---

## 2. Findings

### 2.1 No basemap — the actual ask (issue #4)

Three attempts at the firmware's map view, three deaths, all on Jan's fenix 8 and none in the
simulator:

| version | how the view went on screen | what happened |
|---|---|---|
| 0.8.x–0.9.0 | `switchToView(new MapPageView())` | Unexpected Type Error on device |
| 0.9.1 (`b891e08`) | `pushView`, the documented way | app killed on the page, mid-recording, **nothing in CIQ_LOG** |
| 0.9.2 (`2b3bc66`) | no native view; `TrackDraw` on black | — |

The 0.9.0 death is explained: `switchToView` onto a native base view is unsupported and the
forums have reported exactly that Type Error for years. The 0.9.1 death is **not** explained,
and 0.9.2 stopped looking. Read today, the 0.9.1 `MapPageView` (`git show
b891e08:garmin/source/ui/MapPageView.mc`) did four things at once that each carry a known
risk on real hardware, and no experiment ever separated them:

- **Built the whole overlay inside `onShow`.** `onShow` called `_refresh()` synchronously,
  which allocated ~128 `Position.Location` objects, called `clear()`, added up to 32
  `MapPolyline`s with `setPolyline()`, and then `WatchUi.requestUpdate()` — all before the
  native view had rendered once. Forum guidance from Garmin staff warns that view-stack work
  done from `onShow`/`onUpdate` is unreliable on some devices; 0.9.1 did not push from there,
  but it did everything else there, and "the moment it came up" is exactly the timing the
  crash had.
- **Used `MapTrackView`, not `MapView`.** `MapTrackView` is the less-used class: it centres
  itself, draws the device's navigation arrow, and forum bug reports name it specifically for
  device-only crashes (a 530 report, and "works in the simulator, crashes on the watch" when
  anything is drawn over it). `MapView` with `setMapVisibleArea` is the class most apps that
  ship a map actually use.
- **Rebuilt every polyline on a 5 s `Timer`** while recording at 1 Hz, with a sensor listener
  and a `SensorLogger` open. Repeated `clear()` + 32 × `setPolyline()` against a native
  renderer that was mid-tile is the kind of thing a silent kill looks like.
- **Ran with no memory telemetry.** A native map view allocates against the app, and the app
  already carries the detectors, a 256-slot history, the pump detector's buffers and the
  accelerometer batches in its 768 KB. Nobody printed `System.getSystemStats().usedMemory`
  before the push, so "out of memory" was never ruled in or out — and an OOM in native code
  is the classic cause of a kill that leaves no CIQ_LOG entry.

None of those is proven to be the cause. The point is that they are separable, cheaply, and
0.9.2's conclusion ("a fourth blind attempt is not worth it") was right about *blind* and
says nothing about a *measured* attempt. Section 3.2 gives the ladder.

One more thing the native view could never do and the current page can: the products list
(`garmin/manifest.xml`) now includes watches with no map at all — fr255 and fr265 today, and
any product added later. Whatever comes back, `TrackDraw` stays as the fallback for
`!(WatchUi has :MapView)`.

### 2.2 The trail's resolution collapses over a session — HIGH

`_trackTick` keeps one point every `TRACK_BASE_STRIDE` (5) usable ticks and, when the 128
slots fill, drops every second point and doubles the stride. The arithmetic for a session:

| buffer fills at | points kept | stride after | metres per point at 20 km/h | at 30 km/h |
|---|---|---|---|---|
| 10.7 min | 128 → 64 | 10 s | 56 m | 83 m |
| 21.3 min | 128 → 64 | 20 s | 111 m | 167 m |
| 42.7 min | 128 → 64 | 40 s | 222 m | 333 m |
| 85.3 min | 128 → 64 | 80 s | **444 m** | **667 m** |
| 170.7 min | 128 → 64 | 160 s | 889 m | 1.3 km |

Jan's seeded session is 1:57. At its end the buffer holds about 90 points **80 s apart**. A
Garda reach is 0.5–1.5 km, so a reach is one to three points and the turnaround at each end
— the jibe, the one shape a wingfoiler would look for — is not on the map at all. The
breadcrumb at that point is a zigzag through the reaches' midpoints, not a track.

Three consequences follow from the same number:

- **The tint lies.** `fly[]` is sampled at one instant per point, so at 80 s per point a
  60 s flight is present or absent by luck. `TrackTint` then absorbs "flicker" up to
  `MAX_RUNS`, which turns that luck into long wrongly-coloured stretches.
- **The screenshot rig flatters it.** `ShotSeed` fills all 128 slots with a smooth synthetic
  six-reach track — the shape of a 10-minute session, captioned 23.1 km. No shot in
  `brand/store-shots-09/` is of the map page, and if there were one it would not look like
  the page after an hour.
- **Halving is the wrong decimator.** Dropping every other point is blind to geometry: it
  throws away corners as readily as straights. The watch does not need Douglas-Peucker, it
  needs the cheap version — keep a point when the rider has moved far enough *or* the foil
  state flipped.

### 2.3 The "you are here" dot is where you were — HIGH

`TrackDraw.draw(…, marker=true)` puts the white dot on `lat[n-1]`, the newest *kept* point.
That point is up to one stride old: 5 s at the start of a session, 80 s after 85 minutes.
At 25 km/h that is a dot 550 m behind the rider, on the page whose stated job is "where am I
now". `MetricsEngine` receives a fix every second and keeps none of it outside the buffer.

### 2.4 The page cannot answer "how far out am I" — MEDIUM

The page's own comment says what it is for: *"where have I been and how far out am I"*. It
draws a normalized shape with no scale bar, no north mark, no wind, no launch point. The
caption is the odometer (distance *travelled*), which says nothing about distance *from
anywhere*. A track that is 300 m across and one that is 3 km across draw identically. The
data for every one of those reference marks is already on the watch: the box scale, the
first point, and the wind axis (`AppSettings.cfg` manual or `AutoWind.dirDeg`, with the same
`~` the Turns page uses for an estimate).

### 2.5 One bad fix stretches the box for the rest of the session — MEDIUM

Points enter the buffer after `speedPlausible` and `QUALITY_USABLE` gates, but nothing
checks the *position* against the previous kept point. The odometer has a teleport guard
(`Odometer.step`); the trail has none. A single 500 m jump — a first fix after a swim, a
multipath bounce under the cliffs at Garda — is kept, enters the bounding box, and the whole
session draws at a fraction of its size until the rider actually sails there. The halving
never removes it (it might, by parity, or it might not).

### 2.6 The buffer survives a discard — LOW

`SessionController` builds its `MetricsEngine` once (`SessionController.mc:44`) and nothing
resets `trackN` or `_trackStride`. After a save the app exits (`SummaryView.mc:440`), so
that path is clean; **Discard → Start** is not: the next session starts with the discarded
session's trail already on its map, at the discarded session's stride. Everything else in
the engine (detectors, records, history) carries over on that path too, so this is a
one-line symptom of a wider "new session, old engine" gap.

### 2.7 Small things

- **Aliasing at the caption.** `mapCaptionY` hangs the odometer off `cy + box/2`; on the
  live page `box` is computed from `fitRadius(dc, false, foilArc)`, so when the foil arc is on
  the map is smaller but the caption still sits at the box edge — correct, and the test
  covers it. No defect, noted because it is the first thing a reviewer will suspect.
- **Pen width 3 on 240 px MIP glass** (fenix 7S, the 8 Solars) is heavy for a 144 px box;
  `scaled()` exists for exactly this and the pen does not use it.
- **`Float` lat/lon is fine.** At 46° N a 32-bit float resolves ~0.6 m in latitude and
  better in longitude; the "~1 m" in the comment is right.

---

## 3. Suggestions

### 3.1 Fix the breadcrumb (no firmware risk, all of it measurable in the layout suite)

**A1 — Live marker from the live fix.** Keep `lastLat`/`lastLon` (two `Float`s) on every
usable tick in `MetricsEngine.tick`, draw the marker from them, and fold them into the
bounding box so the dot can never leave the square. Fixes 2.3 outright. Cost: 8 bytes and
two multiplies.

**A2 — A geometry-aware buffer.** Replace "every N ticks, halve when full" with:

- append when the planar distance from the last *kept* point is ≥ `D` metres (start with
  25 m), **or** when `flying` differs from the last kept point's state — so every takeoff
  and touchdown is a vertex and the tint stops being a coin toss;
- raise `TRACK_MAX` to 512 (three `Array`s of 512 is under 10 KB against 768 KB; the
  `PhoneLink` comment about memory was written for 128 and still holds);
- keep the halving as the overflow fallback, doubling `D` with it, so a six-hour session
  still fits.

At `D = 25 m` a jibe of 15–30 m radius gets two to four vertices instead of zero, a 1 km
reach gets ~40, and a two-hour, 25 km session uses ~500 points before the first halving.
`TrackTint.MAX_RUNS` (32) stays: at honest vertices it absorbs real flicker, not sampling.

**A3 — A teleport guard for the trail.** Reject a candidate point whose distance from the
last kept point implies more than the barrel's plausible speed over the ticks since; the
odometer already does this and the two should agree. Fixes 2.5.

**A4 — The reference marks a map is for.** Four cheap primitives, all authored at `REF_PX`
and read through `scaled()` like the rest of the page:

- a **scale bar**: the largest of 100 m / 200 m / 500 m / 1 km / 2 km that fits in a third
  of the box at the current scale, bottom-left of the box, `FONT_XTINY` label (it is a label,
  not a value — the floor rule allows it);
- a **launch ring**: hollow white circle at point 0. "Home" is the one fixed point of a
  session and it costs one `drawCircle`;
- a **wind arrow**: top-right of the box, pointing where the wind blows *to*, with `~` when
  the axis is an estimate, exactly as the Turns page labels it. Nothing else on the map is
  as useful to a wingfoiler, and it is free;
- an **N tick** at the top of the box, since north-up is a promise the page currently keeps
  silently.

**A5 — Optional: a follow mode.** A GCM setting `mapMode = fit | follow`. `fit` is the page
as it is. `follow` centres on the live fix at a fixed width (say 1 km across, chosen so a
reach fits) so the rider sees the last few reaches at a readable scale and the launch ring
tells the way home. This is the mode that actually answers "how far out am I" while sailing;
`fit` remains the right mode for the post-save Track page. Do this after A1–A4, not instead.

**A6 — Reset the engine per session.** `startSession` should start from a fresh
`MetricsEngine` (or `reset()` every buffer, the track included). Fixes 2.6 and the wider
carry-over.

**A7 — Make the rig honest.** Seed the screenshot track by pushing a real fixture track
(`fixtures/`) through the real `_trackTick`, so the shot is the page after two hours, not
after ten minutes. Add a map shot to the store set — there is none today — and add a test
that decimates a fixture with A2 and asserts the reach ends survive (a minimum vertex count
inside each turn window the fixture's golden file already lists).

### 3.2 Get the basemap back — as an experiment ladder, not a fourth attempt (issue #4)

The 0.9.1 code changed four things at once (2.1). Change one at a time, on the device, with
two instruments the last attempts did not have:

- `System.getSystemStats().usedMemory` / `.totalMemory` printed to CIQ_LOG immediately
  before every push, and again from the first timer tick after it;
- a **`Storage` breadcrumb**: write `mapPush = <step number>` before the push and clear it
  on the first successful tick. A kill that leaves nothing in CIQ_LOG still leaves that key
  in Storage, and the next launch can print "died at step N". That is how a crash a log
  cannot see becomes one it can.

The ladder, each step on the fenix 8, each with the instruments above:

1. `WatchUi.MapView`, empty, `setMapVisibleArea` around the current fix, pushed from the
   **start screen** menu — no recording session, no sensors. Does the watch show a map?
2. The same, pushed from the **session menu** while recording (session, sensor listener,
   logger all live). This isolates "native map + active recording".
3. Add **one** `MapPolyline` of the whole track, built once, *before* `pushView`, never in
   `onShow`.
4. Add the 32-run tint and the `Timer` refresh.
5. Swap `MapView` for `MapTrackView` — only to learn whether the class was the problem.

Whichever rung fails names the cause; whichever rung the design needs and survives is the
page. If step 2 fails and step 1 passes, the answer to #4 is a **post-save** map on the
summary stack (issue #4's own second bullet), which is worth having on its own.

If a native view survives, two constraints shape it:

- it should be `MapView` with an `onUpdate` override that calls `MapView.onUpdate(dc)` and
  then draws the odometer, the marker, the wind arrow and the **PAUSED banner** over the
  map — the documented overlay pattern, and the one thing the old design could not do. The
  forum reports of device crashes when drawing over `MapTrackView` are the reason to prefer
  `MapView`;
- the page stays `TrackDraw` on every product without `WatchUi has :MapView`, and the
  push/pop state machine 0.9.2 deleted comes back only for the products that have one.
  Budget that: it was a real source of bugs (`PageNav.mapShown`, `dropMap` on every exit
  path) and the reason the paused skip existed.

### 3.3 If the native view stays dead: a *ground*, not a basemap

The rider does not need tiles; he needs to see water against land. Two options, in order of
cost:

- **A shoreline polyline from the phone.** The iOS app knows the spot (`Spots`, auto-cluster)
  and already has the companion link (ADR-013, a card, 192 B). A simplified shoreline of the
  spot — 100–200 points, ~1–2 KB as packed integers — sent once per spot, kept in `Storage`,
  drawn in `Ink.dim()` under the breadcrumb by the same `TrackDraw` projection. It is
  testable in the layout suite, works on every product, and is what "map background" means
  at a 273 px box. It needs a shoreline source on the phone (OpenStreetMap coastline via a
  one-off query, or a hand-traced polygon per spot in the app); that is the real cost, and it
  is a phone task, not a watch one.
- **A pre-rendered tile from the phone** (issue #4's third bullet). A 10 KB image cannot be
  handed to the watch as a bitmap: there is no API to build a `BufferedBitmap` from bytes,
  so it would be drawn pixel by pixel into one once per spot. Feasible, heavy, and it
  answers the question worse than the polyline does at this size. Not recommended.

---

## 4. Recommended order

1. **A1 + A3 + A6** — one afternoon, no design decisions, three real defects gone (the stale
   marker, the teleport, the discarded session's trail).
2. **A2 + A7** — the decimator and the honest screenshot. This is the change that makes the
   page a track instead of a zigzag after the first hour, and the test that keeps it one.
3. **A4** — scale bar, launch ring, wind arrow, N. After this the page answers its own
   question with no map under it, which is the point at which issue #4 can be judged on
   what it would *add* rather than on what the page lacks.
4. **3.2, steps 1–2** — two device experiments with instruments, one evening on the water or
   the balcony. Then decide between 3.2 (live native map), the post-save-only map, and 3.3.
5. **A5** only if riders ask for it after 3.

Everything in 1–3 is inside `TrackDraw`, `MetricsEngine._trackTick`, `RecordingView.
drawMapPage` and the tests that already measure them, and none of it touches the firmware.
