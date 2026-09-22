> Part of `docs/algorithms.md`. Engine 0.23.0.

## Speed records (GP3S set)

2 s peak · 10 s peak · 5×10 s (mean of best 5 **disjoint** 10 s windows) · 100 m · 250 m ·
500 m · nautical mile (1852 m) · 1 h · alpha 500 · session distance.

| param | default | notes |
|---|---|---|
| `alphaProximity` | 50 m | endpoint-to-startpoint (Pythagoras on local meters) |
| `alphaMaxDistance` | 500 m | total path length |
| `alphaCandidatePrune` | ≥250 m path AND ≥90° COG spread | gps-wizard optimization |
| `alphaBoundary` | interpolate | fractional samples at window edges (phone only) |
| `hourSearch` | forward + backward | avoids the classic missing-samples bug |
| `minSpeedFilter` | none | GPSResults-style 5 kn floors distort results — never applied |
| `uncertifiedShortWindowMax` | **1.2** | K, the plausibility gate (engine ≥ 0.20.0): on an **uncertified** source a window shorter than 10 s is accepted only up to this multiple of the best 10 s. See below. Certified Doppler records never see it |
| watch live set | **2 s and 10 s only** (shipped) | rolling means over the last 2 and 10 *samples*, reset on any GPS gap — `garmin/…/SpeedRecords.mc`. 5×10 s, 500 m, NM and alpha-lite are **planned, not shipped** (`SpeedRecords.mc`, "phase 3"; FIT ids 28–31 reserved and unwritten). The divergence check compares six records against a watch that can supply two — harmlessly, since it skips zero-valued pairs |

### The plausibility gate — the uncertified short window (engine ≥ 0.20.0)

Jan, 19 September 2026: *"uncertified speed record: maybe only accept if it seems reasonable
vs the 10 s record."*

A best 2 s differentiated from positions rides on **two fixes**, and one of them being wrong is
the whole record. A best 10 s rides on ten and averages the bad one away. That difference is
measurable: over the corpus, every session read twice — once as its FIT, once as the positions
alone (`lab/tools/strava_vs_icu.py`'s arm, GPX at Strava's six decimals) — the ratio
`best2s / best10s` sits in the same narrow band on both channels, except where a fix is wrong.

| best2s / best10s | n | median | p90 | p95 | max |
|---|---|---|---|---|---|
| **certified** (class a/b) | 16 | 1.044 | 1.087 | **1.114** | **1.159** |
| positional (class c) | 17 | 1.046 | 1.119 | 1.403 | **2.539** |

The positional column is the certified column plus one outlier: its second-highest reading is
1.120 and its highest is 2026-08-29's **2.539** — the 31.77 kn against a certified 13.21 that
"Positions-only recordings" below measures. `best2s / best5x10s` says the same thing one
notch louder (certified p95 1.144, max 1.189; positional max 2.576) and adds nothing to the
decision, so the gate is written against the 10 s.

**The rule.** On a source whose `capabilities.hasDoppler` is **false**, a record whose window
is shorter than **10 s** is accepted only if it is at most `uncertifiedShortWindowMax` × the
best 10 s. The search then returns **the fastest window that passes** rather than nothing: a
rider who went fast still gets a number, and the number is one the same afternoon's 10 s can
account for. In the GP3S set the only window shorter than 10 s is the best 2 s.

**K = 1.2**, from the certified p95 (1.114) × 1.1, rounded to one decimal. It clears the
certified **maximum** (1.159) by 3.5 %, so no real 2 s peak the corpus has ever seen would be
refused if the same session arrived without its speed channel — and it is less than half the
distance to the outlier, which reads 2.5.

**What it moves.** One session, and it is the one Jan is describing:

| session | arm | best 2 s before | after | the certified answer |
|---|---|---|---|---|
| 2026-08-29 pm (ciq) | positional | 31.77 kn | **13.13 kn** | 13.21 kn |

The fallback lands **0.6 %** below the Doppler record the same afternoon measured. Every
other session on both arms is unchanged, both committed class (c) goldens sit at 1.05 and
move no number, and nothing certified is touched at all — the gate is not reachable from a
file that measured its own speed.

**The distance records are left alone, and the data is why.** The gate is keyed on the
window's *length*, and on the whole corpus the shortest distance window is the best 100 m at
**13.5 s** (250 m: 38 s, 500 m: 79 s, NM: 314 s, alpha 500: 43 s) — every one of them already
longer than the 10 s reference, every one of them averaging a bad fix away. Their certified
and positional readings agree accordingly: `best100m / best10s` runs 0.960–0.997 certified
against 0.919–0.993 positional, and the other four are the same story. There is no second
problem to fix, so there is no second rule. Should a rider ever cover 100 m in under 10 s the
gate applies to that window too, by the same sentence.

**What it is not.** It is not a spike filter and it does not clean the track: the fallback
window may still clip the bad sample's edge (the unit tests assert exactly that). It bounds
the *claim*. And it does not change what the rider is told — the record still wears the
`uncertified` mark it has worn since engine 0.9.0, because the source is still a source that
could not prove it measured anything.

