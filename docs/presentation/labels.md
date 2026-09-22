> Part of `docs/presentation.md`. Engine 0.24.0.

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
(docs/algorithms/disciplines.md "Disciplines"), so the pump chips, the "pumps to takeoff" tile, the pump
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
read". Changing it re-derives **this session and nothing else** (docs/algorithms/disciplines.md,
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

