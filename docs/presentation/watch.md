> Part of `docs/presentation.md`. Engine 0.23.0.

## The watch's two layout rules — the equator, and the size ladder

Jan read all twenty-four watch screens off a numbered sheet on **21 September 2026** and gave
a note per page. Two rules came out of it, and every watch page is held to both.

**1. On a round glass the widest line belongs on the vertical centre.** The chord is widest at
the equator and collapses fast towards either arc, so the widest thing a page has to say goes
there and the narrow things — labels, captions, legends, streaks — go above and below it. It
is not a preference: on a 454 px glass the chord at the equator is 450 px and the chord two
text rows down is 380, so a wide row pushed off centre is a row that has to shrink or shed
content for no reason at all.

What it changed, page by page: the Turns page's four-count ladder row is lifted onto the
equator (`RecordingView.turnsBias`, capped at 20 % of the radius so the bottom row never pays
for it); the Tacks & jibes page is two wide rows straddling the centre with a narrow word on
the far side of each; the large set's giant straddles it, which it already did; the post-save
Takeoffs page puts its fraction there. The layout suite asserts the claim rather than trusting
it — `turnsPageFitsRoundDisplay` and `kindsPageFitsRoundDisplay` each check that the wide row's
own ink spans `cy`.

**2. Numbers larger, words smaller.** A label has to be found once; a number is read every
glance. Where a row has a word and a number in it, the number takes the ladder's rung and the
word takes FONT_XTINY beside it — which was already the house idiom (the streak row, the
port/starboard row) and is now the rule. Where a word costs a number a rung, the word gets
shorter, moves to a narrow row of its own, or goes.

What it changed: the large set's word is FONT_MEDIUM rather than FONT_LARGE and sits at the
BOTTOM of the page rather than under the giant; the Clock page's "timer" went entirely and its
second number took the band; the Map page's odometer walks the text ladder from FONT_LARGE
with "km" small beside it, where it had been pinned at FONT_SMALL, the floor; the Story page's
"turns" moved under the dot row so the dots get the width; the Turns page's three inline
captions became one legend on a narrow row of its own; and the Main page's clock went up a
rung on every family whose top arc can hold one (see below — Jan's own cannot).

The one place rule 2 was argued the other way is the foil table's row key, and Jan argued it:
`tot` gave way to **`total`** even though the short word buys the six values a font rung,
because "tot" is an abbreviation a rider has to expand on the most-read row of the table, and a
smaller number you can name beats a bigger one you have to work out. Only the readability floor
may shorten it now (`RecordingView.foilKeys`).

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

### The Main page's clock — a rung raised, and the one glass that cannot take it

Jan's note was two words: *make the clock time bigger*. What it turned into is the most
useful thing this round measured, so it is written down rather than quietly half-done.

The clock is the top row of the page a rider spends the session on, and the top row sits in
the **top arc**, which is where a round glass is narrowest. Its ceiling is
`FONT_NUMBER_MEDIUM` now, one rung above the `FONT_NUMBER_MILD` it had carried since 0.9.2,
and it reaches it on **every shipped family but one**: 26 → 36 px of digit on a fenix 5 Plus,
45 → 53 on an fr255, 55 → 67 on a fenix 7S, 71 → 91 on a venu 2S, 78 → 105 on an Instinct 3
AMOLED, 82 → 102 on an epix 2 Pro, 89 → 116 on a venu 3. On the **fenix 8 47 mm** it does
not: the chord for a 114 px box at that depth is 241 px and a `FONT_NUMBER_MEDIUM` "23:59"
needs about 250. Nine pixels, on Jan's own watch.

Three ways to buy them were tried and all three cost more than the rung is worth, which is
why the page ships as it is:

- **lift the block** (the Clock page's own trick, `CLOCK_BIAS`). 20 px of lift puts the
  streak row's corner 217 px out on a 213 px radius — the bottom row leaves the glass before
  the top row gets its rung. That page has two rows and this one has five.
- **band the clock on `FONT_NUMBER_MEDIUM`'s line** rather than its ink. It does not help the
  fit at all, the box the glass clips being the ink either way, and it pushes the four rows
  under it 30 px deeper for nothing — measured, that is enough to cost the tally row its
  captions.
- **fit per time of day.** "11:49" is narrow enough for the bigger rung and "23:59" is not, so
  the clock would change size during the afternoon. A number that grows and shrinks on its own
  is worse than a number that is one rung small.

So the rung is decided once, on the **worst case** the row can be handed (`mainClockFont`
asks `fitByOwnInk` for "23:59"), and the band is `FONT_NUMBER_MEDIUM`'s ink — 114 px against
`MILD`'s 113 px line, so the stack does not move and no other row pays for the attempt.
`fitByOwnInk` is new and is the honest half of the fix: it measures each candidate against the
chord for **that candidate's own box**, where the app's usual fitter measures every candidate
against the chord for the top one's. Near an arc the box height is most of what decides the
chord, and a fitter blind to that answers "nothing fits" and hands back a text font.

**Open, and Jan's to decide:** the Main page's tally row drops its *flew / touch / fell*
captions on a 454 px glass for any session with three two-digit counts, and has done since
they were added in 0.9.11 — the row's budget there is 380 px and the captioned form needs
more. It is the shed-content rule working as written. It is also three words that the 30-turn
session they were written for never sees.

## The watch's Turns page — one row, four counts, and a mark for the wind

Jan's layout review, 21 September 2026. The page had **six rows** — a header, the tally as the
giant, the clean jibes with their rate, both streaks, the outcome dots, and the flew-through
share with the port/starboard split — and three of them were saying the same thing at three
resolutions. It has **five** now, and one of them is the page:

```
  clean · flew · touch · fell  ↘
       ★34  63 · 21 · 12
    ● ● ● ● ● ● ● ● ● ● ● ● ●
       streak: 4/9  7/12
            P29/S22
```

- **The ladder row is the page**, and it is lifted onto the equator (`turnsBias`). Four counts
  in four inks: the clean jibes behind their star first, then flew · touched · fell with the
  separators drawn as dim **dots**, because the number fonts have no punctuation — which is
  also what lets a separator shrink with the digits instead of pinning a text font's comma
  beside them. One renderer draws it here, twice on the Tacks & jibes page, and on the large
  set's three turn screens.
- **The clean jibes joined the row they refine.** `★ 12` had a row of its own from 0.9.5, and
  a subset printed on its own row is a number the rider has to relate to another number
  himself. First on the row, because it is the strictest rung and the one the product is named
  after.
- **CPH left the watch.** A rate is a *reading* of a count; the count is the fact. It also
  divided by a clock the phone does not have (docs/algorithms.md, the watch divergences), so
  the wrist and the phone printed two different rates for one afternoon. `cleanPerHour` and
  its 60 s no-rate floor are kept in `PageModel` and still tested — the number is one page-set
  decision away from coming back.
- **The "% flew" share left too.** It is `flewCount` over `turnCount` and both of those are
  printed one row up, so the page was stating one fact twice — and a page that says the same
  thing twice has to be believed twice. What is left on the bottom row is the port/starboard
  entry split, which is the one number on the page a rider can act on tomorrow.
- **The header became a legend**, on a narrow row of its own: the same four words in the same
  four inks in the same order. Colour alone was the key until 0.9.11 and the words came back
  then, inline beside each count; moving them off the counts is what buys the counts their
  size (three inline captions cost the row ~90 px on a 454 px glass). It sheds **content**
  and never size — FONT_XTINY is the bottom of the ladder — and the order is separators, then
  the mark: on a 240 px fenix 5 Plus, where FONT_XTINY is 26 px, the full legend is 224 px
  against a 214 px chord.

### The wind is a mark, not a bearing

The header printed the axis — *SW*, or *~SW* where the watch had worked it out. Jan: the rider
does not read a bearing off the Turns page. What he needs to know there is only **whether the
page has an axis at all**, because without one the port/starboard row below it is counting
nothing and the Tacks & jibes page one swipe on is two rows of zeros.

So it is a small arrow (`Glyphs.drawWind`), diagonal so it cannot be mistaken for the vertical
double-headed pump glyph, with **three states in one mark**:

| state | mark | why |
|---|---|---|
| the rider set the axis | **filled** | it is a statement of fact — manual always wins (`Config`) |
| the watch estimated it | **hollow** | the leading `~` the word used to carry, as a shape |
| there is no axis | **hollow, dim** | drawn and not omitted: a missing mark and a mark nobody noticed look the same, and this is the one state the rider can do something about |

The mark is **white or dim and never the outcome ladder's ink**, which is a verdict scale
nothing outside a maneuver outcome may borrow (see "Colour and glyph vocabulary" above). An
axis is not a verdict. The bearing itself is still one long-press away on the start screen and
in the session menu, where it is a number a rider actually sets.

## The watch's Tacks & jibes page

Jan, 21 September 2026, from a tester practising tacks. The Turns page says how the maneuvers
went — flew through, touched down, fell in, the streaks, the dots. Nothing on the watch said
**which maneuvers they were**, although the watch has counted tacks and jibes apart since the
first wind axis. Since 0.9.17 the standard set has an eighth page, straight after Turns, and
the large set has two more screens.

0.9.17 drew it as two **giants** with *flew N* beside each word. Jan's layout review the same
evening re-cut it to read like the Turns page instead: one wide **ladder row** per kind, in the
same four inks and the same order, with the kind's word on the far side of its own row, so the
two wide lines straddle the equator:

```
        jibes
    ★34  39 · 8 · 5
     24 · 13 · 4
        tacks
```

Five decisions in that shape:

- **it is the Turns page's row, twice.** One renderer (`RecordingView.drawLadderRow`) draws the
  session's ladder, both kinds' ladders and the large set's three turn screens. A rider who has
  learned to read one of these rows has learned to read all four on the watch, and the moment
  it was two pieces of code they would drift.
- **the two wide rows straddle the centre**, with the narrow words above the first and below
  the second — the round-glass rule above. 0.9.17's two giants with captions under them put
  four rows of ink on the page and neither wide thing on the equator.
- **tacks have no clean rung, and never will.** `cleanJibeCount` counts clean *jibes*, which is
  the verdict the product is named after. A star over the tack row would be inventing a number
  the engine does not compute.
- **the header is gone where the axis is known.** It said *wind ~NNE* and spent a whole row on
  a bearing nobody reads off this page; the Turns page one swipe back carries the axis as a
  mark instead. It survives for the one state it is the only explanation of — *wind not set*,
  where every turn is a generic turn, both rows are zeros, and the page is uninformed rather
  than broken.
- **aborted turns are on neither row.** A sweep the classifier rejects is a course change,
  not a maneuver, and the watch has no twin of the engine's aborted-turn count at all.

The counts come from `TurnDetector.tackCount` / `jibeCount`, which already ride the FIT
session. The three rungs are **six counters** — `tackFlewCount` / `jibeFlewCount` since 0.9.17,
`tackTouchCount` / `jibeTouchCount` / `tackFellCount` / `jibeFellCount` since 0.9.18 —
incremented where the outcome resolves, because the kind is fixed when the sweep closes and the
outcome when the window resolves and `_resolve()` is the only place that knows both. They are
**not** backfilled by the auto-wind lock, exactly as `cleanJibeCount` is not, so a kind's three
rungs sum to that kind's count for every turn typed after the axis holds and to at most it
afterwards; the invariant and its qualifier are in docs/algorithms.md's watch-divergence list
and asserted by `perKindOutcomesAddUpToTheKind`. No new FIT field — the split the phone needs
is the tack and jibe counts, which have been in the file since 0.9.0.

## The watch's two page sets — standard, and large text

"I need my glasses" (Jan and a tester, 20 September 2026). The standard set packs four to six
numbers onto a screen, which is the right answer on a dry wrist and the wrong one at 25 kn
with spray on the glass. Since 0.9.16 there is a second set, and **one Garmin Connect enum
picks between them** — *Data screens: Standard / Large text* (`pageSet`). One setting, no new
property per page, and it is in **every stream**, which matters because the per-page editor
below is not (see docs/channels.md).

The large set is **five screens, one number each** (seven between 0.9.17 and 0.9.18):

| # | the number | the word under it | also on the page |
|---|---|---|---|
| 1 | live speed | `now km/h` (or `kn`) | — |
| 2 | foil share | `time on foil` | the foil-% bezel arc, earned the ordinary way |
| 3 | turns | `turns` | the session's ladder row — ★clean · flew · touch · fell |
| 4 | jibes | `jibes` | the jibes' ladder row |
| 5 | tacks | `tacks` | the tacks' ladder row (no star: tacks have no clean rung) |

**The five, and the two that left** (Jan, 21 September 2026: "pages 7 and 4 are good enough").
*Time* went because the standard Clock page **is** a giant time of day with nothing on it but
a timer — a large-text screen for the clock was the clock page one rung smaller. *Best 2 s*
went because the standard Records page carries both records with their names, and a set that
answers "how fast was the best two seconds" without saying what the ten was is a worse version
of the page one swipe away.

**Two of the words were rewritten in the same round**, and both for the same reason — a number
nobody can name is not readable however big it is:

- `speed km/h` → **`now km/h`**. Jan, off the sheet: *"is this current speed or a record? which
  metric?"* It is the live speedometer, and it sits one swipe from two record screens in the
  standard set, so the word has to answer *when* as well as *what*. "now" is the shortest true
  answer there is.
- `on foil` → **`time on foil`**. The number is a share of the **minutes**, and its distance
  twin (`M_FOIL_DIST_PCT`) is the same "%" over a different denominator. A page that says only
  "on foil" makes the rider guess which of the two he is reading.

Four rules make it bigger rather than merely emptier:

- **the giant gets the whole stack**, and since 0.9.18 the **top** of it: the order is giant,
  outcome row, word, with the word at the bottom of the page. A label is found once and a
  number is read every glance. The layout suite asserts the large giant is never *narrower*
  than the same value on a hero page, on any glass.
- **the giant leaves the bitmap ladder where the device has a vector face** (0.9.18). Jan
  measured "33.8" at about **55 %** of a fenix 8's width and asked for 70–75 %, and
  FONT_NUMBER_THAI_HOT is the *top* of the bitmap ladder — "as large as the fitter allows" was
  already true and still too small. `RecordingView.bigGiantFont` follows `LockView.codeFont`,
  which has done this for the invite code since 0.9.10, with all three of its hard-won rules:
  the bitmap ladder is the **floor**, never merely the fallback; a face is accepted only if it
  can draw **every character** of the value (on the epix 2 / MARQ 2 / Descent Mk3 families
  `BionicBold` is a digits-only cut and measures a missing "%" at zero width, which every
  fitter reads as "fits"); and the whole block is behind `Graphics has :getVectorFont`, so the
  CIQ 3.x families never enter it. Two rules are this page's own: the face must draw the value
  **wider**, not merely taller, because these cuts are condensed and a taller-thinner number is
  not a bigger one; and the size is **probed once per stack shape and cached**, because the
  giant is redrawn every second and a live speed changes every second. Measured after:
  **66 %** on a fenix 8 47 mm, 71–77 % on the epix 2 Pro, venu 2S / venu 3, fenix 7S and
  fr255 families, and unchanged where no face qualifies.
- **the word is FONT_MEDIUM**, two rungs above every caption on the standard pages, down from
  FONT_LARGE — the rung it gave up is the giant's. It carries its unit, which is the only
  place on the watch where a caption does. It steps down the ordinary ladder on a narrow chord
  and the suite asserts it never falls below FONT_SMALL, the readability floor.
- **no rings.** A flight ring costs 10–16 px of every radius, about 7 % of the digits on a
  240 px glass, and this set's whole trade is radius for digit height. Only the foil page
  keeps its arc, because the arc *is* the number the page already shows.

There is deliberately no map, no timeline and no table in the large set: a page you have to
read is not a page this set is for. And there is no editor for it — the five pages are a
fixed table (`PageModel.buildLarge`) that reads no property at all, which is exactly what
lets it be the one page control every stream has. The three TURN screens carry an outcome row
between the giant and the word, because a count of jibes without a verdict on them says
nothing on its own; the other two are a giant and a word.

**The text-size headroom of the standard pages was reviewed in the same round** and the answer
was to take no rung there (`standardPagesTextHeadroom` logs the measurement per glass). Every
pinned caption — the hero unit line, the records labels, the foil column headers and row keys
— *fits* a rung up in its chord on every glass, and *the stack* holds the taller line only on
the fenix 5 Plus family, whose number fonts carry no leading. Taking the rung would mean two
different page geometries per font set. The MAIN giant's inline unit/caption block cannot move
at all: on that same family it is already the taller box of its band, so a rung up reaches
into the clock row, which is the 0.9.13 bug exactly. The rung went to the large set instead,
where the page spends no rows on anything else and can afford it.

## The watch's show/hide switches — seven screens a rider can drop

**0.9.18, every stream.** Jan: a rider who never reads the Story page should be able to stop
paging through it. Until this round the only way was the per-page editor, which is dev-only,
so a release rider had the page set the table gave him and nothing else.

Seven booleans in Garmin Connect, right under *Data screens*, all default ON — *Show the Foil
page*, *Show the Records page*, *Show the Turns page*, *Show the Tacks and jibes page*, *Show
the Clock page*, *Show the Story page*, *Show the Map page*. One sentence seven times; the
only thing that changes is the page's name.

**Main has no switch.** A rider who turned the last screen off would have no page to turn one
back on from. `PageModel.build` already refused to leave the watch blank, and the page it fell
back to is the page that cannot go.

**The other two sets follow the same seven**, because they are the same pages:

| switch | standard page | large-text screen(s) | after-save page(s) |
|---|---|---|---|
| Foil | Foil | *time on foil* | S·Foil **and S·Takeoffs** |
| Records | Records | — | S·Records |
| Turns | Turns | L·Turns | S·Turns |
| Tacks & jibes | Tacks & jibes | L·Jibes **and** L·Tacks | S·Kinds |
| Clock | Clock | — | — |
| Story | Story | — | S·Story |
| Map | Map | — | S·Track |

Three screens have no switch and never will: **Main**, the large set's **live speed** screen
(the same argument one set down), and the after-save **Saved** page, which is the
acknowledgement the rider pressed for and what the page-position dots count from. *S·Takeoffs*
follows **Foil** because it is the one after-save page with no live twin to inherit from, and
what it counts is how often he got onto the foil.

The after-save review follows the switches at all because it IS the live pages since 0.9.18 —
six of its eight are their live twins drawn by the same code. A rider who hides the Story page
and still finds it in the review has found a second page set nobody told him about.

**In the dev stream the per-page editor still decides what each page is**, and the switch then
decides whether that page is drawn: `build()` reads the editor's layout first and filters on
the switch afterwards. Two questions, asked in that order.

**A settings edit arrives mid-session** — that is what a phone-editable setting is for — and
`WingfoilApp._applySettings` rebuilds the model and re-wraps `PageNav.index` behind it. On this
runtime an index past the end of the page list is an uncatchable error, so a rider standing on
the Map page when its switch goes off is not a glitch waiting to happen; it is the app dropping
to the watch face with his recording in it. `aSwitchThrownMidSessionNeverStrandsTheRider`.

**The screenshot harness ignores all seven** (`PageModel.showAll`). A sheet is a check on the
layouts and it photographs every page the app can draw, whatever the simulator's property
store says.

## The after-save pages and the live ones

A saved page and a live page showing the same number must be the same piece of code, or the
two start disagreeing about one session. Jan's layout review of 21 September 2026 put it as a
target rather than a case-by-case judgement — *identical to the live pages wherever possible*
— and **six of the eight** are now exactly that.

| after-save page | verdict | why |
|---|---|---|
| S1 **Verdict** (foil % + arc, SAVED pill) | **genuinely post-save** | it is the landing page and its subject is the session as a whole. The SAVED pill and the phone line live here and nowhere else |
| S2 **Records** | **unified, 0.9.18** | was a bespoke speed hero — best 2 s as the giant, "10s 11.5" under it, the session odometer under that. Two of those three are the live Records page's own two, drawn a different size in a different arrangement with a different word for each, which is how two screens showing one session start disagreeing about it. `drawRecordsBody`. What the unification **drops** is the odometer: it is on the live Map page under the trail and on S8, and a number with a home on exactly one of two screens showing the same session is the problem this table exists to fix — but it is now on two *conditional* pages, and that is the open question this round leaves |
| S3 **Foil** | **unified, 0.9.16** | was a bespoke "Flights" hero (longest flight, its distance, the count). Every one of those numbers is on the live foil table already — `max` is that flight's two numbers under the two columns that name them — and the table says four more besides. The **flight count** rode the table's title row (`foil · 31`) from 0.9.16 to 0.9.18 and came off in the layout review: a table of six foil numbers with a seventh in its own title is a title that has to be read rather than found, and the count is not a foil number. It is FIT session field 36 and on the phone's session page |
| S4 **Turns** | **unified, and since 0.9.18 with no flag at all** | it was `drawTurnsBody(dc, c, live=false)`, which showed the two streaks as their session bests alone. The run he ended on **is** a fact about the session — "I finished on a run of seven" is the sentence a rider says in the car park — and it is the same reading of the same two numbers he had one button press earlier. The parameter stays on the renderer: the two forms are a real distinction and a renderer that can only draw one of them has to be edited to get the other back |
| S5 **Tacks & jibes** | **unified, born unified** (0.9.17) | `drawKindsBody`, with no flag at all: two ladder rows are the same eight numbers before and after the save. Shown only when the session has a tack or a jibe to name — without a wind axis both rows are 0, and a page that would say 0 is not a page |
| S6 **Takeoffs** | **genuinely post-save** | no live twin exists; the watch has no takeoffs page on the water. Every line of it was rewritten in 0.9.18 — see below |
| S7 **Story** | **unified** (since 0.8.1) | the timeline, verbatim. `history` is complete and untouched by the save, and a coffee-in-hand read of the session arc is what it was always for |
| S8 **Track** | **unified** (since 0.9.2) | `TrackDraw`, the same renderer as the live map page, minus the position marker — the rider is ashore |

What is **not** unified, and deliberately: the SAVED pill does not ride the reused pages. S2,
S3, S4, S5, S7 and S8 look exactly like their live twins, and adding the eyebrow to them would
mean finding a free top arc on six pages whose top rows are already a legend, a title, a word,
a caption, two records and a map — which is the 0.9.13 overprint waiting to happen on six pages
instead of one. The page-position dots along the bottom are what says "this is the review, not
the water", and they are on every one of the eight.

### S6 Takeoffs — three numbers that had to say what they were

Jan read `39/56`, `4.3 to foil` and `+19 bpm` off the sheet and could not say what any of the
three were. That is pattern **H** of docs/review-checklist.md — a bare code the rider has to
decode — applied to numbers rather than to letters. What they actually are, and what they say
now:

| was | is | what the number is |
|---|---|---|
| `39/56` | **`39 of 56`** | takeoffs out of **attempts**: he pumped 56 times and got up 39 of them (`PumpDetector.successes` / `attempts()`). The slash said *per* as often as it said *of* |
| `4.3 to foil` | **`4.3 pumps each`** | the average strokes a takeoff took, over every takeoff including the free ones (`avgPumpsX10`, FIT session field 37). "to foil" named the destination and not the number |
| `+19 bpm` | **`last +19 bpm`** | what the **last** takeoff cost his heart — the rise from that effort's start to its peak (`HrCostTracker`). It is one takeoff and not an average, and beside an average a bare "+19 bpm" reads as another average |

The word *takeoffs* is the small line above; the fraction is the wide line on the equator; the
other two share the narrow line below it, and the HR half is the first thing a narrow chord
gives up — it is the only number on the page about one maneuver rather than the session. The
fraction is drawn as **three pieces** — the two counts in the number ladder around "of" at
FONT_XTINY — because a number font has no letters, which is the bug `fitGiant` exists to stop.
Every `--` the old page printed is simply absent: a takeoff that was never priced is not a fact
about the session, and a row that is not there says that better than a row of dashes.

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
`phone 4/13` while pages are moving, `phone ok` when everything is across, and null when there
is nothing to say, which is what a release or beta build always gets.

**Since 0.9.18-dev1 there is a second wait, and it says so in its own word**: the wrist
stream follows the recording (docs/transfer-format.md §2b), so the line reads `phone 4/13`,
then `wrist 2/8`, then `phone ok`. Two words rather than one counter over both, because they
are two waits and the second one starts after the rider has already been told the first is
done — a counter that jumped from 13/13 back to 2/8 would read as a transfer going backwards.
"wrist" is the word the app uses for the accelerometer on every other surface.

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

And **one short buzz** when the **last** stream is whole, on a channel of its own
(`CH_PHONE`) — the recording's own completion is silent where a wrist stream follows it,
because one tick means "you can walk away" and that is not yet true. It
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

