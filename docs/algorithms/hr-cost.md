> Part of `docs/algorithms.md`. Engine 0.24.0.

## HR cost (phone) — what an attempt costs in heartbeats

Jan's question: *"my HR goes up when I pump."* `lab/src/wingfoil_lab/hrcost.py` answers four
versions of it — per-takeoff cost, pumping vs cruising, fatigue over the session, and recovery
— from the FIT `heart_rate` channel joined to the takeoff runs, the flight ends and the turns.

**Frozen (phase 3.5).** Ported to `ios/WingFoilKit/…/AnalysisEngine/HrCost.swift` and carried
by the golden schema as the `hr` block (docs/testing.md), so every number below is now a
cross-implementation parity obligation like the rest. Adding the block moved no pre-existing
golden number, so `ENGINE_VERSION` stayed at 0.2.0 — but it now covers these numbers too, and
the next change to a definition here bumps it. `tools/hr_report.py` reproduces this section.

| param | default | units | notes |
|---|---|---|---|
| `hrCostPeakWindow` | 30 | s | peak searched this far past the anchor. Not the burst length: optical HR trails effort by 10–20 s (measured median peak lag 20.5 s on 2026-08-07), so a window as short as the effort measures the HR he *arrived* with |
| `hrBaselineWindow` | 10 | s | baseline = **median** (not mean — one spike must not move it) of the usable samples in the window ending at the anchor |
| `hrMinCoverage` | 0.6 | | a window below this share of usable seconds yields `None`, never a number |
| `hrMaxSampleGap` | 10 | s | longer between two samples ⇒ an HR hole. A separate rule from the cleaner's, read off the raw records rather than the cleaned track: HR is a slow channel two samples 6 s apart bracket perfectly well, while a gap in the speed rule protects distance integration. Smart Recording writes 1–9 s cadences (2026-08-05: 985 intervals, 5 of them ≥10 s; 2026-08-04 pm: 3745, 13 of them) so 10 s sits in a real valley of the distribution. Under the speed rule **as it was before engine 0.23.0** (~4 s on such a track) the natives lost 93–94 % of their takeoff costs to "gaps" that were nothing of the sort — 3/52 and 9/130 measurable, against 52/52 and 129/130 here. Since 0.23.0 the cleaner's own Smart Recording floor is **this same valley**, so the two numbers agree on a native track; they stay two rules, because a 1 Hz track still cuts speed at 3 s and HR at 10 |
| `hrFlatlineMax` | 60 | s | identical bpm for longer, inside one gap-free stretch ⇒ stuck sensor, whole run dropped. Corpus longest identical runs: 21 s (ciq), 17 s / 27 s (natives), so at 60 s the guard removes **nothing** today — it is there for a future dropout, where an optical sensor holds one value for minutes, and it must not fire on a genuinely steady resting heart |
| `hrMinBpm` / `hrMaxBpm` | 30 / 220 | bpm | outside this is sensor garbage, not a heart rate |
| `hrLag` | 10 | s | pumping/cruising **classification** windows are shifted forward by this, and cruising additionally excludes a ±`hrLag` guard band around every burst. Without it the metric mostly compares the HR he brought into each burst |
| `hrRecoveryWindow` | 120 | s | cap on the half-decay search; running past it is `censored`, a fact about the window |
| `hrMinRise` | 5 | bpm | below this there was no rise to recover from — no recovery is measured, and the attempt is not in the recovery denominator |
| `hrBinMinutes` | 20 | min | fatigue-curve bin width (equal thirds also available for short sessions) |

**Validity, and why nothing is ever fabricated.** A wrist sensor under a wetsuit sleeve, in
cold water, on an arm being thrown around, drops out and sticks. Three per-sample guards —
plausible, not stale, not across a hole — collapse into one number per window: **coverage**,
the share of the window's seconds carried by intervals whose *both* end samples survive all
three (the same both-ends-qualify convention flight segmentation and the stop measure use).
Below `hrMinCoverage` the metric is `None`. Every aggregate is printed as `n valid / n total`,
so a summary can never quietly average three takeoffs and call it a session. A hole *inside* a
covered window can only hide a **higher** peak than the one observed, so a cost read across
one is biased low, never high.

**The anchor is the start of the effort**, i.e. the takeoff *run* start (`takeoff.py`) — the
first stroke of the burst that produced the flight, or the start of the speed rise when that
came earlier. Anchoring on `ON_FOIL` instead would measure a different thing entirely: its
baseline is read *during* the pumping (already elevated) and its window runs 30 s into the
flight, so on 2026-08-07 it reports a *larger* number, 7.9 bpm against 6.9, made of the rise
that the attempt had already produced plus whatever the first half-minute of flying added.
The run anchor is the one for which "what this attempt cost" is the thing being measured. Two
degraded anchors are flagged
`approximate`: no strokes in the run (no accelerometer, or a genuinely free takeoff), and a
truncated run, which anchors on the flight start itself and so measures the HR delta across
the off-foil → on-foil transition alone. That fallback is what gives native sessions a figure.

| metric | definition |
|---|---|
| takeoff HR cost | peak − baseline around the anchor. **Negative values are reported**, not clamped: "he was still recovering when he started" is a different fact from "this cost nothing" |
| pumping vs cruising | time-weighted mean HR over the `hrLag`-shifted burst spans (all of them — takeoff, failed, recovery, in-flight: one physical act) against the same over on-foil time outside the guard bands |
| bpm per stroke | **pooled** Σcost ⁄ Σstrokes over the takeoffs that have both. The median of the per-takeoff ratios is reported beside it, because dividing a 3 bpm cost by 4 strokes one takeoff at a time turns sensor noise into a wide spread |
| fatigue curve | per bin: attempts (flights started in the bin + failed episodes whose first stroke is in it), success rate, avg/median cost, **avg baseline**, mean HR, avg pumps, and the cost coverage |
| recovery | seconds from the peak until HR first falls halfway back to the baseline. The search stops at a hole — HR 120 before an eleven-minute gap and 88 after it did not decay in that window, and calling it a fast recovery would be the most flattering possible lie |

**Corpus (defaults above).** 2026-08-07 ciq: cost 6.9 bpm avg / 7.0 median over **23/23**
takeoffs, all burst-anchored; pumping 101.6 vs cruising 96.0 bpm (**+5.6**, coverage 1.00 on
both sides); 0.76 bpm per stroke; half-recovery 12 s (14/15) after takeoffs, 18 s (4/7) after
swims. The two native sessions have no strokes and every anchor `approximate`, and every
takeoff they have is measurable: 2026-08-05 am 13.5 bpm avg (**12/12**), 2026-08-04 pm
10.4 bpm (**40/40**). They read *higher* than the ciq session rather than the same, and since
engine 0.23.0 that is the honest reading: those sessions used to be cut into 52 and 130
"flights" by a Smart Recording cadence, so most of what was averaged was a phantom restart
mid-reach at no cost at all. Twelve and forty real water starts after a real swim cost more
heartbeats than a class-(a) afternoon of mostly-made jibes, which is what the number now says.
Usable HR: 76 % / 98 % / 86 % of the session span (the ciq loss is three genuine breaks
totalling 22 min).

**Fatigue: half the hypothesis held, and the other half is a warning about the metric.**
2026-08-07 in thirds — 67 % / 69 % / **44 %** success (12 / 16 / 9 attempts), with four of the
last third's five failed attempts in the 1:17–1:23 cluster. The *success* collapse is real and
the 20-minute bins bracket it the same way: 64 / 75 / 69 / 50 / **33 %**. The **cost** does the
opposite
of the prediction: 7.3 / 9.3 / **−0.5** bpm by thirds. It is not that the late attempts were
cheap, it is that there was no headroom left to rise into — mean attempt baseline 92 → 100 → 99
bpm across the thirds (89 → 103 across the 20-minute bins), and the session's last three
takeoffs read −1 / +1 / −9 bpm off baselines of 113 / 103 / 103 against a session maximum of
126. A rise measured against a drifting baseline is not a fatigue metric on its own; that is
why `avg_baseline_bpm` sits beside `avg_cost_bpm` in every bin, and why the honest late-session
statement is *"attempts starting 8–14 bpm higher, success rate down 25 points, rise exhausted"*.
Normalising the cost against the range still available to the session maximum is the obvious
next tuning step, and needs a session where he actually reached his max.

