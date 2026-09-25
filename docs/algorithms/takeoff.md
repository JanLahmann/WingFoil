> Part of `docs/algorithms.md`. Engine 0.25.0.

## Takeoff analysis (phone) — pumps-to-takeoff · attempts · in-flight pumping

The flight-**start** analogue of *Flight-end outcome*, and the differentiator metric set
(docs/plan.md §1). Flight segmentation says a flight began; this says what it cost to get
there, and — the part no summary built from flights alone can ever contain — how often he
pumped and *did not* get up. Feeds FIT session fields 35–38 and lap fields 12–13.

| param | default | units | notes |
|---|---|---|---|
| `takeoffMaxRun` | 30 | s | cap on the pre-flight window searched back from `ON_FOIL` |
| `takeoffRiseSlack` | 0.3 | m/s | walking back, a sample still belongs to the speed rise while it is no more than this above the slowest sample seen so far (monotone enough to be a takeoff, loose enough for a real water start) |
| `takeoffRestSpeed` | 1.0 | m/s | walking back, the first sample at or below this *is* the run start — he was sitting on the board. Without it a slack-tolerant walk-back swallows the whole rest, because a flat trace is "non-increasing" too (= `turnStopSpeedFloor`) |
| `takeoffAttemptWindow` | 10 | s | an attempt stays open this long past its last stroke: `ON_FOIL` inside the window ⇒ that attempt succeeded and its burst is the flight's takeoff run; silence past it ⇒ the attempt failed. Also the silence that separates two attempts |
| `takeoffMinPreWindow` | 3 | s | less gap-free record than this before a flight start ⇒ the run is not in the data (`truncated`) |
| `freeTakeoff` | < 3 strokes | | got up on wind alone — a fact about the conditions, not about his pumping, so the two are separated in every average |

Bursts, cadence and `pumpMinStrokes` come from *Pumping (accelerometer)* unchanged; turn
ownership uses the same window as *Flight-end outcome* (`start` → `end + outcomeWindow`).

**The takeoff run** is the contiguous pre-flight window of rising speed *plus* the pump burst
that led into it, whichever started earlier — so `pumps_to_takeoff` counts the strokes of the
effort that actually produced the flight, and `duration_s ≥ speed_rise_s` always. The rise is
read on the Doppler channel, the one that defined the flight boundary, so run and flight agree
on where the takeoff ended. The walk-back also stops at a recording gap and at the previous
flight's end: a run cannot reach back through the flight before it.

`takeoffAttemptWindow` deliberately **replaces the watch's 5 s `attemptSuccessWindow`** rather
than mirroring it. On 2026-08-07 the qualifying burst ends 0.1–2.5 s before `ON_FOIL` for 20 of
23 takeoffs, but 6.2 s, 8.0 s and 8.7 s before it for three, where the board kept accelerating
after he stopped pumping; at 5 s those three lose their run (and one reads as a *free* takeoff
that was nothing of the sort). 10 s costs nothing and matches the watch's `attemptFailSilence`,
so one number plays both roles and there is no dead zone in which an attempt is neither.

**Every pumping burst is classified exactly once** — the ownership discipline of the flight
ends, for the same reason. Bursts less than `takeoffAttemptWindow` apart are first chained into
one **episode** (one continuous effort: four bursts inside a minute of thrashing are one failed
attempt, not four), then:

| outcome | test | counted as |
|---|---|---|
| `in_flight` | the episode lies wholly inside a flight | `in_flight_strokes` — pumping to hold or extend a glide, never a takeoff. Amplitude-gated since 0.8.1 ("In-flight strokes"), so a gentle episode is still classified and still placed, and contributes 0 strokes |
| `success` | a flight starts between the first stroke and `takeoffAttemptWindow` after the last | nothing extra: it *is* that flight's takeoff run, already counted as a flight |
| `recovery` | the episode lies inside a detected turn's outcome window | the turn's `touchdown`, already scored there |
| `failed` | none of the above | a failed takeoff attempt |
| `unknown` | the record does not run gap-free for `takeoffAttemptWindow` past the last stroke | nothing — excluded from every tally |

Since **0.3.0** the episodes themselves are serialized, as the golden's top-level
`pumpEpisodes` list (docs/testing.md) — every outcome, in detection order, with the instants
and the cross-reference indices — so a failed attempt can be *placed* (on the map, in the speed
chart) instead of only counted; the classifier is unchanged, only its output now leaves the file.

`takeoff_attempts` = flights + failed attempts, `takeoff_successes` = **flights**: a flight
demonstrably happened, so it succeeded even when its run was truncated; truncation only removes
it from the pumps/duration averages. Sources without an accelerometer report the speed-only run,
`None` stroke counts and — because their failures are invisible — a `None` success rate rather
than a flattering 100 %.

**Corpus (defaults above).** 2026-08-07 ciq: 23 takeoffs, all judged, 14 failed attempts ⇒ 37
attempts at 62 % success; 9.0 pumps to takeoff on average (median 7, range 4–21), 8.7 s average
run (median 8.0), 0 free takeoffs, 395 counted strokes (1341 raw peaks before engine 0.8.0) of
which 127 in flight across 36 in-flight episodes. The native sessions have no accel and lose
the run of every flight they have, since
engine 0.23.0: 2026-08-05 am 12 of 12 (11.8 s average), 2026-08-04 pm 40 of 40 (13.1 s). Before
it, when a Smart Recording cadence was read as a hole, those were 9 of 52 and 23 of 130 (6.8 s
and 7.6 s) — the same truncation that cost 111 of that session's 130 flight *ends*. The runs
are longer because a run may now walk back through a cadence step instead of stopping at it. **Unvalidated:** the failed-attempt count has no ground
truth yet (fixtures/README.md logs takeoff attempts per session — 2026-08-07 is still blank),
and it is the one number here that moves with `takeoffAttemptWindow`: 15 failures at 8 s, 14 at
10 s, 10 at 12 s, 9 at 15 s (56 %/62 %/70 %/72 % success). Everything else is flat from 10 s up.

