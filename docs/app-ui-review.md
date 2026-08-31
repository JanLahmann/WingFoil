# App UI review — iOS (iPhone 17 Pro Max) & web (janlahmann.github.io/WingFoil)

Same format as `docs/watch-ui-review.md`: numbered findings, a severity, a concrete fix.
Judged against `docs/presentation.md` (the UI contract), `docs/plan.md` §3.3, and the taste
the watch review established — **numbers big, labels small, no unclear icons, tables over
decoration, information-dense but readable at a glance**.

## 0. How these screenshots were made

**iOS.** `xcodegen` + `xcodebuild -scheme WingFoil` from this worktree, Debug, onto the
`iPhone 17 Pro Max` simulator (iOS 26.5, 440 × 956 pt / 1320 × 2868 px). Screens were parked
with the `SIMCTL_CHILD_UI_*` hooks documented in `docs/testing.md`:
`UI_RESET=1 UI_IMPORT_FIXTURES=1` for the library (14 fixtures imported), then
`UI_OPEN_SESSION=latest` with `UI_SCROLL_TO=chart|summary|turns|takeoff|hr`,
`UI_OPEN_TURNS=1`, `UI_TAB=records|trends|gear`, `UI_SCROLL_TO=sideSuccess`, `UI_SHEET=settings`.
The open session is the 29 Aug Nago-Torbole CIQ recording (1 h 57 m, 31 flights, 51 turns,
69 takeoff attempts) — a deliberately busy session, which is the one worth designing for.

**Web.** Live Pages deploy in a throwaway Chrome tab, engine 0.5.0 / pyodide 0.28.3. The
6.0 MB CIQ fixture (`2026-08-07-0754…_ciq.fit`) was imported through the page's own file
input, then saved to the library so Library and Records & trends had a row to draw.

Two caveats on coverage, stated rather than hidden:

- **No true narrow-viewport screenshot.** `resize_window` narrows the OS window but the
  screenshot API captures at a fixed 1372 × 870 virtual viewport, so the phone layout never
  entered the frame. §7 (small-screen web) is therefore read from `web/css/style.css`'s
  breakpoints rather than from a picture. That is a weaker evidence base and is flagged as
  such — but the CSS is unusually explicit, so the conclusions are firm.
- **No standalone Spots screenshot** — see finding 6.1: there is no Spots *screen* to park
  on. It is a row inside the Settings sheet.

### Captures

| file | screen |
|---|---|
| `ios-library.png` | Sessions (Library) |
| `ios-session-top.png` | SessionDetail — header, map, legend |
| `ios-session-chart.png` | SessionDetail — speed chart + replay |
| `ios-session-summary.png` | SessionDetail — Foil + Speed records |
| `ios-session-turns.png` | SessionDetail — Turns & losses + Takeoff |
| `ios-session-takeoff.png` | SessionDetail — Takeoff & pumping + Effort |
| `ios-session-hr.png` | SessionDetail — HR cost + Gear |
| `ios-session-turnsdrill.png` | Turns drill-in (filters + map + list) |
| `ios-records.png` | Records tab |
| `ios-trends.png` | Trends tab (top) |
| `ios-trends-sidesucc.png` | Trends — port/starboard + side success |
| `ios-gear.png` | Gear tab |
| `ios-settings.png` | Settings sheet |
| `web-01-loading-progress.png` | Pyodide/analysis progress card |
| `web-02-session-top.png` | Web session — header + tile grid |
| `web-03-session-map-legend.png` | Web session — track + legend chips |
| `web-04-session-chart-takeoffs.png` | Web session — speed strip + takeoffs |
| `web-05-session-turns-table.png` | Web session — turns table |
| `web-06-library.png` | Web library |
| `web-07-records-trends.png` | Web records & trends |

---

## 1. iOS SessionDetail — the screen the whole app is for

Measured from `ios-session-top.png`, converted to points (956 pt tall, tab bar from ~880 pt):

| band | points |
|---|---|
| title + sport + wind line | 127 – 190 |
| "Watch and phone disagree" banner | 210 – 245 |
| map | 266 – 528 |
| legend chips (10 chips, 3 rows) | 535 – 609 |
| grey explainer prose (3 paragraphs) | 621 – 735 |
| "Open map full screen" | 734 |
| "Speed" heading | 770 |

### 1.1 There is not one number on the first screen — HIGH

The rider finishes a session, opens the app, taps the top row, and the first screenful
contains: a date, a sport chip, a wind bearing, a warning, a map, ten legend chips and three
paragraphs of grey instructions. **The first actual result — `Foil time 56%` — sits at
roughly 1160 pt, one and a third screens down.** The session's verdict is below the fold on
a 6.9″ phone.

This is exactly finding §9.4 of the watch review ("Five numbers, no hierarchy, no verdict"),
and the watch fixed it by making foil % the giant on the page you land on. The phone has
twenty times the glass and answers the question later than the watch does.

**Fix.** Put a verdict block directly under the title, above the map — see §3 for the exact
content. It costs ~150 pt and it is the reason the screen exists.

### 1.2 190 pt — a fifth of the screen — is spent explaining the legend — MEDIUM

The chips (74 pt, 3 rows) are a control and earn their space. The three grey paragraphs
under them (621–735 pt) do not: "Tap a chip to hide or show it… Chevrons point the way you
were riding. Solid = maneuver outcome · hollow = straight-line flight end. Takeoff carries
both halves… Tap the track to move the replay playhead…". That is legend documentation
rendered on every visit, forever, to a rider who learned it the first time.

Note the one genuinely session-specific fact is buried mid-paragraph: *"38 failed attempts
this session."* That is a number, and it is set in grey 13 pt body copy.

**Fix.** Collapse the prose behind the `?` help affordance the app already has everywhere
else (`Speed ?`, `Foil ?`, `Turns & losses ?`). Promote "38 failed attempts" into the
takeoff card where it belongs. Saves ~115 pt on every session view.

### 1.3 The warning banner outranks the results — MEDIUM

"Watch and phone disagree on takeoff attempts" is a collapsed orange banner at 210 pt —
above the map, above everything. It is a provenance footnote about a 69-vs-N attempt count,
and it is currently the most prominent element on the screen after the title.

**Fix.** Move it below the verdict block, or reduce it to a small orange `?`-style badge on
the Takeoff card whose disagreement it describes. A discrepancy in one metric should be
marked on that metric, not gated in front of the whole session.

### 1.4 Speed records: eight tiles, ~520 pt, to show eight numbers — MEDIUM

`ios-session-summary.png`. Eight 2-up cards, each ~130 pt tall, each carrying one number
plus a "at 58:00 · 2 s" provenance line. The web shows the identical eight as a compact
table (`web-07-records-trends.png`) in about a third of the height and it reads *better*,
because the values line up in a column and can be compared by eye.

The owner's stated taste is tables over decoration. This is the clearest place in the app
where a table wins.

**Fix.** One table: `record | value | at`. Keep the orange selection ring on the row (the
picker semantics in `presentation.md` "Record windows" work identically on a row).

### 1.5 The chart's x-axis ticks are arbitrary — LOW

`ios-session-chart.png`: `0:00 · 33:20 · 66:40 · 100:00`. Those are 2000-second intervals —
the axis divided the domain into four rather than choosing round time units. The web strip
does it right: `0 10 20 30 40 50 60 70 80` minutes.

**Fix.** Snap ticks to 5/10/15/30-minute units. Same on the HR-cost chart, which shares the
defect.

### 1.6 The 2-up card grid strands a half row — LOW

`ios-session-turns.png`: `Glide-outs 0` sits alone with an empty cell beside it. Same in
`ios-session-takeoff.png` (`Pump strokes 3091` alone). With an odd card count the grid always
ends ragged.

**Fix.** Falls into §3's restructure anyway — a table has no parity problem.

---

## 2. iOS Turns drill-in — the best screen in the app, two taps deep

`ios-session-turnsdrill.png`.

### 2.1 This screen already is the design language the watch just adopted — and nothing links to it from the top — HIGH (opportunity, not a defect)

It opens with **`69%` flew through / `35 of 51 all turns`**, then a three-chip tally
`35 flew through · 8 touchdown · 8 fell in` on the ladder's own inks, then the filtered map,
then a dense scannable list (`4:57 · Jibe · port entry · 11.8 → 8.7 kn · 74 · ✅`).

Outcome tally as the headline, a percentage as the giant, a table underneath. That is
verbatim the watch's redesigned S4/Turns page and verbatim Jan's taste. It is genuinely
excellent — and it is reached only by scrolling ~2 400 pt to the "All 51 turns" row and
tapping it.

**Fix.** Promote the `69% flew through` + tally block to the top of SessionDetail (§3),
and make the turn list a tab rather than a push.

### 2.2 The filter copy is correct — no action

"Port entry / Starboard entry" plus "Entry tack is the tack you came into the turn on — not
which way the board rotated." That is `presentation.md` "Filter semantics" honoured to the
letter. Worth stating because §5.2 below is the same fact violated elsewhere.

---

## 3. THE MULTI-PAGE QUESTION — endorsed for iOS, with one structural constraint

**Verdict: yes, tab it — but tab the *cards*, not the *figures*.**

### 3.1 The scroll is genuinely too long

Adding the measured bands: header/map/legend/prose ~770 pt, chart + replay ~370, Foil ~260,
Speed records ~520, Turns & losses ~590, Takeoff & pumping ~330, Effort/HR ~780, Gear ~200.
**≈ 3 800 pt — a little over four full phone screens**, with five unrelated subjects in one
column and no way to get to the fifth except through the other four. A rider who wants to
know how his jibes went scrolls past the map, the chart, the replay, four foil tiles and
eight record tiles to get there.

### 3.2 The constraint that rules out naive tabs

`presentation.md` "Scrub and zoom" mandates **one playhead**: the chart scrub position and
the map dot are the same timestamp, and moving either moves both. "Pairing" adds that tapping
a flown stretch of track **focuses the chart on that flight**. Map and chart are therefore
one linked instrument, not two pages. A tab set of `Overview / Map / Turns / Takeoffs /
Records` that puts Map on its own page breaks the visible half of that link: you tap a
segment on Map, and the chart it focused is on another tab.

So the split has to fall between **the figures** (map + chart, one instrument, shared
playhead) and **the analysis cards** (five independent subjects).

### 3.3 Proposed structure

```
┌─ title · sport · date · 1 h 57 m · 23.0 km          (always, ~64 pt)
├─ VERDICT                                            (always, ~150 pt)
│    56%  on foil          1 h 3 m of 1 h 57 m
│    ●35  ●8  ●8           flew / touched / fell      ← ladder inks, watch idiom
│    31 flights · longest 7:04
├─ [ Map · Speed | Turns | Takeoffs | Effort ]        segmented, sticky
└─ tab body
```

| tab | contents |
|---|---|
| **Map · Speed** *(default)* | the map, the legend chips, the speed chart, the replay scrubber, the speed-records table (§1.4). One playhead, one instrument, contract intact. |
| **Turns** | today's Turns & losses cards **plus the drill-in list inline** — filters, tally, list. Kills the extra push in §2.1. |
| **Takeoffs** | Takeoff & pumping cards + the "38 failed attempts" number from §1.2. |
| **Effort** | HR cost card, the bins chart, gear picker. |

Why this and not the tab set floated in the brief: `Overview` disappears because the verdict
block *is* the overview and it should be permanent, not a page you can navigate away from;
`Records` folds into Map · Speed because the record picker's whole purpose is to highlight a
window **on the map and chart** — a records tab that highlights a figure on a different tab
is the §3.2 mistake again.

The verdict block staying above the tab bar is the important part. It is the answer to "was
that a good session", and it should never be a tab you have to select.

**Precedent.** The watch reached the same conclusion from the opposite direction: `watch-ui-review.md`
§10 replaced a single crowded summary with a seven-page paged review, keeping a verdict page
as the one you land on. The phone should do the same thing with the affordance a phone has.

### 3.4 The web session view — a different answer

**On desktop, keep the single scroll.** At `max-width: 1120px` the web session view is a
document, and it is a good one: tiles → track → speed strip → takeoffs → turns table →
flight-ends table → raw JSON. The two long tables (34 turn rows, 23 flight-end rows) *want*
a continuous page; that is what makes it a lab tool rather than an app, and Jan reviews it on
a Mac. Tabs there would be a regression.

**On narrow, adopt the same five-way switcher.** The page already has a `.views` segmented
control in the topbar (Analyze / Library / Records & trends) which at ≤760 px goes
full-width on its own row — the idiom exists. Below 760 px the session view should get a
second row of section chips driving the same five sections as iOS, so the phone user is not
scrolling ~6 000 px past two full tables.

Cheap intermediate step if that is too much: make the Turns and Flight-ends panels
`<details>`, collapsed by default below 760 px, with the summary line ("30 counted, 4
rejected · 4 held ≥ 70 %…") as the `<summary>`. That alone removes ~2 000 px of phone scroll
for a few lines of CSS.

---

## 4. Information hierarchy — what belongs first on a phone

The question "what deserves to be first" has one answer and both apps currently give a
different one.

**The verdict.** In priority order:

1. **Foil %** with the absolute time beside it (`56% · 1 h 3 m of 1 h 57 m`). It is the one
   number that answers "was that a good session", it is the watch's S1 giant, and it is the
   first stat on the iOS library row already.
2. **The outcome tally as three coloured counts** — `35 · 8 · 8` on the ladder's inks. Not a
   percentage alone; the tally carries the shape of the session (many turns mostly landed vs
   few turns all landed) in the same width.
3. **Flights + longest** — `31 flights · longest 7:04`.
4. **Best 2 s**, with a PB flag when it beat the stored all-time.

Everything else — wind axis, records beyond best 2 s, pump strokes, HR cost, the map — is
second screen. The map is a *browsing* surface, not an answer; it deserves the largest area,
not the first position.

**Where each app stands.**

- **iOS library row** already does this correctly and beautifully: thumbnail + phase-tinted
  sparkline, `56% · 31 turns · 13.21 kn`, then `35 · 8 · 8` in ladder inks, then distance
  greyed. It is the single best-designed element in either app. The session *detail* it
  opens then discards that hierarchy entirely.
- **iOS SessionDetail** leads with a map (§1.1).
- **Web session** leads with a 10-cell tile grid (`web-02-session-top.png`) in which
  everything is the same size — `DURATION 1:31:34` is as loud as `OUTCOMES 9/9/12`. That is
  the watch's §9.4 defect ("all five rows same size, same colour, same weight; nothing is
  the headline") reproduced at ten cells. Nothing is the headline.

**Fix, web.** Break the flat 10-tile grid into a hero row and a detail row: `ON FOIL` +
`OUTCOMES` + `FLIGHTS` large in a first band, the rest at current size below. The tiles are
already `grid-template-columns: repeat(auto-fit, minmax(150px,1fr))`, so this is a class on
three cells, not a rewrite.

---

## 5. Cross-platform consistency — and three contract violations

The watch now leads the design language. Measuring the apps against it:

| watch idiom | iOS | web |
|---|---|---|
| outcome tally as headline | library row ✅ · detail ❌ · turns drill-in ✅ | one tile among ten ⚠️ |
| foil % as the verdict giant | library ✅ · detail ❌ | one tile among ten ⚠️ |
| streaks (longest dry / longest flew) | absent ❌ | absent ❌ |
| foil `min | km` table | split across Foil + Distance cards ⚠️ | ✅ tiles |
| dot strips for outcome sequence | absent ❌ | absent ❌ |

### 5.1 `longestDryStreak` / `longestFlewStreak` are computed and never shown — MEDIUM

Both live in the golden schema (`summary.turns.longestDryStreak`, `longestFlewStreak`, per
`docs/testing.md`) and the watch review promoted streaks into the redesigned summary. Neither
app renders either one. "Six jibes in a row without getting wet" is the most motivating
sentence this dataset can produce, and it is already in the analysis document.

**Fix.** One line in the verdict block: `best run: 6 flew in a row`. Free — no new
measurement.

### 5.2 Trends borrows the outcome ladder for a non-verdict — HIGH (contract violation)

`ios-trends-sidesucc.png`, "Turn success by entry tack": **port entry = blue, starboard entry
= green.**

`presentation.md` is unambiguous: *"The outcome ladder is a verdict scale and nothing else
may borrow it: green = flew through · orange = touchdown · red = fell in · grey = course
change"*, and blue is the takeoff ink. Here green and blue encode **which tack you entered
on** — an entry side, not a verdict, not an effort. A rider reading a chart whose *subject*
is "% flew through" and whose *series colour* is ladder green will read the green line as the
flew-through line. It is the same mistake as watch finding §6.1 (green meaning two things on
one screen), and this screen is worse because both meanings are about turns.

**Fix.** Port/starboard is a symmetric pair and needs a symmetric, non-ladder encoding:
either one hue at two lightnesses, or solid vs dashed on a single neutral ink. Add the pair
to `design/tokens.json` as its own `side.port` / `side.starboard` category so it cannot drift
back — and per the contract's own rule, amend `presentation.md` in the same commit.

### 5.3 The Port/starboard chart uses a colour from no vocabulary at all — MEDIUM

Same screenshot, the chart above: a **magenta** line. Magenta is not in the layer catalogue,
not in the ladder, not in the effort set. It is an unowned colour.

**Fix.** Same `side.*` tokens as 5.2.

### 5.4 "Longest flight" is drawn in the takeoff blue — LOW

`ios-trends.png`. Foil time is teal (✅ the phase tint), jibes-flown-through is green (✅ it
genuinely is the flew-through metric), longest flight is **blue** — the effort/takeoff ink,
for a flight-duration metric. Should be the phase teal, like foil time: both are flight
facts.

### 5.5 Trends interpolates straight lines across multi-week gaps — MEDIUM

`ios-trends.png` and `ios-trends-sidesucc.png`. The corpus has one session on 13 Jun and then
a cluster from 31 Jul, and every chart draws a **straight line joining them** — a smooth,
confident six-week trend through territory where no session exists. "Sessions per week" on
the same screen tells the truth (`4 of 22 weeks on the water`), which makes the contradiction
visible on one screenful.

The web states the correct rule explicitly: *"A gap in a line is a session where the value
could not be measured — not a zero."* The contract's own formatter rule is "a missing value
is absent, never 0" — and an interpolated line is worse than a zero, because it invents a
value with no marker to show it was invented.

**Fix.** Break the polyline where the gap between consecutive sessions exceeds a threshold
(two weeks is natural given the weekly bucket below it). Points stay, the connecting segment
does not.

### 5.6 iOS library rows carry the tally; web library rows do not — LOW

`ios-library.png` gives every row `35 · 8 · 8` in ladder inks. `web-06-library.png` gives
`ON FOIL · DISTANCE · FLIGHTS · LONGEST · TURNS · BEST 2 S` — no outcome tally at all. Same
data, same product, and the more prominent surface is the one missing the headline metric.

**Fix.** Add an `OUTCOMES` column to `.lib-table`.

### 5.7 The HR card contradicts itself — LOW

`ios-session-hr.png`: `Pumping vs cruising · -0.1 bpm · 119 vs 119 bpm on the foil`. The
delta says the difference is negative; the two operands, as displayed, are identical. The
contract cares about exactly this class of thing ("a measured zero is a value (`0 bpm`), and
`−0` must never appear").

**Fix.** Either show the operands at the precision that justifies the delta (`119.2 vs
119.3`) or round the delta to the operands' precision (`0 bpm`). Do not print a delta finer
than the numbers it came from.

---

## 6. Navigation & the remaining screens

### 6.1 Spots is a first-class filter and a fourth-level setting — MEDIUM

`ios-settings.png`: Spots lives at **Settings → Places → Spots (2)** — reachable only via
`SettingsView.swift:100`, i.e. gear icon → scroll past help, the intervals.icu key field,
sync, and the Garmin watch section. Yet "All spots" is a top-level filter chip on **both**
Records and Trends. A dimension you filter two tabs by should not be managed inside a modal
settings sheet.

**Fix.** Either surface Spots from the filter chip itself (tap "All spots" → a picker with a
"Manage spots" footer row), or move it beside Gear, which is the same kind of object (a
named thing that sessions reference and that you filter aggregates by).

### 6.2 Records: eight decorated medallions, ~245 pt each — MEDIUM

`ios-records.png`. Each row is a gold gradient disc containing the same text as the label
beside it (`2 s` in the disc, `2 s` as the title), a value, a provenance line, a PB delta,
and a sparkline that is ~90 px wide and essentially flat at that size. Eight of these is
about 2 000 pt of scroll — two full screens for eight numbers.

The medallion is decoration; the sparkline at that width carries no information (all eight
read as a flat line with a bump); the disc duplicates the title. Meanwhile the genuinely good
content — `+1.27 kn on the previous best` — is the smallest text in the row.

**Fix.** A table: `record | value | +Δ PB | date · spot`, with the disc dropped and the
sparkline either widened into a real PB step curve or removed. Keep the row tappable to the
detail. This is the same call as §1.4 and the same taste principle.

### 6.3 Gear: the foil is an aeroplane — LOW

`ios-gear.png`. Wing = a wind glyph (fine), Board = a board outline (fine), **Foil = ✈︎**.
"No unclear icons" is an explicit owner preference, and a hydrofoil rendered as a passenger
jet is the definition of unclear.

**Fix.** A front-wing silhouette, or no icon — the word "Foil" is unambiguous on its own.

### 6.4 Gear empty state asks three times — LOW

Three identical `No X yet` / `+ Add X` cards stacked, plus a "Show retired gear" toggle for a
library containing zero items, plus a paragraph about retiring gear that does not exist.

**Fix.** One empty state ("Add your wing, board and foil to filter records and trends by
kit") with a single button; reveal the three-section layout once anything exists. Hide the
retired toggle at zero items.

### 6.5 Tab-bar icons are good — no action

Sessions/Records/Trends/Gear read correctly at a glance; the trophy and the waves are
unambiguous. Noting it because §6.3 is the exception, not the pattern.

---

## 7. The small-screen web experience

Read from `web/css/style.css` (see §0 caveat — no narrow screenshot).

### 7.1 The responsive layer is genuinely well built — credit, no action

Rare enough to record. Breakpoints at 760 px and 560 px plus a landscape-height rule;
`--tap` enforced as a real 44 px minimum on buttons **and on the legend chips** ("The chips
are the map's filter, so they are real touch targets"); `input { font-size: 16px }` to stop
iOS auto-zoom; `env(safe-area-inset-top)` in the topbar; `min-height: 100dvh` with an
explicit comment that `100vh` is the *largest* viewport on iOS; `overflow-x: hidden` on the
body with `minmax(0, 1fr)` grid columns so a wide table cannot push the page sideways; wide
tables scrolling inside `.table-scroll` with `overscroll-behavior-x: contain`; and
`table.stack-sm` restacking the two *browsing* tables into cards while deliberately keeping
the 34 × 16 turns table tabular ("34 rows × 16 fields as cards would be a mile of page").
That last decision is exactly right and matches the owner's taste.

### 7.2 The page is a phone-hostile length regardless — HIGH

Good mechanics do not fix ~6 000 px of content. On a 430 × 932 phone the session view is
roughly **seven screens before the turns table starts**, then 34 rows, then 23 more. §3.4's
collapsed `<details>` or section switcher is the fix.

### 7.3 Cold analysis blocks the tab for minutes with no ETA and no cancel — HIGH

Measured: the 6.0 MB CIQ fixture sat on **"Analyzing"** for **over nine minutes**, during
which the tab was unresponsive enough that screenshot injection timed out repeatedly. The
progress card (`web-01-loading-progress.png`) shows four steps with sub-labels
(`pyodide 0.28.3`, `engine 0.5.0`, `session.fit`, `6040 KB`) and the note "The runtime
(~12 MB) loads once and is then cached" — but **no elapsed timer, no estimate, no cancel**,
and the sub-label on the slow step is a file size, not progress.

On a desktop this is annoying. On the phone this review is aimed at, a nine-minute unresponsive
tab is indistinguishable from a hang, and the user will kill it — losing the work.

**Fix, in order:** (a) an elapsed counter on the active step, and a one-line expectation
("large CIQ files take several minutes"); (b) a cancel button; (c) if the analysis is not
already off the main thread for its whole duration, move it — `web/js/worker.js` exists, so
the plumbing is there. (a) and (b) are the cheap ones and remove most of the harm.

### 7.4 A visible hole in the tile grid — LOW

`web-02-session-top.png`: ten tiles into a six-column `auto-fit` grid leaves an empty bordered
cell at the end of row two. It reads as a missing metric.

**Fix.** Falls out of §4's hero/detail split; otherwise let the last tile span the remainder.

### 7.5 "Save to library" is the loudest thing on the session — LOW

Full-width filled primary button, sitting directly above the stat grid, wider than any
number. It is a filing action competing with the results.

**Fix.** Right-align it at its natural width beside the source badges (it already goes
full-width below 760 px, which is correct on a phone).

---

## 8. What the presentation contract promises and a screen does not deliver

Checked against `docs/presentation.md`.

| contract clause | status |
|---|---|
| Effort chip labelled with the *selected* window ("best 2 s"), not "best effort" | ✅ both — iOS chip reads `best 2 s`, web reads `best 2 s` |
| Chip text from the layer catalogue's `label` | ✅ both — all ten chips match, in catalogue order |
| Takeoff layer hides both halves with one chip | ✅ both — single `takeoff` chip |
| Filter copy says "Port entry / Starboard entry", never bare left/right | ✅ iOS turns drill-in, verbatim |
| Coverage carried visibly ("23 of 23 takeoffs") | ✅ iOS — `31 of 31 takeoffs`, `25 of 25 rises`, and Trends' `12 of 14 sessions cannot report this · Needs the wrist accelerometer` is a model of honest degradation |
| A missing value is absent, never 0 | ✅ observed |
| **Ladder colours reserved for verdicts** | ❌ **violated — §5.2**, Trends side-success |
| **Colours confined to the documented vocabulary** | ❌ **violated — §5.3**, magenta |
| Phase tint = teal for flight facts | ⚠️ §5.4, longest-flight trend in takeoff blue |
| "−0 must never appear" / deltas consistent with operands | ⚠️ §5.7 |
| One playhead across map and chart | ✅ — and it is the reason §3.2 constrains the tab split |

The two ❌ rows are the only outright breaches, and both are on one screen (Trends). Both are
token-level fixes.

---

## 9. Prioritized punch list

**Status.** Items are marked as they ship. `✅ shipped` means the change is in and its
tests are green; an unmarked item is still open. The two commits that worked this list are
named in the entries.

### Quick wins — small diffs, visible immediately

1. ✅ **shipped (quick-wins commit)** — **§5.2 / §5.3** Stop Trends using ladder green +
   takeoff blue for port/starboard, and retire the magenta. Added `side.port` /
   `side.starboard` to `design/tokens.json` — one hue at two intensities, the quieter half
   dashed — regenerated all four token artifacts (`DesignTokens.swift`, `tokens.css`,
   `tokens.js`, `DesignTokens.mc`), and applied them on **both** platforms: the iOS
   side-success and port-share charts, and the web `turnSide` chart through two new line
   roles (`sidePort` / `sideStarboard`). `presentation.md` amended in the same commit, and
   `PresentationTests.theSideInksBelongToNoOtherVocabulary` now asserts the property that
   made the old spelling wrong. *The only outright contract violations in either app.*
2. ✅ **shipped (quick-wins commit)** — **§1.2** The three legend paragraphs are the
   `mapLegend` help topic, reached by a `?` that flows with the chips. "38 failed attempts"
   is a `Failed attempts` card on the takeoff section.
3. ✅ **shipped (quick-wins commit)** — **§7.3 (a)+(b)** A ticking `mm:ss` clock on the
   active step, a one-line expectation ("large CIQ recordings take several minutes"), and a
   Cancel that terminates the worker and re-warms a fresh one in the background. The
   analysis is one synchronous call into CPython-on-WASM, so terminate is the only thing
   that actually stops it — see the note on `rpc.cancel`.
4. **§5.1** Render `longestFlewStreak` — already computed, never shown.
   *(Superseded in part: the key-metrics block, shipped before this review's punch list was
   worked, already draws `11 dry · 5 flew`. Nothing remains on the session screen; the
   trends screen still never shows a streak.)*
5. ✅ **shipped (quick-wins commit)** — **§5.4** Longest-flight trend is the phase teal.
   Every trend tone is now a token rather than a `Color` literal.
6. ✅ **shipped (quick-wins commit)** — **§5.7** The pumping-vs-cruising operands are
   printed at the delta's own precision, and the printed delta is derived from the printed
   operands, so the card reconciles exactly.
7. ✅ **shipped (quick-wins commit)** — **§6.3** `GearKind.symbol` is now optional and
   `foil` returns nil: there is no SF Symbol that means "hydrofoil", so rather than the
   next-nearest wrong picture the app draws its own front-wing silhouette (`GearKindIcon`).
8. ✅ **shipped (quick-wins commit)** — **§1.5** `TimeAxisTicks` in the kit picks the finest
   step from a ladder of nameable units and labels its multiples; the speed chart and the
   HR-cost chart share it, so they cannot drift apart.
9. ✅ **shipped (quick-wins commit)** — **§5.6** The web library table has an `outcomes`
   column on the ladder's inks. The tally is a new digest field, absent on rows stored
   before it existed, which render "—" rather than three zeroes.
10. **§7.4 / §7.5** Close the tile-grid hole; stop "Save to library" out-shouting the numbers.

### Added after the review, at Jan's request

- ✅ **shipped (quick-wins commit)** — **The web had no sample file.** A first visitor with
  no `.fit` to hand saw a drop target and nothing else. `web/example/ExampleSession.fit` is
  now the same 435 KB recording the iOS app bundles (byte for byte), reached by an
  "…or try the example session — Lago di Garda, 29 Aug" link beside the file chooser. It
  goes through the ordinary `analyzeFile` path, so what it shows is what a real file shows;
  it is precached by the service worker, which is what makes it work for an installed app
  with no network; and GitHub Pages uploads the whole of `web/`, so the deploy needed no
  change.

### Structural — worth planning

11. ✅ **shipped (before this punch list was worked)** — **§1.1 + §4 — the verdict block.**
    `KeyMetrics` / `KeyMetricsView` and the web's `keyMetrics`: four rows above the map,
    pinned by `PresentationTests.keyMetrics*` on both platforms. The structural commit made
    it **permanent** — it sits above the switcher, on every section, and the divergence
    banner moved below it (§1.3), where a provenance footnote about one metric belongs.
12. ✅ **shipped (structural commit)** — **§3 — tab SessionDetail on iOS**:
    `Map · Speed | Turns | Takeoffs | Effort`, sticky, beneath the permanent key-metrics
    block. Map and chart are on one section and everything that annotates them rides along,
    so the shared playhead and the tap-to-focus pairing are intact; the chart's zoom window
    moved up to `SessionDetailView` so a trip to Turns does not silently reset it. §2.1 is
    folded in: the drill-in is the Turns tab's own body, under the turn cards, and the push
    is gone. The section model, its words and the anchor→section mapping live in the kit
    (`SessionSection`), asserted by `PresentationTests.sessionSections*` /
    `everyScrollAnchorResolvesToExactlyOneSection` — a `UI_SCROLL_TO` anchor that resolved
    to no section would silently photograph the wrong tab.
13. ✅ **shipped (structural commit)** — **§1.4 + §6.2 — tables instead of tile walls.** The
    session's speed records are `record | value | at` with the picker's orange selection as
    a row band; the Records tab is `record | value | +Δ PB | when · where` under one header
    row. The medallion is gone (it repeated the title) and the 90 px sparkline with it; the
    freshness it encoded survives as a 7 pt dot, and `+Δ PB` — previously the smallest text
    in the row — is a column.
14. ✅ **shipped (structural commit)** — **§3.4 + §7.2 — the narrow web.** The section
    switcher, not the cheap `<details>` fallback: `Map · Speed | Turns | Takeoffs | Data`
    below 760 px, built from `data-section` attributes so a new panel joins by carrying one.
    Turns and Flight ends share a chip, which is the ~2 000 px §7.2 measured. The fourth
    chip is `Data` rather than `Effort` because the web has no HR content and an empty tab
    is worse than an unmatched label; the `effort` id is reserved for when it does.
    **The desktop scroll is untouched**, and crossing the breakpoint upward restores every
    panel, so no sequence of taps and resizes can strand a desktop reader.
15. ✅ **shipped (structural commit)** — **§6.1 — Spots**, both of the review's options:
    a "Manage spots…" row inside the spot filter menu itself, so the chip that filters by
    spot is the chip that manages them, and a Spots section at the top of the Gear tab,
    which is the tab that owns named things sessions reference. The Settings sheet's
    "Places" section is gone.
16. **§7.3 (c)** Confirm the analysis runs off the main thread end-to-end.
    *(Partly answered by the Cancel work: `entry.analyze_json` is one synchronous call
    inside `js/worker.js`, so it is off the main thread — the tab's unresponsiveness is the
    worker saturating the machine, not the UI thread doing the parse. Whether that can be
    yielded from inside Pyodide is still open.)*

### Deliberately not recommended

All three were re-confirmed while the structural commit was written, and two of them are
now asserted rather than merely intended.

- **Tabs on the desktop web session view.** It is a document and it works as one; the two long
  tables want the continuous page. Narrow viewports only. *(Held: `.sections` is
  `display: none` above 760 px, and `js/sections.js` un-hides every panel on the way back up,
  so no sequence of taps and resizes can leave a desktop reader short a panel.)*
- **A separate "Records" tab inside iOS SessionDetail.** The record picker's purpose is to
  highlight a window on the map and chart; separating them breaks the feature. *(Held: there
  is no `records` case in `SessionSection`, and
  `PresentationTests.sessionSectionsAreTheFourTheReviewSettledOn` asserts both the four
  cases and that the record table's anchor sits on the same section as the two figures.)*
- **Restacking the web turns table into cards on phones.** The CSS already decided against
  this for good reason, and the reason is still good. *(Held: the turns table is untouched —
  the switcher moves the whole panel off screen rather than reshaping what is inside it.)*
