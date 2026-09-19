# Web design review — the site and the app shell, 19 September 2026

Jan: *"review the layout / design of the web app / website. Some elements look a bit strange.
Pop-ups, four tabs (sessions, records, …), some others."*

Rendered with headless Chromium against `python3 -m http.server` in `web/`, into
`tmp/shots/` at `-400.png` and `-1280.png` each: `home-`, `start-`, `help-`, `invite-`,
`app-sessions-`, `app-records-`, `app-trends-`, `app-gear-`, `app-settings-`, `app-help-`,
`app-welcome-`, plus `after-gear-1280.png` and `after-welcome-400.png`. The library is
empty in every shot — IndexedDB does not settle under a virtual clock — so the session
page, the welcome and the populated tabs were read from markup and CSS.

**How to shoot the app so its empty states are actually in the picture** (the second round,
the same day). Drop `--virtual-time-budget` and give `chrome-headless-shell` a real
`--timeout=12000`: storage then settles and every tab draws its own sentence. The welcome
dialog opens over the first shot, so seed `cleanjibe.welcomeSeen.v1` from a throwaway page
on the same origin that redirects to `/app/#/<tab>`, and delete that page afterwards. The
round's own shots are `tmp/shots/after-*.png` at 400 px and 1280 px, plus
`after-app-sessions-menu-400.png` with the menu open.

## Ranked findings

| # | screen | what | why it reads wrong | the fix | state |
|---|---|---|---|---|---|
| 1 | app, all tabs | The tab bar is **four words and no glyphs**. iOS carries `water.waves`, `trophy`, `chart.xyaxis.line`, `bag` beside the same labels. | A row of small grey words at the foot of a page reads as a link list. The single largest reason the tabs "look strange". | Four inline SVGs in `.tabbar button`, 24 px over an 11 px label, the button `flex-direction: column`. **Applied**, with the three faults of Jan's fourth screenshot: the chosen tab is ink, not a clipped box; the safe-area inset is paid once, by the bar; the count badge rides the glyph. | **applied** |
| 2 | app, ≥860 px | The **rail was a leftover sidebar**: a full-height panel-coloured column, its items floating halfway down the viewport. | `justify-content: center` put the navigation at the middle of the screen, unattached to what it governs. | **Applied**: top-aligned under the measured `--topbar-h`, and the rail's rows now carry the tab glyphs. Open: drop the panel background, let the right border carry it. | open |
| 3 | app, all tabs | **Two navigations, stacked.** The marketing `sitenav` (GET STARTED · HELP · *Open the app* · *Get the beta*) sits above the app's four tabs. | Pattern F and M. *Open the app* is a loud blue door to the page it is on. | **Applied**: `/app/` has no site nav at all. One bar, the mark, the name and the Menu button, between `appheader:begin` and `appheader:end`; `verify_links.py` pins the nav across the six reader pages and holds the app to its own header. | **applied** |
| 4 | Records, Trends, Gear | **No empty state.** Each tab is a title, a grey caption and nothing. `docs/screens.md` names the sentences: *Your records start with your first session*, *No spots yet*, *No wings yet*. | Pattern G. Three of four tabs greet a first visitor with what reads as a failed load. | **Applied**: *Your records start with your first session*, *Your trends start with your first session*, *No spots yet* — each with *Go to Sessions*. A spot chip that filtered everything out says *No session matches these filters* instead. | **applied** |
| 5 | Sessions | **`Download all (.zip)` is greyed out and says nothing**; `#lib-sub` beside it is blank. | Pattern G: a control that is off says why. The panel is a heading and a dead button. | **Applied**: `#lib-sub` carries the screen's line, *Nothing saved yet. Analyze a file and press Save to library.* | **applied** |
| 6 | app, banners | **Three banners, no rule between them**: a new version, Chrome's install offer, the iOS hint. Two could show at once, and the iOS bar prepended itself above the sticky topbar while Chrome's identical bar sat below. | Two stacked bars in one colour push the app off the first screen. | **Applied**: at most one banner, in priority order; the iOS bar sits last, under the topbar. *Later* is now remembered in `localStorage` behind try/catch, keyed by the build it was said on, so the next release still asks. | **applied** |
| 7 | welcome | **The dismiss was the loudest button**: *Later* was `.primary`, *Try the example session* `.ghost`. | The screen whose job is to get a stranger onto the example shouted *Later* in blue. | **Applied**: swapped, affirmative last, and the phone's third door — *Set up intervals.icu* — is there and opens Settings. | **applied** |
| 8 | Gear & spots | **A naked empty card.** The quiver panel drew a bordered white box with nothing in it while IndexedDB answered, and forever where storage is refused. | A blank bordered rectangle is the clearest "broken" signal a page has. | **Applied**: absent until its body is drawn, and a storage that refuses now says *Your gear could not be read. This browser is not saving anything right now.* | **applied** |
| 9 | Settings, Help | **Two pages with no title.** `#/settings` opens straight into an `INTERVALS.ICU` panel, and neither has a way back but the tab bar. | Pattern A. A destination that does not name itself leaves the rider unsure whether he changed tab or page. | **Applied**: both carry an `h1` and *Back to Sessions*, in the session page's own words. | **applied** |
| 10 | site + app | **One type scale for three jobs.** `h2` is 15 px uppercase and letterspaced, so the app's page titles (`SESSIONS`, `RECORDS`) wear the section-nav eyebrow's furniture. Nothing exceeds 18 px. | iOS gives a tab root a large title. Here the title is a label, so nothing is the top of the page. | **Applied**: a tab root's name is the page's `h1.page-title` at 21 px in sentence case, and `h2` stays the 15 px section eyebrow it was. The app header's wordmark is no longer an `h1`, so one page has one top. | **applied** |
| 11 | Help tab | Forty topics, **every section expanded, no search, no index**. The ladder inverts: a topic's summary is smaller than the body under it. | The iOS Help is searchable and foldable. A wall reads as a dump. | Sections as `<details>`, a filter on top, summary at body size. **Open** — the Help tab renders from `HELP.sections` in js/appshell.js and the fold and the filter are a screen of their own, not a patch on this round. | open |
| 12 | Sessions rows | **The badges explain themselves in a `title`.** *Example* and a rider's name are pills whose meaning, *not counted in your records or trends*, lives in a tooltip a phone cannot open. | Pattern H: no code without its word in reach. | **Applied**: one line under the list, and only where a badge is on it. | **applied** |
| 13 | /invite/, /start/, /help/ | Below 720 px the section nav becomes a **full-width grey `<select>`, "On this page…"**. | It reads as an unfilled form field. The other element that looks strange. | **Applied**: the `<select>` is gone from the markup and the stylesheet. Below 720 px the same links are a row of chips that scrolls sideways, in the session switcher's shape. | **applied** |
| 14 | Trends | At 400 px **`Custom range…` wraps to two lines inside a one-line segment** of the range control. | A control that breaks its own shape reads as a bug. | **Applied**: `Custom…` under 480 px, the full name as the button's accessible name and as the sheet's title, and the segment's words no longer wrap. | **applied** |
| 15 | / vs /app/ | **Two site headers.** Home says *Wing foiling, measured.* with a GitHub button; `/app/` says *Wingfoil session analyzer* with the Menu button. | One product, one header. | **Applied**: one sub-line, the site's. The app header carries no tagline, because the page names itself one screen down, and the repo link is in the footer on every page. | **applied** |
| 16 | / hero | The `h1` is *Did you fly through that jibe?* and **the lede opens with the same sentence**. | Pattern F, on the surface a stranger reads first. | Cut the repeat. **Open**: the lede is `data-copy="promise"`, pinned character for character to `docs/copy/phrases.json` by `verify_copy.py`, and the `h1` is its first sentence. Cutting the repeat means either a new headline or a new promise, and both are copy decisions rather than layout ones. | open |
| 17 | app shell | **The shell is monochrome blue.** Active tab, primary buttons and links are all `--series-1`, the chart's series ink. Phase teal and clean mint live only inside the figures. | The product's colour is the mark's teal; the chrome borrows a data ink. | A decision, not a patch: the shell takes the teal for `aria-current`, or `docs/presentation.md` says the chrome is deliberately neutral. **Open, and Jan's to make.** The tab bar now marks the chosen tab with `--series-1`, so the question is live on one more surface than it was. | open |
| 18 | app | **A shared file can vanish silently.** `?shared=1` with an empty slot calls nothing and says nothing. | Pattern G. The rider shared a `.fit` from Android and lands on an untouched Sessions tab. | **Applied**: *That shared file did not arrive. Share it again and pick CleanJibe.* on the Sessions tab. | **applied** |

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

**Round one, 19 September 2026 (the review's own five).**

1. `web/app/index.html` — welcome dialog: *Try the example session* is the primary and sits
   last; *Later* is the ghost.
2. `web/css/app.css` — the ≥860 px rail is top-aligned under the measured topbar.
3. `web/css/app.css` — at most one banner:
   `.update-banner:not([hidden]) ~ .update-banner:not([hidden]) { display: none; }`.
4. `web/js/install.js` — the iOS hint is inserted after `#install-banner` rather than
   prepended to `<body>`, so it sits under the topbar and is the one that stands down.
5. `web/css/app.css` — `#gear-quiver-panel:has(#gear-quiver:empty) { display: none; }`.

**Round two, the same day, after three more phone screenshots** (*"Layout still not really
nice. Unclear this is drop down."*, *"Navigation / tabs don't look nice."*).

6. **One header on `/app/`** — the site nav is gone from the app; the bar is the mark, the
   name and the Menu button, between `<!-- appheader:begin -->` and `<!-- appheader:end -->`.
   `verify_links.py` byte-pins the nav across the six reader pages and holds the app to its
   own header instead. The repo link left every topbar for the footer.
7. **The menu is a sheet in the app's own style** — an `.ask-form` with padding, rows of an
   icon and a word at 15 px, the phone's five symbols drawn as line icons, the divider above
   *Settings*, the build line as a footer under a hairline, *Close* as a button. The sheet
   takes the focus, so no row opens wearing a ring.
8. **The tab bar is a tab bar** — a 24 px glyph over an 11 px label, the phone's four
   symbols; the chosen tab is ink and stroke rather than a box that the bar's edge clipped;
   the safe-area inset is paid once, by the bar, which is where the white band under the
   labels came from; the count badge rides the glyph.
9. **The three metric cells cannot touch** — `.lib-open > span { display: block }` is more
   specific than `.row-metrics { display: flex }`, so the row's gap had never applied. It is
   a three-column grid, qualified by `.lib-row`, with the gutter between the cells.
10. **Empty states** on Records, Trends and Gear & spots, in the phone's words, each with the
    door out; `#lib-sub` says why *Download all (.zip)* is off.
11. **Titles** — a tab root's name is the page's `h1.page-title` at 21 px sentence case;
    Settings and Help have one, and a *Back to Sessions* crumb.
12. **The section nav** on `/start/`, `/invite/` and `/privacy/` is a scrolling chip row
    under 720 px. The `<select>` and the script that drove it are gone.
13. The small ones: *Later* on the update banner is remembered; the welcome's third door;
    the quiver's failure sentence; the badge line under the list; the shared-file sentence;
    `Custom…` in the segment.

`verify_app_shell.py`, `verify_links.py`, `verify_unique.py`, `verify_copy.py` and
`docs/copy/check_voice.py` pass. `verify_web_entry.py` still fails on the pre-existing
numpy/pandas ABI mismatch locally.

**Still open, and why.** 2 (the rail's panel background), 11 (the Help tab's folds and its
filter — a screen of its own), 16 (the hero repeat: the lede is pinned copy, so it is a
copy decision), 17 (the shell's colour — Jan's to make, and the new tab bar puts
`--series-1` on one more surface).

## The patterns of this round

- **G, affordances that do not show** — 4, 5, 8, 18. A surface with nothing on it says the
  screen's own sentence and offers the door out.
- **F and M, furniture in two places** — 3, 6, 15. Both shells are on screen inside the app,
  and one banner had two positions.
- **A, a title narrower than its screen** — 9, 10. Two pages do not name themselves; the
  style that would name them is spent on labels.
- **H, a bare code** — 12, and the tab bar. The badge's meaning was in a tooltip; four
  words with no glyph are the same fault one bar down, and the phone's symbols are what the
  words were missing.
- **A control that pays a cost twice** — 8, and the row metrics. A safe-area inset paid by
  the bar and by its buttons is a white band; a `display: flex` overruled by a more specific
  `display: block` is a gap that never applied. Both were invisible in the stylesheet and
  obvious on a phone, which is why a round ends with a 400 px screenshot.
