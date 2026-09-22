> Part of `docs/algorithms.md`. Engine 0.24.0.

## Session rates (phone, engine ≥ 0.6.0) — `durationS` · `avgSpeedKmh` · `turnsPerHour` · `jibesPerHour` · `cleanJibesPerHour` · `wetPerHour` · `windowRates`

A tally answers "how many"; a rate answers "how busy". Forty jibes is a good session in an
hour and a slow one in four, and until 0.6.0 nothing in the summary could tell those apart —
the document carried counts and a foil percentage, and every "per hour" a screen wanted had
to be improvised from `foilTimeS`, which is the wrong denominator for all of them.

Seven fields in `summary`, all phone/web analysis outputs — **nothing here is written to the
FIT** (docs/fit-schema.md is untouched by this version):

| field | definition | units |
|---|---|---|
| `durationS` | last − first sample of the **cleaned** track (T1, gaps included) — the duration every surface *displays*, and since 0.13.0 **not** a denominator | s, 1 dp |
| `timerTimeS` | Σ dt over the non-gap steps (T2) — the session minus its pauses. **The denominator** (engine ≥ 0.13.0) | s, 1 dp |
| `avgSpeedKmh` | `records.distanceM / timerTimeS × 3.6` | km/h, 2 dp |
| `turnsPerHour` | **dry** counted turns: `(turns.turnsCounted − turns.outcomes.fellIn) / (timerTimeS/3600)` | 1/h, 1 dp |
| `jibesPerHour` | **dry** jibes: `(turns.jibes − turns.jibeOutcomes.fellIn) / (timerTimeS/3600)` | 1/h, 1 dp |
| `cleanJibesPerHour` | **clean** jibes: `turns.jibesSuccessful / (timerTimeS/3600)` | 1/h, 1 dp |
| `wetPerHour` | `flightEnds.all.fellIn / (timerTimeS/3600)` | 1/h, 1 dp |
| `windowRates` | the rolling `windowRateMin`-minute view of the same two events (below) | object |

**One denominator, and since engine 0.13.0 it is timer time.** The question every one of
these answers is "per hour *on the water*", and an hour the recorder was not running is not
an hour on the water. `timerTimeS` sums the non-gap steps of the *cleaned* track — the same
timeline every other summary number was measured on — so a Smart-Recording hole, a paused
lunch break, or the twenty minutes the board spent on the beach come out of the divisor.
Until 0.13.0 the rates divided by the elapsed span (T1) and every one of them was deflated
by exactly those minutes: on the Rheinstetten afternoon that is 7742 s against 4712 s of
timer, and a JPH of 13.0 that should have read 31.3.

`durationS` stays in the block and keeps its meaning — a rider who jibes forty times in two
hours of drifting between gusts and one who does it in one are not having the same afternoon,
and T1 is what says so. It is what every surface prints as the session's duration. The two
are two named keys rather than one blurred number.

`avgSpeedKmh` moves with them: it is still an honest moving-plus-waiting average, well below
`distanceKm / foilTimeS`, and still a session-shape number and never a speed record — the
GP3S block remains the only place records live.

**TPH counts dry turns** (engine ≥ 0.13.0). The numerator is `turnsCounted −
turns.outcomes.fellIn`: the same "dry" rule JPH has applied since 0.7.0, read over every
counted turn. A swim is not a maneuver made, and a busy-ness number a rider can raise by
falling is not a measure of his afternoon.

**JPH counts the jibes he sailed out of** (engine ≥ 0.7.0). The numerator is `turns.jibes −
turns.jibeOutcomes.fellIn`, i.e. `flewThrough + touchdown` — a touchdown counts, because
pumping straight back up out of one is a jibe he made, and a swim does not, because it is a
jibe he did not. The alternative is a headline number a rider can raise by falling more
often, which is the one thing a rate on the front screen must never reward. On 2026-08-29
that is 47 of 50 jibes: **25.1** an hour where the all-jibes count read 26.7.

**CPH counts the jibes he *rode*** (engine ≥ 0.10.0). `cleanJibesPerHour` is
`turns.jibesSuccessful` over the same hour — the strict verdict, a counted jibe flown all the
way through carrying its speed (docs/presentation/clean-jibe.md "Clean jibe"), which is the engine's
per-turn `clean` flag and not a new measurement. Same denominator, same 1 dp, same
null-on-no-duration rule. The two jibe rates are deliberately both here because they answer
questions a rider asks in that order: JPH says he got away with it, CPH says he rode it. On
2026-08-29 that is 24 of 50 jibes, **12.8** an hour against JPH's 25.1; on 2026-08-07 it is 3
of 30, **2.6** against 20.3 — a 4.9× gap between the two sessions where the dry number,
which forgives every touchdown, sees only 1.2×. CPH is the harder number to move and the
one the front screen carries (docs/presentation.md, key metrics).

Since 0.12.0 **CPH nests inside JPH by construction** rather than by luck: clean requires
`flew_through`, dry is `flewThrough + touchdown`, so every clean jibe is a dry one and the
rate can never stand above it. Before 0.12.0 the nesting held on every fixture but was not
guaranteed — `success` was blind to the outcome, so a session of high-scoring swims could
in principle have printed a CPH above its JPH. The numerator fell on eleven of the seventeen
fixtures when the rule narrowed (e.g. 2026-08-29: 25 → 24; 2026-08-02: 14 → 9), which is the
size of the population that had been carrying its speed and still getting wet.

`turnsPerHour` beside them is deliberately **every kind** of counted turn — tacks, jibes and
unclassified alike — and not only jibes. The three answer different questions: "how busy was
the afternoon", "how many jibes did I sail out of", "how many did I ride". What all three now
share is the dry rule: a maneuver that ended in the water is not one the rider made, on any
of the three.

**Wet is every fall, not every fallen jibe.** `wetPerHour` counts **all** `fell_in` flight
ends — straight-line swims and turn-owned swims alike (`flightEnds.all`, which is exactly
`straight.fellIn + inTurn.fellIn`). Deliberately *not* the turn ladder's `turns.outcomes.
fellIn`: on 2026-08-29 that would read 4 where the rider swam 25 times, because 21 of his
swims happened outside a counted turn — the same blind spot documented under "Turn streaks",
and one the 12 s outcome window of engine 0.13.0 widened on purpose (a fall a quarter of a
minute past a sweep is a straight-line fall, not that turn's). The two channels count
genuinely different events and neither bounds the other: a mid-turn swim that never ended a
flight is a `fell_in` **turn** and no flight end at all, which is why 2026-06-13 reads 2 turn
falls against 9 fell-in ends while 2026-08-29 reads 4 against 25. The rider-facing question
is "how often did I get in the water", so the flight-end channel — one event per actual
swim — is the one that answers it.

**A period divides by the same clock a session does.** A month, a season, a trip or a typed
range prints JPH/TPH/CPH/WPH over `Σ timerTimeS` — never over `Σ durationS`, which is what
the aggregate block's "hours on the water" sums and is a *duration*, not a divisor. The rule
in one line, and it holds on both platforms: **every displayed duration is T1, every rate
denominator is timer time.** Until 7 Sep 2026 the period block summed T1 for its rates too,
so a month holding one afternoon reported a CPH *below* that afternoon's own page — every
paused break the rider took deflating his own month. Both stored clocks exist for exactly
this: a library computes a rate without re-reading the recording, so the row has to carry the
denominator (digest schema 9 `timerTimeS` / `library._timer_s`, GRDB v13 `timerTimeS` /
`SessionRow.timerSeconds`; their duration twins are `rateDurationS` / `_rate_duration_s` and
`rateSeconds`). A row saved before those columns falls back one step at a time — timer →
elapsed → the row's own duration — which under-states the rate by whatever the recorder sat
paused, and is a smaller error than dropping the afternoon out of its own month.

**No timer time, no rate.** `timerTimeS ≤ 0` (a one-sample track, an empty clean) makes all
five derived values **null**, never 0.0 — and both window peaks with them, over an empty
series. Zero would claim "he did nothing in an hour on the water"; null says there is no hour
to divide by. `durationS` and `timerTimeS` themselves stay 0.0. Rates are computed from
unrounded inputs and rounded only on the way into JSON.

Corpus, for scale — the two CIQ sessions, regenerated from `fixtures/goldens/` at
engine 0.13.0:

| session | `durationS` (T1) | `timerTimeS` (T2) | `avgSpeedKmh` | `turnsPerHour` | `jibesPerHour` | `cleanJibesPerHour` | `wetPerHour` |
|---|---|---|---|---|---|---|---|
| 2026-08-07 am (30 counted turns, 30 jibes of which 7 wet, 3 clean, 16 fell-in ends) | 5080.0 | 4088.0 | 11.24 | 20.3 | 20.3 | 2.6 | 14.1 |
| 2026-08-29 pm (51 counted, 50 jibes of which 3 wet, 24 clean, 25 fell-in ends) | 7029.0 | 6748.0 | 12.26 | 25.1 | 25.1 | 12.8 | 13.3 |

Read the two clocks first: the morning lost nearly a thousand seconds to gaps and the
afternoon barely twenty per cent of that, which is why the morning's rates move the further
when the denominator becomes T2. The afternoon is still the busier *and* the faster session,
and it is now the *drier* one per hour too — 13.3 swims against 14.1 — where on the elapsed
clock the morning looked better. That flip is the point of the change: the two afternoons
were never being compared over the same kind of hour.

TPH and JPH read the same on both sessions here because almost every counted turn on this
corpus is a jibe; where a session carries tacks the two part. CPH is where the pair actually
separates: 2.6 against 12.8, a 4.9× gap, where the dry numbers differ by 1.2×.

### The rolling window — `summary.windowRates` (engine ≥ 0.7.0)

A session average over two hours cannot say *when* the rider was going well, and the busiest
quarter of an hour is the part he remembers. `windowRateMin` (**15 min**) is slid over the
session and the same two event channels are counted inside it:

* **dry jibes**, each at its turn's own `ts` (the sweep's start), the `jibesPerHour`
  numerator event for event; and
* **wet flight ends**, each at its end's own `ts` — every `fell_in`, the `wetPerHour`
  numerator.

```json
"windowRates": { "windowMin": 15, "bestJph": 60.0, "bestJphStartTs": 3720.0,
                 "bestWph": 24.0, "bestWphStartTs": 2154.0,
                 "series": [ { "ts": 0.0, "jph": 8.0, "wph": 4.0 }, … ] }
```

**The series is a 60 s grid; the peak is not read off it.** One point a minute, the first at
the session's own first cleaned sample, the last a full window before its end — coarse
enough to keep a two-hour session's series reviewable in a golden, fine enough to draw. The
two peaks are the *exact* sliding maxima instead, found by anchoring the window on the events
themselves: the count in `[s, s+W)` can only be highest where the window opens on an event,
so those instants (plus the two ends of the allowed range) are the whole candidate set. Ties
keep the earliest window. `bestJph ≥ max(series.jph)` therefore always holds, and often
strictly — on 2026-08-29 the busiest wet quarter-hour reads 24 an hour where the grid saw 20,
because no minute-aligned window happens to hold all six of those swims at once.

**Never a flattering peak.** Only windows lying **wholly inside** the session count: a
three-minute burst scaled ×20 is a lie, and it is exactly the lie a peak invites. A session
shorter than one window has no full window at all, so its peak *is* its whole-session rate
over the span it actually lasted — the 60 s smoke fixture reports one series point and a peak
equal to it, flagged as nothing special because nothing special happened. This is the mirror
of the never-a-flattering-zero rule the four rates follow (docs/testing.md): an absence must
not read as a verdict, and a fragment must not read as a peak.

Implemented once per engine: `session_rates` / `window_rates` in
`lab/src/wingfoil_lab/goldens.py`, `SessionRates` / `SessionWindowRates` in
`ios/WingFoilKit/…/AnalysisEngine/SessionAnalysis.swift`. The watch does not compute any of
them (it has no flight-end classifier and no cleaned track); the phone recomputes them on
import like every other summary number.

