> Part of `docs/algorithms.md`. Engine 0.24.0.

## Wind axis estimation (phone)

1. Foiling samples only, speed ≥ 2 m/s (COG≠heading below that — COAPS caveat).
2. Weighted circular histogram of COG (10° bins, weight = distance) → two dominant modes
   (reaches) → axis = bisector.
3. 180° ambiguity: **no-go zone** — of the two axis ends, the one whose ±45° cone holds
   (almost) no distance is where the wind comes from; margin = relative cone asymmetry
   (`fullMargin` 0.4 ⇒ certain, both cones empty ⇒ unresolved), then the rider's
   **default turn type** where that margin is weak (below) → else Open-Meteo prior →
   else user value.
4. Confidence ∈ [0,1] = axis confidence (lobe mass × lobe balance × mode separation) ×
   the 180° call's certainty; `< 0.5` ⇒ turns labeled `turn`, not tack/jibe, unless user
   set wind manually (manual always wins).

The **speed** asymmetry originally specified for step 3 is not used: across the whole
fixture corpus mean speed rises as the course turns *toward* the wind (a foil loses
apparent wind deep downwind), i.e. the opposite of the displacement-sailing rule it was
taken from. It is kept as a diagnostic only. The no-go-zone rule matches Garda's diurnal
pattern (morning Peler from N, afternoon Ora from S) on every corpus session.
**An opposed pair of reaches still has a wind** (engine ≥ 0.23.0, ADR-030). Until then a
separation above `windMaxLobeSeparation` = 179° was refused as a degenerate bisector, and a
tester's afternoon of two exactly opposed reaches — lobes 132.74° / 311.90°, separation
**179.16°** — came back with no axis at all, so not one of its 78 maneuvers could be named a
tack or a jibe. The bisector is undefined *at* 180° and nowhere else, and even there the
answer is not missing: the wind axis is the **perpendicular** of the lobe axis, and the no-go
cone picks its end exactly as it does for every other separation. The construction is now the
half-angle form `lobe0 + wrap180(lobe1 − lobe0) / 2`, which is defined for every separation,
agrees with the old equal-weight circular mean everywhere that mean was defined (so no corpus
session moves by a digit), and returns the perpendicular at exactly 180°. **The parameter is
retired** — it no longer appears in a golden's `config` block. The doubt rides in
`confidence`, where it can be read, rather than in a hard `null`: that tester session comes
back at **222.3°, confidence 0.70**, cone margin 0.31, against 222° from the watch's own live
estimate and 225° from a weather archive, and its turns split 45 tacks / 33 jibes against the
watch's 44 / 32.

**The watch took the same change in 0.9.18** (`AutoWind._bisect`), so there is no divergence
row for it any more: the half-angle form, the refusal retired, and the perpendicular at
exactly 180°. It is cheaper on the wrist as well as more complete — two adds and a divide
against the four transcendental calls the circular mean needed, on a function every
evaluation runs. `WingFoilCore.autoWindOpposedLobesStillResolve` holds it, in two passes: with
nothing but the one reach the axis is computed and the DIRECTION stays unresolved (both no-go
cones are empty, and the doubt shows up as a confidence of 0), and with a little downwind
running in the mix the same lobes resolve to the perpendicular.

### Default turn type — the rider's habit as 180° evidence

Flipping the wind 180° swaps every jibe and tack, so a rider's declared habit is evidence
about orientation. A wingfoiler jibes far more than he tacks; if one end of the axis makes
this session's sweeps come out mostly jibes and the other makes them mostly tacks, the
first end is the one the rider actually sailed in.

`windDefaultTurnType` — `jibes` (**default**) · `tacks` · `balanced` (prior off). It is
a *prior*, not a measurement, and three rules keep it in its place:

* **Axis never.** It touches the 180° call only. The bisector, the lobes and
  `axisConfidence` are computed before it and are not consulted about it.
* **Weak calls only.** With `eCone = clip01(ambiguityMargin / fullMargin)` — the very
  factor confidence has always been scaled by — a decisive cone (`eCone ≥ 1`, i.e.
  `ambiguityMargin ≥ fullMargin` 0.4) is untouchable: the prior is not even evaluated, and
  the numbers are bit-identical to the pre-prior engine.
* **Only real maneuvers vote.** Every sweep `detect_turns` would report is classified under
  *both* axis ends, and a sweep votes only if it is a tack-or-jibe under both. A bear-away
  is not evidence about the wind, and a sweep that is a maneuver under one end only would
  let the prior pick its own electorate.

The blend, with `nDefault`/`nOther` the votes for and against the declared type **under the
cone's own pick** and `w` = `windTurnPriorWeight` (0.5):

```
eCone    = clip01(ambiguityMargin / fullMargin)          ∈ [0, 1]
mTurn    = (nDefault − nOther) / (nDefault + nOther)     ∈ [−1, 1], signed toward the cone
e        = eCone + w · mTurn
direction = cone's pick            if e ≥ 0
            cone's pick + 180°     if e < 0            (`priorFlipped`)
certainty = clip01(|e|)                                  → confidence = axisConfidence × certainty
```

So the prior can overturn the cone only below half of `fullMargin`, and only with a
decisive majority: a 90/10 jibe split (`|mTurn|` 0.8) flips a cone margin under 0.16; an
even split (`mTurn` 0) flips nothing and changes nothing. `balanced`, no votes, and an
exact tie are all bit-identical to the cone acting alone. The wind object records what
happened — `turnTypeMargin` (`|mTurn|`), `turnTypeDirDeg` (the end the habit favours, null
when the prior did not run or had no votes), `turnTypeVotes`, `priorFlipped`.

On the current fixture corpus the prior never fires: every session's cone margin is ≥ 0.52,
well past `fullMargin`. It exists for the sessions the cone cannot separate — short ones,
and ones sailed as two broad reaches with no upwind work to empty a cone.

### Watch approximation: auto wind — `garmin/barrel/WingFoilCore/source/AutoWind.mc`

Device app **0.9.0**. Until it, the watch had one source for a wind axis: the bearing the
rider entered by hand. Without one every sweep is a generic `turn` — no tack/jibe split, no
port/starboard split, and `tack_count`/`jibe_count` omitted from the FIT — and it is the one
thing that cannot be fixed after the session. `AutoWind` estimates the axis live, from the
same evidence the phone uses, so the watch is self-sufficient mid-session.

**It runs the same chain as the engine above**, at 1 Hz, in O(1) per tick with every array
allocated at construction:

| step | engine (`wind.py`) | watch |
|---|---|---|
| samples | foiling, ≥ 2 m/s, weighted by per-step distance | identical: `FlightDetector` ON, Doppler ≥ 2 m/s, weight = `speed × dt` |
| histogram | 36 × 10°, smoothed ±20° | identical, accumulated incrementally |
| lobes | argmax of the smoothed histogram, then the weighted circular mean of the raw samples within ±25° | argmax, then the mass-weighted circular mean of the **bin centres** within ±2 bins |
| axis | bisector of the two lobes (half-angle form, defined at every separation); rejected below 60° only | identical since watch 0.9.18: `AutoWind._bisect` is `a + wrap180(b − a) / 2`, the perpendicular at exactly 180°, and the 179° refusal is gone with the circular mean that needed it |
| axis confidence | `clip01((mass−0.2)/0.4) × clip01(balance/0.5) × clip01((sep−60)/20)` | identical |
| 180° call | ±45° no-go cones, `margin = \|mA−mB\|/(mA+mB)`, `eCone = clip01(margin/0.4)` | identical, over bin centres |
| default-turn-type prior | `e = eCone + 0.5·mTurn` over every detected sweep | identical, over the last 64 logged sweeps |
| adopt | `confidence = axisConf × certainty ≥ 0.5` | identical, **plus** a confirmation and a hysteresis (below) |

Cadence: evaluate every **60 s**, once **500 m of flying distance** has accumulated — the
engine's own `min_distance_m`, kept rather than re-tuned so the watch and the phone refuse on
the same evidence. At a wingfoil's 8 m/s that is a bit over a minute in the air, typically two
or three reaches: the least that can show two lobes at all.

**The three deliberate divergences**, all forced by the platform:

1. **Bins, not samples.** Lobe refinement and cone mass are computed over bin centres, so both
   carry up to ±5° of quantization. Measured cost on the corpus: under 2°.
2. **Incremental and one-way.** A sample joins the histogram and never leaves; the estimate is
   the whole session so far. There is no sliding window, so a genuine wind shift is not
   forgotten but averaged — it shows up as the estimate walking, bounded by (3).
3. **Confirmation + hysteresis.** The first direction is adopted only when **two consecutive**
   qualifying evaluations agree within 20° — the engine can answer once from complete
   evidence, the watch's first answer costs a vibe, the one-shot backfill and every turn label
   from then on. After that the adopted value moves only on a re-evaluation **≥ 15°** away.
   The estimate keeps converging underneath (on 2026-08-07 it walks 23° → 35° over the hour)
   and the readout does not follow, because a bearing that creeps by two degrees a minute is
   unreadable.

**Precedence and display.** Manual wind always wins: `Config.windDirection` is derived as
`windManual >= 0 ? windManual : windAuto`, so an estimate fills the axis only while the rider
has set none, and setting one takes over instantly (clearing it hands the axis back). Every
place a bearing is shown marks an estimate with a leading `~` — `~SSW` on the turns-page
header and the session menu, `wind ~200° SSW` on the start screen — because an estimate the
rider cannot tell from a measurement is worse than no estimate. One vibe (`AlertManager`
channel `CH_WIND`, two rising ticks) when it first locks.

**The one-shot backfill.** Turns are normally classified with the wind in effect at the time
and never re-judged. Auto wind is the single exception, and only at its first lock:
`TurnDetector.backfillWindSplit` replays the logged sweeps once, so the session's tack / jibe /
port / starboard counts do not start from zero at minute two of an hour's riding — the sweeps
the axis was learned *from* are exactly the session's own first turns. It is narrow on
purpose: it **adds splits and nothing else**. `turnCount`, the outcome tallies, the scores and
the streaks are untouched, and a logged sweep that turns out to be a bear-away under the new
axis stays the generic turn it was counted as (retracting it would move `turnCount`, the
success percentage and every streak that spanned it). After it,
`tackCount + jibeCount ≤ turnCount`, the difference being those course changes.

**Settings.** `autoWind` (default **on**) and `windDefaultTurnType` (`jibes` default · `tacks`
· `balanced`), the latter mirroring the engine's setting of the same name and vocabulary.

**Acceptance: ±20° against the engine, on real sessions.** `garmin/tests/AutoWindFixtures.mc`
(generated by `lab/tools/make_autowind_arrays.py`) carries the recorded 1 Hz cog/speed/
foil-state stream of both `ciq` fixtures; `autoWindReplayFixtures` drives `AutoWind` through
them and asserts it locks, lands within 20° of the phone engine's `wind.dirDeg` for that
session, and never flips after locking.

| fixture | engine `dirDeg` | watch, at save | error | locks at | later updates |
|---|---|---|---|---|---|
| 2026-08-07 | 35.58° | 28.03° | −7.6° | 658 m | 0 |
| 2026-08-29 | 199.88° | 195.91° | −4.0° | 2 320 m | 0 |

The band is 15° of hysteresis (the adopted value may lag the converged estimate by that much
*by construction*) plus a few degrees of bin quantization. It is also under one 16-point
compass step (22.5°), i.e. inside it the watch and the phone never disagree about what to
print. On this corpus the prior never fires — every cone margin is decisive, exactly as it is
for the engine.

