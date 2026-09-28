# Tack count — Jan's library against his memory (28 Sep 2026)

Jan, 28 Sep 2026: *"Validate tack count in my own corpus. Number seems too high; I think it
should be 3 in total. All failed."*

**Finding: the engine counts 18 tacks where Jan remembers 3.** Fourteen of the 18 come from one
rule: the aborted-turn pass (engine 0.21.0) names a sweep that ended in a fall *by the axis it
was closing on*. A jibing rider who heads up and falls gets a tack under that rule. Four smaller
rules close the gap to **5 candidates in the wingfoil sessions**, and the three strongest of
those are very likely Jan's three. Proposal below; nothing in the engine has changed yet.

## Method

Lab engine 0.26.0, wingfoil preset, default config, over every watersport activity in Jan's
intervals.icu library (61 activities, 2025-08-10 … 2026-09-19, downloaded to a scratch folder,
not the repo). The committed corpus and the September raw CIQ files are a subset of it and give
the same numbers. 23 files are desk/test recordings with no wind axis (Pfinztal, Remchingen,
the 31 Aug morning stubs); two of them crash `pump_track` (side finding below). **38 sessions
have an axis, and every one resolves at confidence ≥ 0.96 with cone margin ≥ 0.30.** So the
tack count does not come from the 180° call or the rider-default prior. The prior never fires,
and the tacks are not a flipped wind.

Two of the 38 are windsurf sessions recorded before Jan's first wingfoil session
(2025-08-10 Torbole, 2026-04-04). They are listed below but are not part of the wingfoil answer.

## Per session

Only sessions with a tack are listed. The other 29 sessions with an axis have 0 tacks.

| session | jibes | tacks | course changes |
|---|---|---|---|
| 2025-08-10 07:29 (windsurf) | 37 | 1 | 5 |
| 2026-04-04 14:50 (windsurf) | 3 | 1 | 1 |
| 2026-06-05 12:24 | 71 | 1 | 14 |
| 2026-08-02 07:48 | 38 | 1 | 2 |
| 2026-08-03 07:41 | 52 | 2 | 3 |
| 2026-08-05 13:56 (FoilMotion) | 69 | 1 | 44 |
| 2026-08-07 07:54 | 31 | 1 | 4 |
| 2026-08-29 14:40 | 56 | 1 | 19 |
| 2026-08-30 14:20 | 64 | 2 | 8 |
| 2026-09-01 08:04 | 77 | 1 | 4 |
| 2026-09-01 16:11 | 57 | 2 | 8 |
| 2026-09-03 08:05 | 79 | 1 | 5 |
| 2026-09-03 14:53 | 58 | 3 | 5 |
| **all 38 sessions with an axis** | **1561** | **18** | — |

Jan's memory, *all failed*, holds: 17 of 18 are `fell_in`. The one `touchdown` is a windsurf
session.

## Each tack

Times are local, approximate (session start + session clock). The TWA pair is the engine's
`twaInDeg → twaOutDeg`: 0 is head to wind, ±180 is dead downwind. "Ab" = aborted-turn pass.

| # | when | net | TWA in → out | how found | what the trace shows | verdict |
|---|---|---|---|---|---|---|
| 1 | 08-30 ≈14:22 | +76° | −81 → −5 | ab | steady beam reach at 11–12 kn, heads up 20° at speed, through head to wind at 6.5 kn, on round to +77/+163 as it stops | **real tack attempt** |
| 2 | 09-03 ≈15:29 | +57° | −81 → −24 | ab | beam reach at 12 kn, heads up 30° at 11 kn, through the wind at 3 kn to +46/+53, stops | **real tack attempt** |
| 3 | 09-03 ≈15:21 | +57° | −84 → −27 | ab | beam reach at 12 kn, heads up 20° at 10 kn, reaches −27 at 4 kn, falls back to −92 and stops | **likely a tack attempt that did not get through** |
| 4 | 09-01 ≈17:09 | −54° | +65 → +11 | ab | bears away to +117, then heads up 110° to +7 while holding 6.5–8.5 kn, barometer under | possible, odd (holds 6.5 kn at 10° off the wind) |
| 5 | 09-03 ≈09:47 | +60° | −80 → −20 | ab | beam reach at 11 kn, speed collapses to 4.5 kn in 2 s while heading 40° up | probably a crash that rounded up |
| 6 | 08-03 ≈09:43 | −92° | +109 → +17 | ab | broad reach, speed halves *before* the heading moves, then swings back downwind | crash rounding up |
| 7 | 08-07 ≈08:32 | +88° | −127 → −39 | ab | one-sample bear-away blip, then luffs 60° while collapsing to 1.6 kn | crash rounding up |
| 8 | 09-01 ≈08:34 | +60° | −128 → −69 | ab | broad reach → beam reach as the wrist goes under | fall, never near the wind |
| 9 | 08-03 ≈09:19 | −51° | +139 → +88 | ab | broad reach → beam, 10 s recording gap | fall, never near the wind |
| 10 | 06-05 ≈15:15 | +52° | −138 → −86 | ab | one-sample blip back onto the reach, then stop | fall, never near the wind |
| 11 | 09-03 ≈15:35 | −100° | +140 → +41 | ab | **tail of the jibe at 15:34** (same rotation, starts inside that jibe's 30 s outcome window, the jibe is already `fell_in`) | jibe tail, **one fall booked twice** |
| 12 | 08-05 ≈15:22 | +52° | −127 → −75 | ab | **tail of the jibe 8 s earlier** (same rotation, inside its 26 s window, the jibe is already `fell_in`) | jibe tail, **one fall booked twice** |
| 13 | 08-30 ≈15:25 | −89° | +128 → +39 | ab | jibe ends 2 s earlier, same rotation carries on up to close-hauled, falls | jibe exit, not a tack |
| 14 | 09-01 ≈16:26 | +52° | −94 → −42 | ab | jibe ends 2 s earlier, same rotation carries on, falls | jibe exit, not a tack |
| 15 | 08-29 ≈16:08 | +293° | +142 → +75 | crossing | one sweep: a jibe through downwind, then on through the wind as he crashes. It is named by the crossing nearest the sweep's middle, which is the tack | **misnamed jibe** |
| 16 | 08-02 ≈08:48 | +178° | −163 → +15 | crossing | a jibe split in two: bear-away sweep to 3579 s, the downwind crossing falls in the 2 s gap, this sweep starts 17° past downwind and rounds up to the wind as he stops | **misnamed jibe** |
| 17 | 2025-08-10 ≈09:03 | −138° | +80 → −58 | crossing | through the wind at 7.8 kn, touchdown | windsurf tack |
| 18 | 2026-04-04 ≈14:51 | +100° | −81 → +19 | crossing | through the wind at 5 kn, fell | windsurf tack |

**Real tacks in the wingfoil library: 3 strong (#1, #2, #3), 2 doubtful (#4, #5).** That matches
Jan's "3, all failed" if his three are 30 Aug afternoon and two on 3 Sep afternoon. **Ask Jan**
to confirm those three times. If they are right, #4 and #5 are the ones to refuse.

## Which rules over-count

1. **Aborted-turn naming (turns.md, "Naming it").** *"Where it did not [cross], the turn takes the
   axis its own rotation was closing on."* Any fall while heading up becomes a tack, whether he
   was 5° or 88° from the wind (#1–#14). 14 of 18.
2. **The aborted pass does not look behind.** `_merge_aborted` drops a candidate that overlaps a
   counted turn's *sweep*, but not one that starts inside the previous turn's *outcome window*
   or right after it in the same rotation (#11–#14). In #11 and #12 the jibe already owns the
   fall, so the swim is booked twice: once as the jibe's outcome and once as a tack.
3. **Nearest-middle crossing on a two-axis sweep (#15).** A 293° sweep crosses downwind and then
   upwind. The engine names it by the crossing nearest the middle, which picked the tack.
4. **A jibe split at a sampling gap (#16).** On a 2 s Smart Recording file the downwind crossing
   falls between two same-direction sweeps, and the second one is classified by itself.

## Proposal

Five rules. The first three are what matter; R4 and R5 each touch one turn in the library.

- **R1 — an aborted turn belongs to the turn before it.** An aborted candidate that turns in the
  same direction as the previous counted turn and starts before
  `prev.end + max(prev.outcomeWindow, 3 s)` is part of that turn, and is dropped. Where the
  previous turn already fell in, that removes the double booking. Where it flew through, the
  fall goes back to the straight-line channel, as it did before 0.21.0.
- **R2 — an aborted tack must reach the no-go zone.** An aborted sweep that did not cross is
  named a tack only if its last foiling heading is within **`turnAbortAxisDeg` = 30°** of head
  to wind. Otherwise the candidate is dropped: the course change stays on the map and the fall
  is a straight-line fall. A wingfoiler cannot ride 30° off the wind, so a heading that gets
  there is past the point of a luff. Aborted **jibes are left alone**: on the same library,
  a 30° gate would drop 15 of the 69, and 45° would drop 7. Those falls are what the
  0.21.0 pass was built to count, and nothing here says they are wrong. Applying the gate to
  one side only follows the rider's `windDefaultTurnType`: the habit he declared decides which
  word needs the stronger evidence. With `balanced`, the gate applies to both sides; with
  `tacks`, it applies to aborted jibes.
- **R3 — the luff must start at speed.** An aborted tack also needs ≥ 20° of heading gained
  toward the wind while speed is still ≥ 80 % of entry speed. A deliberate tack starts with a
  luff on the foil. When speed collapses before the heading moves, it is a crash that rounded
  up (#6).
- **R4 — a sweep that crosses both axes is named by its first crossing** (#15). Four counted
  sweeps in the library cross both axes, and this changes only #15.
- **R5 — join same-direction sweeps ≤ 2 s apart before naming them** (#16). The library has 5
  such pairs, and only #16 changes.

**Effect on the library** (prototype as a filter over 0.26.0 output, scratch script):

| | 0.26.0 | R1–R5 |
|---|---|---|
| tacks, all 38 sessions | 18 | **7** |
| tacks, wingfoil sessions | 16 | **5** (#1–#5) |
| jibes | 1561 | 1563 (+#15, +#16) |
| aborted jibes | 69 | 69 |
| turn `fell_in` | — | −9 (R1 ×4, R2 ×4, R3 ×1). #11 and #12 were double bookings. The other 7 falls move to the straight-line channel |
| clean jibes, JPH, CPH | — | unchanged (only fell-in turns move) |

At `turnAbortAxisDeg` = 20°, #3 (−27°) is also refused. That gives 3 wingfoil tacks, but #1, #4
and #5, which is the wrong three by the trace. So the gate stays at 30°, and the step from 5 to
Jan's 3 is his answer to the ask above, not a tighter number.

## Risks and checks before this is built

- The 0.21.0 motivating case, a tester's 19 Sep session with two attempted tacks, is not in the
  corpus. R2 would refuse its kept tack if that tack stopped more than 30° short of the wind.
  The doc only says "short of head-to-wind". Run that file before merging.
- R1 hands 2 falls back to the straight-line channel (#13, #14), so the falls tile's
  "in a turn / in a straight line" split moves on those sessions.
- The watch's `TurnDetector` has no aborted-turn pass (turns.md, "No aborted turn" under "Not ported yet"), so none of
  this is a new divergence. R4 and R5 would need a watch port or a divergence row.
- Engine bump (0.27.0), lab → kit → web bundle, goldens regenerated. Six committed goldens hold
  a tack today (08-02, 08-03 ×2, 08-05 FoilMotion, 08-07, 08-29), and **all six go to 0**.

## Side finding

`pump_track` raises `IndexError` (boolean mask length ≠ array length) on two short CIQ stubs,
2026-08-31 06:52 and 07:22. Those files cannot be analysed at all. This is separate from the
tack count and needs its own fix.
