# CleanJibe — web

The site at **cleanjibe.org**: a project homepage and a zero-server analyzer that runs the
**actual `wingfoil_lab` Python engine** in the browser
via [Pyodide](https://pyodide.org/) (CPython compiled to WebAssembly). Drop a `.fit` file,
get the full session analysis: flights, GP3S speed records, wind axis, turns with outcomes,
flight ends, takeoffs. Keep the sessions you care about in a private on-device **library**,
and watch the **records and trends** across them. Installable as a PWA and usable offline.

**There is no third implementation of the analysis.** The browser imports
`lab/src/wingfoil_lab` unchanged and calls the same `goldens.analyze()` +
`goldens.build_golden()` that `lab/tools/make_goldens.py` calls. The `golden` block in the
downloadable JSON is byte-identical to `fixtures/goldens/<stem>.expected.json` for the same
file — verified against all 15 corpus fixtures (see *Verification* below).

```
web/
├── index.html                  the PROJECT HOMEPAGE (cleanjibe.org/) — what CleanJibe is,
│                               the WingFoil watch app, the iPhone app, this analyzer. No JS.
├── app/index.html              the ANALYZER, "CleanJibe Lab" (cleanjibe.org/app/): page
│                               shell, three views (analyze / library / trends)
├── social-card.png             the 1200x630 Open Graph tile both pages point at, by
│                               ABSOLUTE URL (scrapers do not resolve relative ones)
├── tools/social_card.html      the tile's source; rasterize with headless Chrome to
│                               regenerate it — see "The social card" below
├── app/manifest.webmanifest    PWA metadata — beside the app so `scope`/`start_url` are
│                               /app/ and an installed icon opens the analyzer
├── sw.js                       service worker: app-shell precache + Pyodide runtime cache.
│                               Stays at the ROOT: its default scope is its own directory,
│                               so one registration covers homepage and app alike.
├── icons/                      copied from brand/ — nothing is hotlinked outside web/
├── css/tokens.css              GENERATED from design/tokens.json — do not edit
├── css/style.css               dark styling + the data-viz palette (reads the tokens)
├── css/home.css                the homepage's own layout, layered on top of style.css
├── js/app.js                   file intake, view routing, save-to-library, SW updates
├── js/rpc.js                   the one channel to the worker (request/response by id)
├── js/worker.js                Pyodide worker — loads the runtime + the lab, runs the pipeline
├── js/render.js                summary tiles and tables; calls the figures
├── js/session.js               the interactive session view: track map + speed strip, the
│                               playhead they share, layer chips, pan/zoom on both figures,
│                               marker popovers
├── js/viz.js                   drawing primitives both figure files share: palette, SVG
│                               helpers, the marker vocabulary, formatters, tooltip
├── js/tokens.js                GENERATED from design/tokens.json — do not edit
├── js/store.js                 OPFS storage, with an IndexedDB fallback
├── js/library.js               library view: rows, open, delete, per-session + zip export
├── js/rider.js                 the "whose session is this?" prompt, asked on the way in
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
│                               headless checks: marker/filter counts and the flight-count
│                               invariants, vs those goldens
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
playhead, the layer chips, the time-axis zoom, the map's camera and the marker popovers in
`js/session.js` do no analysis: a popover's rows are fields of the analysis document read out
verbatim, the scrubber's readout is the values of the sample nearest the playhead, and the
only numeric work is placing shapes, the binary search from a time to that sample, and the
interpolation that slides the map dot between two fixes. The map's zoom is the same kind of
thing — one multiply and one offset on coordinates the document already carries, with the
figure redrawn from them; it reports no distance and rounds no number. If an interaction
needs a number the document does not carry, the number goes into `lab_bundle/`.

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
# open http://127.0.0.1:8765/       the project homepage
# open http://127.0.0.1:8765/app/   the analyzer
```

> The site has two documents. `/` is the project homepage (static HTML, one extra
> stylesheet, no JavaScript at all); `/app/` is this analyzer. Everything the analyzer
> loads — `css/`, `js/`, `icons/`, `example/`, `lab_bundle/` — stays at the site root and is
> reached with `../`, so the two pages share one copy of the aesthetic and one service
> worker. `js/app.js` resolves the example FIT and `sw.js` against `import.meta.url` rather
> than against the document, which is what lets the page move without moving them.

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

## The social card

Both documents carry a full Open Graph / Twitter set, and both point at the same tile:

```
https://cleanjibe.org/social-card.png     1200 x 630, 66 KB
```

Two things about those tags are load-bearing and easy to get wrong:

- **`og:image` must be absolute.** Slack, WhatsApp, iMessage, Mastodon and X fetch the
  tag's value verbatim; none of them resolve it against the page. A relative path does not
  produce a broken image, it produces *no preview at all*, which is why this is worth a
  paragraph. The same goes for `og:url`.
- **`og:image:width` / `:height` are how a scraper decides to render large.** Without them
  some clients wait for the image before laying the card out, and some fall back to the
  small square. With `twitter:card=summary_large_image` beside them, every client that
  matters renders the wide tile.

The tile is a static PNG rather than anything generated: it is one image for one site, and
a build step to produce one file would cost more than it saves. Its source is
`tools/social_card.html` — the homepage's own hero motif, the same geometry and the same
`design/tokens.json` colours, over the site's surface. To regenerate:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu \
  --force-device-scale-factor=1 --window-size=1200,630 \
  --screenshot=/tmp/card.png file://$PWD/web/tools/social_card.html
python3 -c "from PIL import Image; \
  Image.open('/tmp/card.png').convert('RGB') \
       .quantize(colors=256).save('web/social-card.png', optimize=True)"
```

The quantize step is what takes it from 187 KB to 66 KB; the tile is flat surfaces, a
gradient and four accent hues, so a 256-colour palette with Floyd–Steinberg dither is
visually identical (checked at 2x on the gradient, no banding). Keep it under ~200 KB —
some scrapers refuse to fetch anything larger, and every one of them is on a phone.

Note the tile is **not** in the service worker's `APP_SHELL`. Scrapers do not run service
workers, and an offline visitor has no use for it.

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

**Whose session is it.** The analyzer answers for any `.fit` that reaches it, and two of
them are not the reader's own afternoon: the **bundled example**, and a recording a **friend
sent** — scrubbed of every identifier by the iOS share, so nothing in the file says who rode
it and nothing could. Saved unattributed, either one joins the all-time records and bends
every trend line, and a fast afternoon of somebody else's becomes a personal best that no
later correction can un-set. So the question is asked on the **Save** press, before anything
is written: *Whose session is this?* — **Mine** (preselected, one tap) or **A friend's** plus
a name, with the names already in the library offered as chips so the second file from the
same friend lands on the same spelling as the first. The example answers for itself and is
never asked about. Dismissing the prompt saves nothing.

Both kinds are stored, listed and opened like any other session — badged *Example* or with
the rider's name in the library row — and both are **counted in nothing**: the exclusion is
one condition, `library.counts_towards_records`, applied in `library.aggregate` only, so the
records table, the totals block and every trend chart honour it without three call sites
remembering to. Entries saved before this existed carry neither field, and a missing field
reads as *mine, not example* — nobody's stored library changes meaning. (Same design as the
iOS app's `LibraryStore.clause`; the stored-entry schema went to 2 with it.)

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
- **What counts** — the reader's own sessions. The bundled example and anything a friend
  rode are excluded (see *Whose session is it* above); a library made only of those says so
  instead of drawing a chart of nothing.
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
narrow-window afterthought. Five rules, all of them in `css/style.css`, `js/session.js` and
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

**5. A gesture the browser can also claim is a gesture you will lose.** Two rules, both in
`js/session.js`. *One:* `touch-action` is latched when the **first** finger lands, so it can
never say "one finger scrolls the page, two fingers pinch the figure" — the second finger's
own `touchstart`/`touchmove` say it instead, with `preventDefault` (`lockTwoFingerScroll`).
Without that the page slides under a pinch and the gesture arrives as a `pointercancel`.
*Two:* nothing that a finger is touching may move. The playhead readout appears on the first
touch, so it lives below the figures (see above), and every zoom step redraws the strip, so
the pointer bookkeeping and the `pointermove`/`pointerup` listeners are on `window` and at
module scope — the element the gesture began on is gone by the second move.

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
  old stylesheet indefinitely. Current value: `v14` (the CleanJibe rename, which changed both
  page shells).

The worker precaches **both** documents — `/` and `/app/` — and its offline navigation
fallback picks between them by path, so an offline deep link to `/app/#/library` gets the
analyzer's shell and not the front door.

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
groups (**156 assertions**, all green at the time of writing — 30 / 8 / 31 / 49 / 30 / 8):

| Group | What it pins down |
|---|---|
| 1. dedupe | ±59 s matches on either axis, ±61 s does not, exactly 60 s does; a missing start never matches; the *closest* candidate wins so a replace lands on the right recording |
| 1b. spot names | the corpus filename convention, plus filenames that ignore it |
| 2. digest fidelity | every digest field equals the golden it was projected from, and the port/starboard split is checked against a hand count off the golden's own turn rows: **port 14 entries / 2 held (14.29 %), starboard 16 / 2 (12.5 %)** for the CIQ session, summing to the engine's own 30 counted / 4 held |
| 3. records | the winner of every kind, over all 15 corpus FITs, matched independently *and* named: best 2 s **14.99 kn on 2026-08-01**, best 1 NM **11.451 kn on 2026-08-05**, alpha 500 **11.994 kn on 2026-08-05**; best hour is dropped because nobody set one; every record carries a window that lies inside its session |
| 4. trends | one point per session per line, indices and ids aligned with the session list, oldest first, values equal to the digests in order, and pumps `null` (not 0) for the accelerometer-less sessions |
| 5. zip export | the archive unzips, FIT bytes survive byte-for-byte, JSON is deflated, an aborted export cannot leak into the next one |

### Manual browser test checklist

0. **The homepage.** `cd web && python3 -m http.server 8765`, open
   <http://127.0.0.1:8765/>. Static HTML: the hero, the three cards, the vocabulary list,
   the track motif in the outcome colours. The wordmark reads **CleanJibe**; the two app
   cards keep their own names (*WingFoil for Garmin*, *WingFoil for iPhone*), because the
   site is branded and the apps are not renamed. Both *Open the analyzer* buttons must land
   on `/app/`, and the analyzer's own wordmark must come back here.
0b. **The share card.** View source on both documents: `og:image` must be the absolute
   `https://cleanjibe.org/social-card.png`, with `og:image:width`/`:height` and
   `twitter:card=summary_large_image` beside it. Open
   <http://127.0.0.1:8765/social-card.png> — 1200 x 630, wordmark and tagline whole, the
   motif in the outcome colours.
1. Open <http://127.0.0.1:8765/app/> for everything below.
2. **Cold boot.** The chip top-right should turn into `engine 0.8.1 · pyodide 0.28.3` within
   ~20 s on a warm connection. Open DevTools → Console: there must be no errors, only
   Pyodide's own "Loading/Loaded micropip, numpy, pandas…" lines.
3. **Drop** `fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` on the
   drop zone. The progress list should walk *runtime → wingfoil_lab → parsing → analyzing*
   and the page must stay responsive the whole time (the analysis is in a worker; scrolling
   must not stutter).
3b. **The example button.** Reload, then click *…or try the example session* instead of
   dropping anything. It must fetch `example/ExampleSession.fit` (the 2026-08-30 recording
   the iOS app bundles — docs/testing.md "The bundled example session") and walk the same
   progress list. Expect the short-session numbers: **2 flights**, 68 % on foil, 2.56 km,
   Turns 10 (all jibes), Outcomes 8 / 0 / 2, wind 196°, best 2 s 13.47 kn, and the same
   four badges — `accel` included, because this example ships whole. Key metrics read
   `0:10 · 2.6 km · 7.71 kn`, `13.47 kn` under **max 2 s**, `8 · 0 · 2` (of 10 jibes) on
   the ladder's colours beside `8 dry · 8 flew`, then `44.7` **JPH** and `11.2 WPH`. Being
   under the 15-minute window, the JPH/WPH peaks equal the whole-session rates.
4. **Check the numbers** against the golden above: 23 flights, 60 % on foil, 12.76 km,
   Turns 30, Outcomes 9/9/12, wind 36°, best 2 s 11.36 kn. Badges: `wingfoil`,
   `CIQ dev fields`, `accel`, `HR`.
4b. **Key metrics**, the four rows above the tiles (`docs/presentation.md`, "Key metrics").
   On this file: `1:25 · 12.8 km · 4.89 kn`, then `11.36 kn` under **max 2 s**, then
   `9 · 9 · 12` on the ladder's own green/amber/red *(this is the only place either app
   draws the tally in colour outside the map)* beside `4 dry · 2 flew`, then `12.8` under
   **JPH · dry jibes per hour** (the 18 jibes he sailed out of, not all 30 — engine 0.7.0)
   and `11.3 WPH`. It must read identically to the iOS app's block on the same session —
   the two halves are `web/js/render.js` `keyMetrics` and `KeyMetrics.swift`, and the
   Swift half is pinned by `PresentationTests.keyMetrics*`.
5. **Map.** North-up track; grey off-foil line with teal foiling segments on top (the phase
   tints, the same two the iOS map uses); small chevrons showing which way he went; numbered
   markers — green discs / amber triangles / red crosses / grey hairline crosses for
   bear-aways / hollow squares on the *same* colour ladder for straight-line flight ends (a
   glide-out is a hollow green square, not a category of its own) / blue takeoff arrows /
   red hollow u-turns for failed attempts / cyan drops where the barometer saw the wrist go
   under; wind arrow + scale bar. Hovering a marker
   shows a tooltip, tapping one opens a popover of that event's facts. The legend counts
   must match the tiles. **Zoom it**: wheel/pinch/double-tap, or the **&minus; + Reset zoom**
   row under the chips. At 3× the markers and their numbers must be the same size as at 1×
   (only the track grows), the chevrons must keep roughly the spacing they had, the scale bar
   must have re-picked its distance, and a one-finger drag must pan rather than scrub. **The teal is cut at the engine's exact flight boundaries**, so
   every landing shows a grey stub even where the source recorded no fix inside it — on the
   2026-08-06 wingfoiling file that is 24 of its 54 boundaries, and before the cut they drew
   as continuous flight with a takeoff arrow apparently mid-flight. (A file with no GPS fixes at all must show *"No GPS positions in
   this file"* in the map slot and still render every other section —
   `tools/verify_web_entry.py` covers this headlessly.)
6. **Speed strip.** Blue Doppler line over the paler positional line, teal flight bands,
   purple pumping bands (one per pumping attempt — 37 on the CIQ file, the number the
   presentation golden pins), the same marker numbers as the map. Moving the pointer across it
   shows a crosshair with the time and both speeds.
6b. **The interactions** (`js/session.js`), which is what the two figures are *for*:
   - **Scrub.** Drag the speed strip: a dashed rule follows the pointer, a dot slides along
     the track at the same instant, and the readout below the strip names that instant once
     — clock time, elapsed, both speeds, flying or off foil. Drag on or near the track
     instead: the same three move together. A press well away from the track does nothing
     rather than yanking the playhead somewhere unrelated. The readout sits **below** the
     figures, not above: it appears the moment a finger lands, and above the strip its
     arrival pushed the figure 151 px down on a phone — out from under the very finger that
     had just set it (see `index.html`).
   - **Layer chips.** Eleven of them, worded by `design/tokens.json` and therefore the same
     words the iOS legend uses: flying · off foil · pumping · direction · best 2 s (the
     effort chip is named after the window it is showing) · flew through · touchdown · fell
     in · course change · takeoff · splash. Every chip hides its category on the map *and*
     in the chart — `direction` takes the chevrons with it and leaves the route. A chip with
     nothing to show stays as a subdued caption, not a dead button. "Show all" returns.
   - **Zoom, on the strip.** Wheel or trackpad over the plot (or a two-finger pinch on a
     touch screen) zooms the time axis about the pointer; markers and bands outside the
     window are not drawn; the axis switches to m:ss. Scrubbing still works while zoomed.
     Out again: the **Reset zoom** chip, a double-click (mouse) or a two-finger double-tap
     (touch). A one-finger **double-tap zooms in** about the tap — the mouse keeps its old
     double-click-to-reset, because a mouse has a wheel and a finger does not. **&minus;**
     and **+** beside the chip do the same about the middle of the window, at 44 px.
   - **Zoom and pan, on the map.** Same vocabulary: wheel/trackpad or pinch zooms about the
     gesture, up to 8×. The chevrons re-space themselves so their *screen* rhythm is the one
     they were tuned at, the markers stay exactly the size they are (the geometry scales, not
     the symbols), and the scale bar re-picks its rounded distance. **Zoomed in, a one-finger
     drag pans**, and a clean tap still scrubs or opens a mark; at 1× a drag scrubs along the
     track as it always did, because there is nowhere to pan to. Same three buttons in the
     map's own legend, and the same double-tap pair.
   - **Pairing, on tap only** (docs/presentation.md). Tap a takeoff arrow: the popover gains
     one accent line, `starts flight 12 · 1:23 · ended: touchdown`. A red u-turn says
     `no flight · 3 strokes`; a hollow flight-end square says
     `ends flight 12 · started 41:07 · 7 pumps` (the stroke clause is *absent*, never `0`,
     on a source with no wrist accelerometer). Tap a **flown stretch of track** — the teal
     line itself — and it names the flight (`flight 12 of 55 · 1:23 · 272 m · ended: …`)
     *and* zooms the strip to that flight plus a margin. Nothing of this is on screen until
     something is tapped.
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
14b. **Whose session is this?** Saving anything that is not the example must ask first.
    *Mine* is preselected; *A friend's* with an empty name must leave *Save* disabled;
    Escape, *Cancel* and a click on the backdrop must all save nothing. Save one as a
    friend's: the library row gets the name as a badge, the count line says how many are not
    counted, and **Records & trends must not move**. The example, saved from *try the example
    session*, is badged *Example*, is never asked about, and counts in nothing either — a
    library holding only those two says so instead of drawing empty charts.
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
- **A wheel over either figure zooms it, and does not scroll the page.** That is the same
  rule the speed strip already had, now on the map too — consistency was worth more than the
  odd overshoot, and the page still scrolls from anywhere beside them.
- The **map's zoom is a camera over the fitted plot**, not a tile server: there is no
  imagery under it and no rotation, so at 8× you are looking at the same polyline, larger.
  The limit is 8× because past that a 1 Hz track is mostly the interpolation between fixes.
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
