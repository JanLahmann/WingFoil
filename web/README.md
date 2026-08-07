# WingFoil Lab — web

A zero-server web app that runs the **actual `wingfoil_lab` Python engine** in the browser
via [Pyodide](https://pyodide.org/) (CPython compiled to WebAssembly). Drop a `.fit` file,
get the full session analysis: flights, GP3S speed records, wind axis, turns with outcomes,
flight ends, takeoffs.

**There is no third implementation of the analysis.** The browser imports
`lab/src/wingfoil_lab` unchanged and calls the same `goldens.analyze()` +
`goldens.build_golden()` that `lab/tools/make_goldens.py` calls. The `golden` block in the
downloadable JSON is byte-identical to `fixtures/goldens/<stem>.expected.json` for the same
file — verified against all 13 corpus fixtures (see *Verification* below).

```
web/
├── index.html                  page shell
├── css/style.css               dark styling + the data-viz palette
├── js/app.js                   file intake, worker orchestration, progress
├── js/worker.js                Pyodide worker — loads the runtime + the lab, runs the pipeline
├── js/render.js                summary tiles, inline-SVG map & speed strip, tables
├── js/icu.js                   optional intervals.icu panel
├── lab_bundle/
│   ├── web_entry.py            the ONLY added Python: bytes -> analysis JSON glue
│   ├── wingfoil_lab/           GENERATED copy of lab/src/wingfoil_lab — do not edit
│   ├── FILES.json              load list for the worker (HTTP has no directory listing)
│   └── MANIFEST.json           source hashes, for the staleness check
├── tools/bundle_lab.py         regenerates lab_bundle/wingfoil_lab
└── .nojekyll                   GitHub Pages: serve files verbatim
```

## Privacy

**Nothing leaves the browser.** There is no backend, no upload endpoint, no analytics, no
cookies. The FIT file is read with the File API, handed to a Web Worker, and analyzed inside
the WebAssembly sandbox. The only outbound requests the page ever makes are:

| Request | When | Why |
|---|---|---|
| `cdn.jsdelivr.net/pyodide/v0.28.3/…` | first load | the Python runtime + numpy/pandas (~12 MB, then browser-cached) |
| `pypi.org` / `files.pythonhosted.org` | first load | the `fitdecode` wheel (pure Python, ~120 KB) |
| `intervals.icu/api/v1/…` | only if you use the intervals.icu panel | your own activity list / FIT |

The intervals.icu API key is stored **only in this browser's `localStorage`** and is attached
**only** to requests to `intervals.icu`. It is never sent to the site's host and never appears
in a URL. "Forget key" deletes it.

## Running it locally

```bash
cd web
python3 -m http.server 8765
# open http://127.0.0.1:8765/
```

A plain static server is enough — no build step, no bundler, no npm. The app is plain ES
modules; `js/worker.js` is a **module worker**, which needs a real HTTP origin, so
`file://` will not work.

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

`lab_bundle/web_entry.py` is hand-written and is never touched by the bundler.

## Verification

Three checks, none of which need a browser:

```bash
# 1. the bundle imports and reproduces the goldens exactly
cd /path/to/WingFoil
PYTHONPATH=web/lab_bundle lab/.venv/bin/python - <<'PY'
import json, pathlib, web_entry
fit  = pathlib.Path("fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit")
exp  = json.loads(pathlib.Path("fixtures/goldens/2026-08-07-0754_nago-torbole-windsurfen_ciq.expected.json").read_text())
res  = web_entry.analyze_bytes(fit.read_bytes(), fit.name)
assert res["golden"] == exp, "web_entry drifted from the golden"
print("OK:", res["golden"]["summary"]["turns"]["turnsCounted"], "turns,",
      res["golden"]["summary"]["flightCount"], "flights")
PY

# 2. JS syntax
cd web && for f in js/*.js; do node --check "$f" || exit 1; done

# 3. the lab itself is still green
cd lab && uv run pytest -q
```

Expected numbers for that CIQ session: **30 jibes / 0 tacks**, outcomes **9 flew through / 9
touchdown / 12 fell in**, **23 flights**, 12.764 km, wind from 36°, 60 % on foil.

### Manual browser test checklist

1. `cd web && python3 -m http.server 8765`, open <http://127.0.0.1:8765/>.
2. **Cold boot.** The chip top-right should turn into `engine 0.2.0 · pyodide 0.28.3` within
   ~20 s on a warm connection. Open DevTools → Console: there must be no errors, only
   Pyodide's own "Loading/Loaded micropip, numpy, pandas…" lines.
3. **Drop** `fixtures/sessions/ciq/2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` on the
   drop zone. The progress list should walk *runtime → wingfoil_lab → parsing → analyzing*
   and the page must stay responsive the whole time (the analysis is in a worker; scrolling
   must not stutter).
4. **Check the numbers** against the golden above: 23 flights, 60 % on foil, 12.76 km,
   Turns 30, Outcomes 9/9/12, wind 36°, best 2 s 11.36 kn. Badges: `wingfoil`,
   `CIQ dev fields`, `accel`, `HR`.
5. **Map.** North-up track; grey off-foil line with blue foiling segments on top; numbered
   markers — green discs / amber triangles / red crosses / grey hairline crosses for
   bear-aways / hollow squares for straight-line flight ends; wind arrow + scale bar.
   Hovering a marker shows a tooltip. The legend counts must match the tiles.
6. **Speed strip.** Blue Doppler line over the paler positional line, blue flight bands, the
   same marker numbers as the map. Moving the pointer across it shows a crosshair with the
   time and both speeds.
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

## Known limitations

- **Times are shown in your browser's timezone**, not the session's. The FIT's local offset
  lives in the trailing `activity` message, which `parse.py` does not retain, and re-reading
  a 6 MB FIT just for that is not worth the seconds in WASM.
- First load downloads ~12 MB (Pyodide + numpy + pandas). It is cached afterwards, but the
  very first analysis on a cold cache takes ~25 s end to end for a 90-minute session.
- The intervals.icu integration will normally be blocked by CORS. That is not fixable from a
  zero-server app; the panel detects it and explains the manual export path.
- No pan/zoom on the map — it is a fixed, aspect-correct plot, like `lab/tools/plot_turns.py`.
