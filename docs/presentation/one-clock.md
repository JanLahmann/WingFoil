> Part of `docs/presentation.md`. Engine 0.25.0.

## One clock — every duration a rider sees is the engine's cleaned span

**A session's length is `summary.durationS`, everywhere it is printed.** That is the
engine's own cleaned elapsed span: last minus first *cleaned* sample, gaps included. It is
already the denominator of all four session rates and of average speed, and as of
7 Sep 2026 it is also the number every surface *shows*.

There were four clocks in circulation and three of them reached the rider:

| clock | what it is | where it used to be printed |
|---|---|---|
| **cleaned elapsed span** (`summary.durationS`) | the engine's own | the key-metrics block, the period block's hours |
| raw sample span | last − first *raw* sample, pre-clean | iOS `SessionRow.durationS`: the library row, the Distance card's caption, "Longest session", the widget, the week histogram, the gear rollup |
| FIT `total_elapsed_time` | the file's own field | the web session tile's "Duration", the web "Longest session", the week bar's tooltip |
| FIT `total_timer_time` | the file's own field | the web tile's "moving …" note — **still there, and correct**: that note is about the file's moving time |

They are not close. On the corpus's Rheinstetten afternoon the cleaned span is **7742 s**
and the raw one **10338 s** — 43 minutes — so the block said `2:09 h` while the tile eight
points below it said `2:52:18`, of a different clock, and the same rider's "Longest
session" record was a different number on the phone and on the web.

- **iOS** reads `SessionRow.rateSeconds` (`rateDurationS ?? durationS`, schema v12 — the
  column already existed for the period block). `durationS` stays exactly where it was: it
  is the dedupe key and the stored id, and neither may move.
- **The web** reads `summary.durationS` on the session page and `library._rate_duration_s`
  (`rateDurationS ?? durationS`) over stored digests.
- **Rate denominators are a separate question, and since engine 0.13.0 a separate clock.**
  The rule, in one line: **every displayed duration is T1 (the cleaned elapsed span), every
  rate denominator is timer time (T2, total minus pauses).** `foilPct`, `avgSpeedKmh` and all
  four per-hour rates divide by T2 (`docs/algorithms/rates.md`, "Session rates"); everything in
  this section is about the other half, what is *displayed*.
- **A period obeys the same split**, which is what closed the last gap on 7 Sep 2026: the
  block's "hours on the water" sums T1 and its CPH and WPH divide by summed T2, so a month
  holding one afternoon prints that afternoon's own rate. Stored as `timerTimeS` on both
  sides — digest schema 9, GRDB v13 — because a rate a *library* computes has to reach the
  same denominator as the session page without re-reading the recording. The accessors are
  `library._timer_s` and `SessionRow.timerSeconds`, and their duration twins are
  `library._rate_duration_s` and `SessionRow.rateSeconds`; a call site picks by asking what
  the number is, not by which one is nearer.

**One duration formatter per platform**, the one this document already specifies —
`M:SS min` under an hour, `H:MM h` at or above one, rounded not truncated, unit inside the
value: `KeyMetrics.duration` (Swift, public for exactly this reason), `hm`
(web/js/cardstats.js), `library._f_clock` (period blocks), and `_hm` in
`verify_presentation.py` as the independent third spelling. `Fmt.duration` (`1 h 24 m`),
`hms()` (`h:mm:ss`) and `FlightPairing.clock` survive only for a **clip or a flight** clock,
which is minutes and seconds by design and is commented as such where it is used.

