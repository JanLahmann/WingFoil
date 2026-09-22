> Part of `docs/presentation.md`. Engine 0.23.0.

## Key metrics — the block that opens the session

Both apps open the session analysis with the same block, above the map and the chart, in
the same four rows, numbers big and labels small. It exists because `app-ui-review.md` §1.1
measured the alternative: on a 6.9″ phone the first actual result sat one and a third
screens below a map, ten legend chips and three paragraphs of legend documentation.

| row | content |
|---|---|
| 1 | duration (`10:45 min` / `1:57 h`) · distance · average speed |
| 2 | the best 2 s record, labelled **"max 2 s"**, in the largest type · beside it **5×10 s** and **alpha 500** at the ordinary size, "—" where the session produced none (since 6 Sep 2026). These two are **block-only**: the share card is the block *minus* them — one speed on a card, the one a rider quotes; the Records page owns the set. The web renders them with the `extra` class, which is how `card_parity.mjs` tells them apart |
| 3 | the jibe tally on the ladder's inks · **the tack tally beside it** where the session had tacks (22 Sep 2026) · every fall of the afternoon · the two turn streaks |
| 4 | **JPH** (dry jibes) and **WPH** (`docs/algorithms/rates.md` "Session rates"), one decimal |

The rules, which are the only thing the two implementations can disagree about:

- **Duration is `M:SS min` under an hour and `H:MM h` at or above one.** It was `h:mm` at
  every length, which printed **`0:11`** for the ten minute forty-five second example
  session — the two interesting digits rounded away, and a leading zero where the number
  should be. Survivable on a page a rider can scroll past; not survivable on the share
  card, which is a PNG in somebody else's chat thread with no re-render and nothing beside
  it to check against. A short session is exactly the kind a rider shares.
  - **The unit rides inside the value**, as `km` and `kn` do in every other cell of this
    block. That is the block's own habit, and it settles the ambiguity the bare digits
    create: `10:45` under the word "duration" reads as ten and three quarter *hours* as
    easily as minutes, and at cell size on a card there is no second number to resolve it
    against. It also keeps the card's caption slot free — the tally owns that.
  - **Colons, not "10 m 45 s".** A colon is what a clock looks like, it stays narrow at
    75 px type, and it is the shape the flight table and the replay caption already print.
  - **Rounded, never truncated** — to the nearest minute above the hour, to the nearest
    second below it. `0:00` over a recording that exists reads as a failure to measure.
  - Implemented as `KeyMetrics.duration` (Swift) and `hm` (web/js/cardstats.js), with a
    third spelling in `verify_presentation.py` §5 so the two are checked against a rule
    rather than against each other. The engine's `durationS` is untouched: this is display.
- **Average speed is converted to knots.** The engine reports `avgSpeedKmh`, but every
  other speed in both apps is knots, and a km/h number in a column of knots is a misread
  waiting to happen. It is a session-shape number — elapsed time, gaps included — and never
  a record: the GP3S block is still the only place records live.
- **Row 2 names the window, not the peak.** "max 2 s", the same rule the record picker's
  chip follows; "max speed" over a 2 s window would be the overclaim that rule exists to
  prevent.
- **Row 3 is the jibe ladder**, and the caption says what the three numbers are out of and
  how many were **clean** ("of 50 jibes · 12 clean"). A session whose wind axis never
  resolved has no jibes at all, so it falls back to every counted turn ("of 51
  turns") — an empty ladder over an afternoon of turns would read as "nothing
  happened". The tally is a verdict, so it may wear the
  ladder, and the **library row** wears it too — over every counted turn there, which is
  what a row scanned against its neighbours has to be. The web rows carried no tally at all
  until §5.6, on the more prominent of the two library surfaces; a row from a digest
  written before the field existed renders "—" rather than three zeroes.
  - **The clean count rides in the caption, not in a cell.** It is `jibesSuccessful` — the
    clean count — against the jibe ladder, and **the turn fallback carries no clean clause
    at all**: it read `turnsSuccessful` there, which is the score verdict over every counted
    turn printed under the word for a stricter, jibe-only one, and a session whose wind axis
    named no jibes has no clean jibes to report. The fallback caption is "of 51 turns", full
    stop (7 Sep 2026). A fifth cell on row 3 is a cell the streaks pair would lose, and the
    count is a *qualification* of the tally rather than a metric standing beside it. It stays
    in neutral ink — see "Clean jibe" above.
- **The tacks get the same ladder, beside the jibes** (22 September 2026). The engine has
  typed both kinds of turn since 0.3.0 and this block only ever drew one of them, so a rider
  who tacks read an afternoon with a quarter of its maneuvers missing from the one place
  that sums it up. The cell is the jibe tally's twin — the same three counts, the same three
  inks, the same words under them — and only the caption differs: **"of 14 tacks"**, or "of
  1 tack".
  - **No clean clause, ever.** `tacksSuccessful` is the engine's *score* verdict and
    `turns.py` says outright that it must never be called clean: clean is a jibe word in this
    product and a tack has no clean/dirty reading to carry. The Tacks card on the Turns tab
    dropped its fourth number for the same reason, and this cell was never given one.
  - **Two gates, not one:** `turns.tacks > 0` **and** `turns.jibes > 0`. The second is the
    one worth writing down — when the wind axis named no jibes the cell above has fallen
    back to the ladder over *every counted turn*, and on such a session those turns are the
    tacks, so a second cell would print one set of numbers twice under two captions
    (`docs/review-checklist.md`, pattern F).
  - **It is a card cell too**, straight after the jibe tally, because the card is the block
    (`ShareCardStats`). It is not a `lean` key: lean is the four a rider quotes walking off
    the water plus the honest fall count, and a tack ladder is neither.
  - **Row 3 therefore holds four cells on a tacking session.** The web's `auto-fit` grid
    wraps them by itself; iOS takes the two-column layout it already uses at accessibility
    sizes, because `63 · 1 · 6` does not fit a quarter of a phone.
- **Streaks are `summary.turns.longestFlewStreak` / `longestDryStreak`**, rendered
  `5 flew · 11 dry` — the first time either app draws them. They are over counted turns,
  which is what the engine measures them over; nothing is re-derived here.
  - **Flying leads the pair.** The flew run is the harder of the two and the one the rider
    is chasing, and `longestFlewStreak <= longestDryStreak` always — so the pair reads
    strict-then-lenient, the same order the watch's Turns page has always drawn it in
    (`drawStreakRow2`: green run, then orange run). The block used to lead with dry, which
    put the two surfaces in different orders for one fact.
- **JPH is dry jibes, and the label says so.** The engine's `jibesPerHour` counts the jibes
  he came out of still sailing (`docs/algorithms/rates.md` "Session rates", engine 0.7.0), so the
  cell is captioned **"JPH · dry jibes per hour"**. A rate that counted the swims too could
  be raised by falling more often, and a caption reading "jibes per hour" over a number that
  excludes seven of them would name a different figure than the one printed.
- **CPH sits beside JPH, never instead of it** (engine 0.10.0). `cleanJibesPerHour` is the
  strict verdict per hour — the jibes he flew all the way through carrying his speed — and
  the cell is captioned **"CPH · clean jibes per hour"**. The two are on the row together
  because they answer the two questions a rider asks in exactly that order: *did I come out
  of it still sailing*, and *did I ride it*. Neither is derivable from the other. 2026-08-03
  pm is the session that makes the point — **4.5 JPH beside 0.0 CPH**, fifteen jibes he
  mostly stayed out of the water on and did not ride one of — and a block printing either
  number alone would be answering half the question. The pair reads lenient-then-strict, the
  same direction the tally reads when its caption qualifies the three counts with the clean
  number.
  - **CPH never wears the outcome ladder's inks**, here or anywhere — see "Clean jibe"
    above. It is a rate in the block's ordinary type, like every other cell on the row.

**The clean jibe is a personal best, and it gets the celebration.** Until engine 0.10.0 every
record the app celebrated was a speed. The two that were missing are the ones a wingfoiler
actually chases, and they are kept beside the nine (`CleanJibeRecordKind`,
`PersonalBestDetector.cleanJibeBests`):

| record | what it is | why it is separate |
|---|---|---|
| **Clean jibes** | most clean jibes in one session (`SessionRow.jibesSuccessful`) | the afternoon he rode the most |
| **Best CPH** | best `jibesSuccessful / (durationS/3600)` | the afternoon he rode them *fastest*, which a short evening in good wind wins |

- **A session must last one rate window (15 min) to hold the CPH record.** The rolling
  window's "never a flattering peak" rule (docs/algorithms.md) applied to a session: one
  clean jibe in a four-minute sail is fifteen an hour, and a personal best a rider can set by
  going home early is not one. The *count* takes no such floor.
  - **The floor is on the records table too**, not only on the celebration (7 Sep 2026).
    `SessionRecordKind.bestCph` and `library._cph_record` apply it; before that the table
    had no floor and the confetti did, so "Best CPH" could name two different afternoons
    in one app. It bites on this corpus: the highest CPH of all belongs to a session under
    eleven minutes, and `verify_library.py` asserts that it does not hold the row.
- **Ties keep the earlier session**, the way the window peak keeps the earliest window.
- **One burst for both kinds.** A speed record and a clean-jibe record are the same moment to
  a rider, so `RecordsView` fires one confetti burst and one haptic for either, with a line
  above the table naming what was beaten — the two records have no row in a table of knots,
  and a count of jibes in a column headed `kn` is the one thing a records screen may never
  print. A snapshot written before the pair existed celebrates nothing, exactly as an empty
  snapshot does: the first measurement beats nothing.
- **The replay says it too.** `ReplayCommentary` gains a `cleanJibe` beat on the same
  ordinals the dry count uses — "First clean jibe!", "5 clean jibes" — ranked *above* the dry
  line, so a jibe that is both the fifth dry and the third clean is announced as the clean
  one. It survives a tighter clip budget than an ordinary jibe ordinal and never outranks a
  streak record.
- **Row 4 degrades JPH to TPH, not to zero — and CPH goes with JPH.** When the wind axis
  named **no jibes** while turns were counted, the row shows `turnsPerHour` labelled TPH,
  **and no clean-jibe cell at all**: CPH is a jibe rate, and "0.0 clean jibes per hour" over
  a session that named no jibes would be the precise lie the TPH fallback exists to avoid.
  Where jibes *were* named, a `0.0` CPH is a measured verdict and is printed as one. WPH
  needs no fallback: a fell-in flight end is a fall whatever the wind was doing. A session
  with a duration and genuinely no turns keeps JPH and CPH at `0.0`, because those are
  measured zeroes.
  - **The gate is `turns.jibes > 0 || turnsPerHour <= 0` — the jibe *count*, not the jibe
    *rate*** (7 Sep 2026). It was `jibesPerHour > 0`, and a rate cannot tell "the wind axis
    named no jibes" from "it named fifteen and he swam out of every one": both read
    `jibesPerHour == 0` beside a positive TPH. The second is a session made entirely of
    jibes, and it was getting the TPH fallback and no CPH cell — the exact inverse of the
    rule above. `turns.jibes` is what row 3's tally already gates on, so the two rows can
    never disagree about whether the afternoon had jibes in it. No corpus fixture is that
    session, so both platforms write it down: `card_parity.mjs`'s `allWetJibes` case
    (asserted by `verify_presentation.py` §5a) and
    `PresentationTests.keyMetricsKeepBothJibeRatesWhenEveryJibeWasSwum`.
- **No duration, no row.** `durationS <= 0` makes the engine report all four rates as
  null, and row 4 disappears — the general rule ("a missing value is absent, never 0")
  applied to the one place where a 0.0 would read as a verdict on the rider.

