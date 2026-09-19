# Web design review — the site and the app shell, 19 September 2026

Jan: *"review the layout / design of the web app / website. Some elements look a bit strange.
Pop-ups, four tabs (sessions, records, …), some others."*

Rendered with headless Chromium against `python3 -m http.server` in `web/`, into
`tmp/shots/` at `-400.png` and `-1280.png` each: `home-`, `start-`, `help-`, `invite-`,
`app-sessions-`, `app-records-`, `app-trends-`, `app-gear-`, `app-settings-`, `app-help-`,
`app-welcome-`, plus `after-gear-1280.png` and `after-welcome-400.png`. The library is
empty in every shot — IndexedDB does not settle under a virtual clock — so the session
page, the welcome and the populated tabs were read from markup and CSS.

## Ranked findings

| # | screen | what | why it reads wrong | the fix | effort |
|---|---|---|---|---|---|
| 1 | app, all tabs | The tab bar is **four words and no glyphs**. iOS carries `water.waves`, `trophy`, `chart.xyaxis.line`, `bag` beside the same labels. | A row of small grey words at the foot of a page reads as a link list. The single largest reason the tabs "look strange". | Four inline SVGs in `.tabbar button`, 22 px over an 11 px label, the button `flex-direction: column`. | M |
| 2 | app, ≥860 px | The **rail was a leftover sidebar**: a full-height panel-coloured column, its items floating halfway down the viewport. | `justify-content: center` put the navigation at the middle of the screen, unattached to what it governs. | **Applied**: top-aligned under the measured `--topbar-h`. Open: drop the panel background, let the right border carry it. | S |
| 3 | app, all tabs | **Two navigations, stacked.** The marketing `sitenav` (GET STARTED · HELP · *Open the app* · *Get the beta*) sits above the app's four tabs. | Pattern F and M. *Open the app* is a loud blue door to the page it is on. | A `/app/` variant: the links stay, the buttons go. `verify_links.py` pins the block across seven pages, so it learns the variant too. | M |
| 4 | Records, Trends, Gear | **No empty state.** Each tab is a title, a grey caption and nothing. `docs/screens.md` names the sentences: *Your records start with your first session*, *No spots yet*, *No wings yet*. | Pattern G. Three of four tabs greet a first visitor with what reads as a failed load. | Render the named sentence when the body is empty, with the door out, as `renderGear` does. | S |
| 5 | Sessions | **`Download all (.zip)` is greyed out and says nothing**; `#lib-sub` beside it is blank. | Pattern G: a control that is off says why. The panel is a heading and a dead button. | `#lib-sub` carries the screen's line, *Nothing saved yet. Analyze a file and press Save to library.* | S |
| 6 | app, banners | **Three banners, no rule between them**: a new version, Chrome's install offer, the iOS hint. Two could show at once, and the iOS bar prepended itself above the sticky topbar while Chrome's identical bar sat below. | Two stacked bars in one colour push the app off the first screen. | **Applied**: at most one banner, in priority order; the iOS bar sits last, under the topbar. Open: `update-dismiss` only sets `hidden`, so it returns on every reload. | S |
| 7 | welcome | **The dismiss was the loudest button**: *Later* was `.primary`, *Try the example session* `.ghost`. | The screen whose job is to get a stranger onto the example shouted *Later* in blue. | **Applied**: swapped, affirmative last. Open: two doors where iOS has three — *Set up intervals.icu* is missing. | S |
| 8 | Gear & spots | **A naked empty card.** The quiver panel drew a bordered white box with nothing in it while IndexedDB answered, and forever where storage is refused. | A blank bordered rectangle is the clearest "broken" signal a page has. | **Applied**: absent until its body is drawn. Open: give the failure its one sentence. | S |
| 9 | Settings, Help | **Two pages with no title.** `#/settings` opens straight into an `INTERVALS.ICU` panel, and neither has a way back but the tab bar. | Pattern A. A destination that does not name itself leaves the rider unsure whether he changed tab or page. | An `h1` and a `‹ Sessions` crumb on both, as `#session-back` gives the session page. | S |
| 10 | site + app | **One type scale for three jobs.** `h2` is 15 px uppercase and letterspaced, so the app's page titles (`SESSIONS`, `RECORDS`) wear the section-nav eyebrow's furniture. Nothing exceeds 18 px. | iOS gives a tab root a large title. Here the title is a label, so nothing is the top of the page. | A `.page .panel-head h2` step: 20–22 px, sentence case, no letterspacing. | M |
| 11 | Help tab | Forty topics, **every section expanded, no search, no index**. The ladder inverts: a topic's summary is smaller than the body under it. | The iOS Help is searchable and foldable. A wall reads as a dump. | Sections as `<details>`, a filter on top, summary at body size. | M |
| 12 | Sessions rows | **The badges explain themselves in a `title`.** *Example* and a rider's name are pills whose meaning, *not counted in your records or trends*, lives in a tooltip a phone cannot open. | Pattern H: no code without its word in reach. | One line under the list when a badge is present. | S |
| 13 | /invite/, /start/, /help/ | Below 720 px the section nav becomes a **full-width grey `<select>`, "On this page…"**. | It reads as an unfilled form field. The other element that looks strange. | A horizontally scrolling chip row, as the session switcher already is. | M |
| 14 | Trends | At 400 px **`Custom range…` wraps to two lines inside a one-line segment** of the range control. | A control that breaks its own shape reads as a bug. | `Custom…` in the segment at narrow widths; the full name stays the sheet's title. | S |
| 15 | / vs /app/ | **Two site headers.** Home says *Wing foiling, measured.* with a GitHub button; `/app/` says *Wingfoil session analyzer* with the Menu button. | One product, one header. | One sub-line; GitHub in the footer only. | S |
| 16 | / hero | The `h1` is *Did you fly through that jibe?* and **the lede opens with the same sentence**. | Pattern F, on the surface a stranger reads first. | Cut the repeat. Register 2 gets one line of energy. | S |
| 17 | app shell | **The shell is monochrome blue.** Active tab, primary buttons and links are all `--series-1`, the chart's series ink. Phase teal and clean mint live only inside the figures. | The product's colour is the mark's teal; the chrome borrows a data ink. | A decision, not a patch: the shell takes the teal for `aria-current`, or `docs/presentation.md` says the chrome is deliberately neutral. | M |
| 18 | app | **A shared file can vanish silently.** `?shared=1` with an empty slot calls nothing and says nothing. | Pattern G. The rider shared a `.fit` from Android and lands on an untouched Sessions tab. | One sentence when `takeSharedFile()` returns nothing. | S |

## Checked and clean

- **Contrast.** `--ink-3` is `#5f6159` on white (6.4:1) and `#8a8a80` on `#1a1a19`
  (5.3:1); `--ink-2` is 9.5 and above. `.muted` and `.dim` clear WCAG AA in both themes, so
  Jan's watch rule is met. The 10.5 px `.lib-tag` and `.fineprint` are small, not faint.
- **Dark and light.** Every colour is defined once in `--lt-*` and mapped twice.
- **No cookie or consent pop-up.** Confirmed: umami is cookie-free, and the footer says so.
- **Safe area.** `.tabbar` carries `env(safe-area-inset-bottom)`, `main` reserves it, and
  *Gear & spots* fits the 400 px bar without clipping.
- **Pattern M.** The Menu button is page chrome, so it is on all four tabs in one corner.

## The fixes applied

1. `web/app/index.html` — welcome dialog: *Try the example session* is the primary and sits
   last; *Later* is the ghost.
2. `web/css/app.css` — the ≥860 px rail is top-aligned under the measured topbar.
3. `web/css/app.css` — at most one banner:
   `.update-banner:not([hidden]) ~ .update-banner:not([hidden]) { display: none; }`.
4. `web/js/install.js` — the iOS hint is inserted after `#install-banner` rather than
   prepended to `<body>`, so it sits under the topbar and is the one that stands down.
5. `web/css/app.css` — `#gear-quiver-panel:has(#gear-quiver:empty) { display: none; }`.

`verify_app_shell.py`, `verify_links.py`, `verify_unique.py`, `verify_copy.py` pass.
`verify_web_entry.py` fails on a pre-existing numpy/pandas ABI mismatch locally.

## The patterns of this round

- **G, affordances that do not show** — 4, 5, 8, 18. A surface with nothing on it says the
  screen's own sentence and offers the door out.
- **F and M, furniture in two places** — 3, 6, 15. Both shells are on screen inside the app,
  and one banner had two positions.
- **A, a title narrower than its screen** — 9, 10. Two pages do not name themselves; the
  style that would name them is spent on labels.
- **H, a bare code** — 12. The badge's meaning is in a tooltip.
