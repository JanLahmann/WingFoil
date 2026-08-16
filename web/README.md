# WingFoil Lab — web

A zero-server web app that runs the **actual `wingfoil_lab` Python engine** in the browser
via [Pyodide](https://pyodide.org/) (CPython compiled to WebAssembly). Drop a `.fit` file,
get the full session analysis: flights, GP3S speed records, wind axis, turns with outcomes,
flight ends, takeoffs. Keep the sessions you care about in a private on-device **library**,
and watch the **records and trends** across them. Installable as a PWA and usable offline.

**There is no third implementation of the analysis.** The browser imports
`lab/src/wingfoil_lab` unchanged and calls the same `goldens.analyze()` +
`goldens.build_golden()` that `lab/tools/make_goldens.py` calls. The `golden` block in the
downloadable JSON is byte-identical to `fixtures/goldens/<stem>.expected.json` for the same
file — verified against all 13 corpus fixtures (see *Verification* below).

```
web/
├── index.html                  page shell: three views (analyze / library / trends)
├── manifest.webmanifest        PWA metadata
├── sw.js                       service worker: app-shell precache + Pyodide runtime cache
├── icons/                      copied from brand/ — nothing is hotlinked outside web/
├── css/tokens.css              GENERATED from design/tokens.json — do not edit
├── css/style.css               dark styling + the data-viz palette (reads the tokens)
├── js/app.js                   file intake, view routing, save-to-library, SW updates
├── js/rpc.js                   the one channel to the worker (request/response by id)
├── js/worker.js                Pyodide worker — loads the runtime + the lab, runs the pipeline
├── js/render.js                summary tiles and tables; calls the figures
├── js/session.js               the interactive session view: track map + speed strip, the
│                               playhead they share, layer chips, zoom, marker popovers
├── js/viz.js                   drawing primitives both figure files share: palette, SVG
│                               helpers, the marker vocabulary, formatters, tooltip
├── js/tokens.js                GENERATED from design/tokens.json — do not edit
├── js/store.js                 OPFS storage, with an IndexedDB fallback
├── js/library.js               library view: rows, open, delete, per-session + zip export
├── js/trends.js                records table + inline-SVG trend charts
├── js/icu.js                   optional intervals.icu panel
├── lab_bundle/
│   ├── web_entry.py            hand-written glue: FIT bytes -> analysis JSON
│   ├── library.py              hand-written glue: digests, dedupe, records, trends, zip
│   ├── wingfoil_lab/           GENERATED copy of lab/src/wingfoil_lab — do not edit
│   ├── FILES.json              load list for the worker (HTTP has no directory listing)
│   └── MANIFEST.json           source hashes, for the staleness check
├── tools/bundle_lab.py         regenerates lab_bundle/wingfoil_lab
├── tools/verify_web_entry.py   headless checks: golden parity + no-GPS regression
├── tools/verify_library.py     headless checks: dedupe, digests, records, trends, zip
├── tools/make_presentation_goldens.py
│                               writes fixtures/presentation/ from the analysis goldens
├── tools/verify_presentation.py
│                               headless checks: marker/filter counts vs those goldens
└── .nojekyll                   GitHub Pages: serve files verbatim
```

## The one architectural rule

**The web app never grows its own numeric logic in JavaScript.** Aggregation, dedupe keys,
record winners, trend series, even the y-axis domains of the trend charts are computed in
Python inside the worker, where pandas is already loaded. JavaScript stores bytes,
orchestrates and renders JSON.

Concretely: if you want a number the UI does not yet show, it goes into
`lab_bundle/library.py` and comes out through `js/rpc.js`. The only arithmetic in the JS is
SVG coordinate placement and adding up file sizes for the storage indicator.

This holds for the interactive session view too, which is where it is easiest to break. The
playhead, the layer chips, the time-axis zoom and the marker popovers in `js/session.js` do
no analysis: a popover's rows are fields of the analysis document read out verbatim, the
scrubber's readout is the values of the sample nearest the playhead, and the only numeric
work is placing shapes, the binary search from a time to that sample, and the interpolation
that slides the map dot between two fixes. If an interaction needs a number the document
does not carry, the number goes into `lab_bundle/`.

## Privacy

**Nothing leaves the browser.** There is no backend, no upload endpoint, no analytics, no
cookies. The FIT file is read with the File API, handed to a Web Worker, and analyzed inside
the WebAssembly sandbox. Saved sessions live in this browser's private per-origin storage.
The only outbound requests the page ever makes are:

| Request | When | Why |
|---|---|---|
| `cdn.jsdelivr.net/pyodide/v0.28.3/…` | first load | the Python runtime + numpy/pandas (~12 MB, then browser- **and** service-worker-cached) |
| `pypi.org` / `files.pythonhosted.org` | first load | the `fitdecode` wheel (pure Python, ~120 KB) |
| same-origin `web/…` | first load, then on update | the app shell and `lab_bundle/*.py`, precached by the service worker |
| `intervals.icu/api/v1/…` | only if you use the intervals.icu panel | your own activity list / FIT |

**The service worker adds no request of its own.** It stores responses the page was already
fetching, and only from those three origins plus this site's own. intervals.icu is
explicitly excluded from caching — a cached activity list is not something a privacy-first
app should leave lying around. There is still no cookie, no analytics, no beacon, and no
`localStorage` beyond the intervals.icu key.

The intervals.icu API key is stored **only in this browser's `localStorage`** and is attached
**only** to requests to `intervals.icu`. It is never sent to the site's host and never appears
in a URL. "Forget key" deletes it.

| Data | Where it lives | How to delete it |
|---|---|---|
| Saved sessions (original FIT + analysis JSON) | OPFS, or IndexedDB where OPFS is unavailable | *Delete* on the row, or clear this site's data |
| The library index | the same place, as `index.json` | same |
| intervals.icu API key | `localStorage` | *Forget key* |
| Pyodide runtime, app shell | HTTP cache + service-worker `CacheStorage` | clear this site's data |

Clearing site data, or using a private window, wipes all of it. Nothing is synced or backed
up anywhere — use *Download all (.zip)* if you want a copy you own.

## Running it locally

```bash
cd web
python3 -m http.server 8765
# open http://127.0.0.1:8765/
```

A plain static server is enough — no build step, no bundler, no npm. The app is plain ES
modules; `js/worker.js` is a **module worker**, which needs a real HTTP origin, so
`file://` will not work.

> **While developing, the service worker will serve you yesterday's JavaScript.** Same-origin
> files are answered from the cache first and refreshed in the background, which is right for
> users and infuriating for you: an edit to `js/store.js` will not take effect until the
> second reload. Tick **DevTools → Application → Service Workers → *Bypass for network***
> (or *Update on reload*) before you start, or bump `VERSION` in `sw.js`. Symptom to
> recognise: the page behaves exactly as it did before your edit, with no console error.

## Deploying to GitHub Pages

Everything under `web/` is the site. Nothing needs compiling.

**Option A — publish the `web/` folder from a branch.** GitHub Pages can only publish from
the repo root or `/docs`, so push the folder to a `gh-pages` branch root:

```bash
git subtree push --prefix web origin gh-pages
```

Then *Settings → Pages → Source: Deploy from a branch → `gh-pages` / `(root)`*.

**Option B — GitHub Actions.** Upload `web/` as the Pages artifact
(`actions/upload-pages-artifact` with `path: web`, then `actions/deploy-pages`). This also
gives you a natural place to run the staleness check below in CI.

Notes:
- `.nojekyll` is required: without it Jekyll may drop files and mangle the `lab_bundle/`.
- No COOP/COEP headers are needed — this build of Pyodide does not use threads.
- Everything is same-origin except the Pyodide CDN and PyPI, so no CORS setup is needed.

## Refreshing `lab_bundle/` — do this after every lab change

`lab_bundle/wingfoil_lab/` is a **generated copy**. Editing it is always wrong; edit
`lab/src/wingfoil_lab/` and re-run the bundler:

```bash
cd web
python3 tools/bundle_lab.py            # copy lab sources + rewrite MANIFEST.json / FILES.json
python3 tools/bundle_lab.py --check    # exit 1 if the bundle is stale (use this in CI)
```

> **Staleness warning.** The web app has no way to notice that the bundle is out of date —
> it will happily serve last week's engine and produce numbers that no longer match the
> goldens. If `lab/` changed and `bundle_lab.py` did not run, the site is wrong. `--check`
> is the guard; run it in the same job that runs `pytest`.

`lab_bundle/web_entry.py` and `lab_bundle/library.py` are hand-written and are never touched
by the bundler — it only lists them in `FILES.json` (see `GLUE` in `tools/bundle_lab.py`).

## The session library

Press **Save to library** on a finished analysis and two files are written to this browser's
private storage: the original FIT, byte for byte, and the full analysis document. Opening the
session again parses the stored document and re-renders it — **no FIT decode, no Pyodide
run**, so the library keeps working with the CDN unreachable and opens instantly.

**Where it lives.** [OPFS](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
(the Origin Private File System) when the browser has it, with **IndexedDB** as a
feature-detected fallback — the probe is a real write, because some engines expose OPFS with
only the worker-side sync API and no `createWritable()`. Either way it is private to this
origin, not synced, not backed up, and invisible to every other site. The row under the
library heading shows what the library occupies and what `navigator.storage.estimate()` says
the whole site is using.

**Deleting.** *Delete* on a row (with a confirm) removes both files and the index entry.
**Clearing this site's data, or browsing in a private window, deletes everything.**

**Dedupe.** The project's session-identity rule, unchanged: a start within **±60 s** *and* a
duration within **±60 s** of an existing entry is the same session. Both bounds are
inclusive. The key is computed in Python (`library.digest`), the comparison too
(`library.dedupe_match`) — so the browser and the rest of the repo cannot drift apart. A hit
is never resolved silently: you are told which stored session matched and by how much, and
asked whether to replace it. Answering no leaves the library exactly as it was.

**Getting your data out.** Three ways, none of which need a server:

| | What you get |
|---|---|
| **Download all (.zip)** | every original FIT + every `*.analysis.json` + `index.json`, built by CPython's own `zipfile` in the worker (there is no JS zip library in this app) |
| `.fit` on a row | the original file, exactly as it was dropped |
| `.json` on a row | that session's analysis document, whose `golden` block is the fixture golden |

The intervals.icu panel feeds the same path: fetch → analyze → **Save to library**.

## Records & trends

One Python call (`library.aggregate`) over the stored digests produces the whole view.

- **All-time records** — every GP3S kind (best 2 s … best 1 NM, alpha 500) with the value,
  the session and the date. Ties go to the earlier session: the record was set then.
  *Show the window* opens that session with **that record's exact window** marked in orange
  (the effort ink, one token for both apps) on the track and on the speed strip — the provenance is already in every analysis document
  under `records.windows`, so nothing is recomputed to draw it. Best 5×10 s marks all five.
- **Session by session** — on-foil %, longest flight, turn success rate, average pumps to
  takeoff, and turn success split by the tack the turn was *entered* on. Oldest first; click
  a point to open that session. A **gap in a line is a missing measurement, not a zero** —
  a session with no wrist accelerometer has no pump number, and drawing that as 0 would be a
  lie.
- **Totals** are weighted the way the metric means them: the library's on-foil share is total
  foil time over total on-water time (recovered from each session's own denominator, not from
  elapsed time, which would under-report it by ~19 points), and the turn rate is successes
  over turns.

Charts are inline SVG in `js/trends.js`, drawn with the primitives `js/viz.js` exports —
same surface, same grid ink, series-1 blue and its tint, direct end-labels instead
of a colour key, and a dashed second line so the port/starboard split survives a
colour-vision check without a second hue.

## Phone layout

The app is used on the beach, on a phone, so 390 × 844 is a first-class target rather than a
narrow-window afterthought. Four rules, all of them in `css/style.css`, `js/session.js` and
`js/viz.js`:

**1. The page never scrolls sideways.** Wide content scrolls inside its own box or restacks;
`body { overflow-x: hidden }` is the guard rail, not the mechanism. `main > div` uses
`grid-template-columns: minmax(0, 1fr)` because a grid item's automatic minimum is its
*min-content* width, which is the usual way a wide table pushes a whole page over.

**2. Figures are drawn at their container's real width.** Every inline SVG is `width: 100%`
over a `viewBox`, so the viewBox width *is* the scale factor. A 1100-unit chart in a 350 px
column renders its 10.5 px axis labels at 3.3 px. So `viz.figureWidth(host)` measures the
slot and the figure is drawn at that many user units — scale 1, type at its stated size, on
a phone and on a desktop alike. Below 640 units `viz.isNarrow()` also switches the
geometry: smaller gutters, fewer ticks, no rotated axis titles (there is no room beside a
34-unit gutter), bare units instead, and the trend charts' direct end-labels move from the
right gutter to above the plot. Because the figures now depend on their width, `app.js`
redraws them on a debounced `resize` — that is what makes a rotation come out right.

**3. Two of the tables restack into cards.** Turns (16 columns × 34 rows) and flight ends
stay tabular and scroll sideways inside `.table-scroll`: as cards they would be a mile of
page. The library rows and the records table are *browsed* one row at a time, so below
760 px `table.stack-sm` turns each `<tr>` into a card and each `<td>` into a labelled row,
reading its label from `data-th` — written by the same code that writes the `<th>`, so the
two cannot drift.

**4. Touch, not hover.** Every button is ≥ 44 px tall below 760 px — the legend chips
included, since they are the map's filter and not decoration — `@media (hover: none)`
neutralises the hover styles so they do not stick after a tap, and inputs are 16 px because
Safari zooms the whole page when a focused field is smaller. The file picker is a real
`<label for>` over the input, not a button calling `input.click()` — **iPhone Safari has no
drag & drop, so the picker is the only intake path there** and it must not depend on JS.

Safe areas: `viewport-fit=cover` plus `env(safe-area-inset-*)` on every edge chrome (topbar
top and sides, `main`, the footer's bottom), so the installed PWA — which declares
`apple-mobile-web-app-status-bar-style: black-translucent` — clears the notch and the home
indicator. `100dvh`, never `100vh`: on iOS `100vh` is the *largest* viewport and overflows.

Verified with headless Chrome under mobile emulation at 375 × 667, 390 × 844 and 430 × 932
(`document.scrollingElement.scrollWidth === innerWidth` on all three views, with the
`overflow-x` guard rail temporarily off so it cannot mask anything). **Real iOS Safari has
not been driven automatically** — Chrome's emulation is not WebKit; the WebKit-specific
choices above are made from the documented behaviour, not from a measured device.

## PWA / offline

`manifest.webmanifest` plus `sw.js` make the app installable and usable with no network.

- The **app shell** (HTML/CSS/JS/icons and every file listed in `lab_bundle/FILES.json`) is
  precached at install. The lab module list is read from `FILES.json` rather than hard-coded,
  so adding a lab module never needs an edit in `sw.js`.
- The **Pyodide CDN and the PyPI wheel** are runtime-cached, cache-first: ~12 MB that never
  changes for a pinned version. This is the whole offline story.
- **Updates are offered, never applied behind your back.** A swap mid-analysis would reload
  the page and throw the result away, so a new worker waits and a banner appears with
  *Reload to update*. Bump `VERSION` in `sw.js` whenever anything under `web/` changes; the
  old caches are deleted on activate. **This is not optional for a CSS or JS edit**: the
  shell is served cache-first, so without the bump every already-installed client keeps the
  old stylesheet indefinitely. Current value: `v2` (the phone-layout pass).

Icons live in `web/icons/`, copied from `brand/` (`icon-tile-*` for the normal icon,
`icon-square-*` full-bleed for the maskable one). Nothing outside `web/` is referenced.

## Verification

Five checks, none of which needs a browser:

```bash
cd /path/to/WingFoil

# 0. the bundle is not stale (exit 1 if lab/ moved on without it)
python3 web/tools/bundle_lab.py --check

# 1. web_entry: the bundle reproduces the goldens exactly, and a track with no GPS fixes
#    still produces a serializable document (analyze_json uses allow_nan=False)
lab/.venv/bin/python web/tools/verify_web_entry.py

# 2. library: dedupe edge cases, digest fidelity, records, trends, the zip export
lab/.venv/bin/python web/tools/verify_library.py           # ~35 s; --fast skips the corpus

# 3. JS syntax
cd web && for f in js/*.js sw.js; do node --check "$f" || exit 1; done

# 4. the lab itself is still green
cd lab && uv run pytest -q
```

`tools/verify_web_entry.py` is the whole of check 1: the golden spot-check that used to be
a heredoc here, plus the position-less-track regression (a Doppler-only source has an
all-NaN projection; the view must degrade to `hasPositions: false` rather than emit a NaN
that takes the entire analysis down).

Expected numbers for that CIQ session: **30 jibes / 0 tacks**, outcomes **9 flew through / 9
touchdown / 12 fell in**, **23 flights**, 12.764 km, wind from 36°, 60 % on foil.

`tools/verify_library.py` covers everything the library and the trends view compute, in five
groups (**153 assertions**, all green at the time of writing — 30 / 8 / 28 / 49 / 30 / 8):

| Group | What it pins down |
|---|---|
| 1. dedupe | ±59 s matches on either axis, ±61 s does not, exactly 60 s does; a missing start never matches; the *closest* candidate wins so a replace lands on the right recording |
| 1b. spot names | the corpus filename convention, plus filenames that ignore it |
| 2. digest fidelity | every digest field equals the golden it was projected from, and the port/starboard split is checked against a hand count off the golden's own turn rows: **port 14 entries / 2 held (14.29 %), starboard 16 / 2 (12.5 %)** for the CIQ session, summing to the engine's own 30 counted / 4 held |
| 3. records | the winner of every kind, over all 13 corpus FITs, matched independently *and* named: best 2 s **14.99 kn on 2026-08-01**, best 1 NM **11.451 kn on 2026-08-05**, alpha 500 **11.994 kn on 2026-08-05**; best hour is dropped because nobody set one; every record carries a window that lies inside its session |
| 4. trends | one point per session per line, indices and ids aligned with the session list, oldest first, values equal to the digests in order, and pumps `null` (not 0) for the accelerometer-less sessions |
| 5. zip export | the archive unzips, FIT bytes survive byte-for-byte, JSON is deflated, an aborted export cannot leak into the next one |

### Manual browser test checklist

1. `cd web && python3 -m http.server 8765`, open <http://127.0.0.1:8765/>.
2. **Cold boot.** The chip top-right should turn into `engine 0.3.0 · pyodide 0.28.3` within
   ~20 s on a warm connection. Open DevTools → Console: there must be no errors, only
   Pyodide's own "Loading/Loaded micropip, numpy, pandas…" lines.
3. **Drop** `fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` on the
   drop zone. The progress list should walk *runtime → wingfoil_lab → parsing → analyzing*
   and the page must stay responsive the whole time (the analysis is in a worker; scrolling
   must not stutter).
4. **Check the numbers** against the golden above: 23 flights, 60 % on foil, 12.76 km,
   Turns 30, Outcomes 9/9/12, wind 36°, best 2 s 11.36 kn. Badges: `wingfoil`,
   `CIQ dev fields`, `accel`, `HR`.
5. **Map.** North-up track; grey off-foil line with teal foiling segments on top (the phase
   tints, the same two the iOS map uses); small chevrons showing which way he went; numbered
   markers — green discs / amber triangles / red crosses / grey hairline crosses for
   bear-aways / hollow squares on the *same* colour ladder for straight-line flight ends (a
   glide-out is a hollow green square, not a category of its own) / blue takeoff arrows /
   red hollow u-turns for failed attempts / cyan drops where the barometer saw the wrist go
   under; wind arrow + scale bar. Hovering a marker
   shows a tooltip, tapping one opens a popover of that event's facts. The legend counts
   must match the tiles. (A file with no GPS fixes at all must show *"No GPS positions in
   this file"* in the map slot and still render every other section —
   `tools/verify_web_entry.py` covers this headlessly.)
6. **Speed strip.** Blue Doppler line over the paler positional line, teal flight bands,
   purple pumping bands (one per pumping attempt — 37 on the CIQ file, the number the
   presentation golden pins), the same marker numbers as the map. Moving the pointer across it
   shows a crosshair with the time and both speeds.
6b. **The interactions** (`js/session.js`), which is what the two figures are *for*:
   - **Scrub.** Drag the speed strip: a dashed rule follows the pointer, a dot slides along
     the track at the same instant, and the readout above the strip names that instant once
     — clock time, elapsed, both speeds, flying or off foil. Drag on or near the track
     instead: the same three move together. A press well away from the track does nothing
     rather than yanking the playhead somewhere unrelated.
   - **Layer chips.** Eleven of them, worded by `design/tokens.json` and therefore the same
     words the iOS legend uses: flying · off foil · pumping · direction · best 2 s (the
     effort chip is named after the window it is showing) · flew through · touchdown · fell
     in · course change · takeoff · splash. Every chip hides its category on the map *and*
     in the chart — `direction` takes the chevrons with it and leaves the route. A chip with
     nothing to show stays as a subdued caption, not a dead button. "Show all" returns.
   - **Zoom.** Wheel or trackpad over the plot (or a two-finger pinch on a touch screen)
     zooms the time axis about the pointer; markers and bands outside the window are not
     drawn; the axis switches to m:ss; "Reset zoom" or a double-click restores it. Scrubbing
     still works while zoomed.
   - Everything above is transient: it belongs to the document on screen and is not saved.
7. **Tables.** 34 turn rows (30 counted + 4 rejected), 23 flight-end rows. Turn #1 at
   08:03:36 local, jibe, fell in.
8. **Takeoffs.** With the CIQ file: attempts 37, successes 23 (62 %), avg pumps 9.0, total
   strokes 1341. Now drop a native windsurf FIT from `fixtures/sessions/windsurf-native/`:
   the pump rows must disappear and be replaced by the "no wrist accelerometer" note.
9. **.zip.** Zip that CIQ FIT and drop the zip — identical output, file line shows the inner
   name.
10. **Bad input.** Drop any non-FIT file: a red panel says
    `not a FIT file (missing .FIT signature)`; dropping a good file afterwards still works.
11. **Download analysis JSON** and diff its `golden` block against the fixture golden — they
    must be identical.
12. **Reload.** Second boot should be much faster (the runtime is in the HTTP cache).
13. **intervals.icu panel** (optional): paste a key, *List recent activities*. A CORS failure
    is the expected outcome and must produce the friendly export-by-hand instructions, not a
    stack trace. *Forget key* must clear `localStorage`.
14. **Save to library.** Press it: the button becomes *Saved*, and the Library tab shows a
    count. Analyze the same file again under a different filename and press save — you must
    get the duplicate prompt naming the stored session and the two deltas, not a second row.
15. **Library.** Row values must match the tiles for that session. *Open* re-renders it
    instantly and the save button reads *Already in the library*. Turn off the network
    entirely and *Open* again — it must still work, because nothing is fetched. `.fit` and
    `.json` download; *Download all (.zip)* produces an archive that unzips.
16. **Records & trends.** Every record row names the session it came from. *Show the window*
    jumps to that session with an orange band on the speed strip and an orange overlay on
    the track, plus a "Showing …" note with a *Clear* button. A session with no accelerometer
    must leave a **gap** in the pumps chart, not a point at zero.
17. **Delete.** Confirm, and the row, the files and the storage figure all go down. The
    trends view recomputes (a record that belonged to the deleted session disappears).
18. **Phone.** DevTools → device toolbar → iPhone 15 Pro (390 × 844). Walk all three views:
    nothing may scroll the *page* sideways (`document.scrollingElement.scrollWidth` must
    equal `innerWidth`); the turns table scrolls inside its own box; the library rows and
    the records table are cards, not rows; the map and the speed strip are drawn at ~332
    units wide with legible axis labels. **Tap *Choose a file…*** — it is a `<label>`, and
    on a real iPhone it is the only way in, because Safari has no drag & drop. Rotate: the
    figures must redraw at the new width, not stretch.
19. **PWA.** DevTools → Application: the manifest parses, the icons resolve, the service
    worker is activated with a `wingfoil-shell-*` and a `wingfoil-runtime-*` cache. Go
    offline and reload — the app boots and the library opens. Edit `VERSION` in `sw.js`,
    reload twice: the *"A new version … Reload to update"* banner must appear, and pressing
    it must reload into the new version.

## Known limitations

- **Times are shown in your browser's timezone**, not the session's. The FIT's local offset
  lives in the trailing `activity` message, which `parse.py` does not retain, and re-reading
  a 6 MB FIT just for that is not worth the seconds in WASM.
- First load downloads ~12 MB (Pyodide + numpy + pandas). It is cached afterwards, but the
  very first analysis on a cold cache takes ~25 s end to end for a 90-minute session.
- The intervals.icu integration will normally be blocked by CORS. That is not fixable from a
  zero-server app; the panel detects it and explains the manual export path.
- No pan/zoom on the **map** — it is a fixed, aspect-correct plot, like
  `lab/tools/plot_turns.py`. The *speed strip* does zoom its time axis (wheel or pinch), and
  the map answers by moving the shared playhead rather than by changing scale.
- **The library is device-local and unsynced.** Two browsers, two libraries. There is nowhere
  for a zero-server app to sync to, and inventing one would break the privacy promise. The
  zip export is the migration path.
- The bulk zip export holds the whole archive in memory while it is being built, so a library
  of many hundreds of large FITs may be better exported row by row.
- Trends read the per-session **digests**, not the full documents — loading fifty 200 KB
  analyses to find one maximum would be silly. The digest is produced by the same Python from
  the same document, and `tools/verify_library.py` checks every field of it against the
  goldens.
- The dedupe rule cannot recognise a session whose start timestamp is missing entirely; such
  a file is always stored as a new entry rather than risk merging two different sessions.
