# Fall counting — two questions from 4 Sep 2026 (applied in engine 0.25.0, ADR-035 — both A)

Jan's two Strava imports "Afternoon Wingfoil", Fri 4 Sep 2026: 16:08 (12:58 min, Strava
20034356447) and 13:58 (1:42 h, Strava 20034351727). The original CIQ FITs are in the local,
uncommitted `fixtures/footage/_raw-2026-09/`. The Strava import sends GPX with no Doppler, and
Strava **fills GPS holes**: every second is kept, lat/lon interpolated, baro altitude kept. So
the import was emulated from the FIT the same way (every record kept, lat/lon interpolated,
enhanced altitude, HR), then run through lab engine 0.24.0, wingfoil preset. It reproduces the
phone exactly: jibes 4 flew · 1 touch · 0 fell, Fell in 2 — 1 in a turn · 1 in a straight line.

## 1. "Fell in 2 — 1 in a turn", yet no jibe fell

**Finding: yes, the "in a turn" fall is the excluded course change.**

| t | what | channel verdict |
|---|---|---|
| 7:24 | flight 2 ends, watch under water for 28 s (baro −290 m), GPS lost | straight-line `fell_in` (submerged, stop 26 s). A real fall. On the raw FIT it is a 27 s hole, so it reads `unknown` there. Only the Strava fill makes it judgeable |
| 12:16–12:23 | `round_up`, not counted (under `turnClassifyMinAngle`) | turn ladder `fell_in` |
| 12:29 | flight 3 ends inside the round-up's window | `fell_in`, `ownedByTurn` = the round-up |

The phone reads a fall owned by a course change in four different ways:

| place | what it does with it | code |
|---|---|---|
| Fell-in tile, split caption | **"in a turn"**. Ownership is tested against every turn, course changes included, and says so on purpose | `flightend.assign_end_ownership` (+ `FlightEndClassifier.assignOwnership`), `summarize_flight_ends` |
| Turn list, jibe/tack ladder, `OutcomeSplit.turn_falls` | **hidden**. Counted turns only | `TurnAnalytics` `turn.counted` gate, `split_outcomes` |
| Streaks | **straight-line**. Only ends owned by a *counted* turn are skipped | `turns._streak_events` |
| Map / submersion attribution | **nowhere**. Not a hollow straight-line mark (it is owned), and not a turn window (it is uncounted) | `presentation._drawn_flight_ends`, `goldens.session_submersions` |

The docs contradict each other as well. turns.md, "Aborted turns", says a course change's swim
"is charged to the flight-end channel as a straight-line fall". The flightend.py docstring says
the course change owns it.

**Options**

- **A. Only a counted turn owns a flight end.** A fall inside a course change's window is a
  straight-line fall. The tile then reads *2 — 0 in a turn · 2 in a straight line*. The fall
  gets a hollow mark on the map and its submersion is attributed. This agrees with the streaks,
  with `OutcomeSplit` and with turns.md as written. One `if` in `assign_end_ownership`, in both
  lab and kit.
- **B. Show course changes in the turn list when they own a fall** (a "course change · fell
  in" row). This keeps the attribution but puts uncounted rows in the list, beside a ladder that
  still reads 0 fell. That is two numbers for one question again, and it is more UI.
- **C. Count a course change the ladder calls `fell_in` as an attempted turn**, the way
  aborted turns are counted. This moves `turnsCounted`/`jibes` and overrides
  `turnClassifyMinAngle`'s refusal. Too big for the question asked.

**Corpus (18 committed fixtures):** **9** fell-in flight ends are owned by an uncounted course
change (08-29 ciq 5, foilmotion 2, rheinstetten 1, 08-03 am 1). Under A they move from "in a
turn" to "in a straight line". Total falls, `wetPerHour`, JPH/TPH/CPH, clean jibes, the turn
ladders and the streaks do not move. The goldens do move: `ownedByTurn`, `flightEnds.inTurn`
and `straight`, `outcomeSplit.straightFalls`, and the drawn-end count.

**Recommendation: A.** Engine minor bump, lab → kit → web bundle, and the flightend docstring
and algorithms text reconciled.

*Out of scope, flagged:* 12 corpus flight ends are `fell_in` inside a **counted** turn whose
own ladder said `touchdown`/`flew_through` (for example, the raw 13:58 FIT, flight 7). There
the tile says "1 in a turn" while that jibe reads "touch". This is a verdict disagreement
between the two windows, not an ownership one. It needs a separate round.

## 2. "Flight 18 · touchdown · off the foil 61 s"

**Finding.** It is a touchdown because the ladder only asks whether the speed ever reached
`turnStopSpeedFloor`. Here one sample was at 0.99 m/s against a 1.0 floor, and `stopped_s` was
0. The trace after the exit is 1.1–2.5 m/s for over 60 s, and the next flight starts 224 s
later. That is a slog, not a touch. **"61 s" is a ceiling:** the off-foil run is capped at
`outcome_window_s` = 60 s (+1 sample). So it means "not flying again within a minute".

**Options**

- **A. Touchdown needs the floor early:** the first sub-floor sample falls within
  `turnOutcomeLookahead` (12 s) of the exit. A dip later than that, with no stop over
  `turnFallStop`, is `glide_out`. The loss is judged where it happened, the same span the turn
  channel uses.
- **B. Narrower:** `off_foil_s` at the cap and `stopped_s == 0` → `glide_out`.
- **Presentation, either way:** show the capped value as "off the foil 1 min+" and not as
  "61 s".

**Corpus (18 fixtures, straight-line ends, fell-in untouched):**

| rule | touchdown → glide-out | of |
|---|---|---|
| A (first dip > 12 s) | **8** | 25 straight-line touchdowns |
| B (capped, never stopped) | 2 | 25 |

Jan's 13:58 import: A moves 2 of 4, B moves 1, flight 18 in both. Nothing moves the turns,
falls, rates or clean jibes. The streaks move: a straight-line touchdown breaks the flew-through
streak and a glide-out does not.

**Recommendation: A** plus the "1 min+" label. It is one rule ("the touch is the loss, not a
dip a minute later"), it already has a threshold, and it catches the slog without a second cap.
Decide it on 2–3 of the 8 corpus cases viewed on the turn page first.

*Method:* throwaway scripts in the session scratchpad. No engine code, goldens or tests
changed.
