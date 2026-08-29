# Can the wrist accelerometer see a touch-and-go inside a jibe?

Research note, 2026-08-30. Fixtures: `2026-08-29-1440_nago-torbole-windsurfen_ciq.fit`
(primary) and `2026-08-07-0754_nago-torbole-windsurfen_ciq.fit` (cross-check).
Every number below is reproduced by `lab/tools/touch_and_go_probe.py`; the section names in
brackets are its `--section` arguments. Nothing in the engine, the goldens, or the apps was
touched.

---

## The answer

**No — not the signature that was hypothesised.** There is no usable board-*impact* signature
at the wrist. Once you control for how hard the rider's arms are working, water contact is
invisible: chance-level, and on the pump-normalised features slightly *below* chance.

**But one accelerometer feature does work**, and it is not the one anyone was looking for.
Seconds spent above 2 g in a 16 s window around the turn — `rec_hi_g` — separates the
engine's touchdown class from everything else at AUC 0.957, better than speed alone (0.861),
with 88% precision at its operating point. It is not detecting the board hitting the water.
It is detecting the 9–17 s of heaving that getting back onto the foil costs this rider. It
confirms the labels the engine already assigns; it does not find new members.

And **it clears all six suspects.** Their `rec_hi_g` values are 0.11–0.54 s against a
touchdown range of 0.29–2.44 s; five of the six sit in the bottom quarter of all 51 counted
turns. The one accelerometer feature with real discriminating power says the prime suspects
did no recovery — so they did not touch down.

Separately, the framing in the task needs one correction. **The engine already has a
touch-and-go rule.** `turns._outcome` calls a turn `touchdown` even when the flight never
breaks, provided the rider pumped inside the outcome window *and* the speed went "marginal".
The tally is not limited by a missing sensor; it is set by where one speed threshold sits.

**The tally I would defend for 2026-08-29: 35 flew / 8 touchdown / 8 fell, unchanged.**
The reasoning, and the one narrow circumstance under which I would move it to 33/10/8, is in
[What I would defend](#what-i-would-defend).

---

## 1. The evidence already in hand, verified

All of it checks out.

| Claim | Verified |
|---|---|
| 51 counted turns, 35 flew / 8 touchdown / 8 fell | yes (62 turns detected, 11 rejected) |
| 6 of the 35 flew-scored turns have `pumped=true` | yes — ts 2284, 2679, 3469, 4027, 4341, 4616 |
| the five slowest flew turns bottom out at 6.6–7.3 kn | yes — 6.65, 7.04, 7.25, 7.28, 7.34 |
| touchdown-turn median `minKn` 5.7 kn | yes — 5.75 |

Two facts worth adding, because they shape everything downstream:

- **All 8 touchdown turns have `pumped=true`. Zero of the 8 `fell_in` turns do.** The pump
  flag is not a weak hint; on this session it is nearly definitional for touchdown.
- **`submerged` is false on all 35 flew turns.** The barometer never says the wrist went
  under during one.

So the suspect set is exactly six turns. That ceiling matters: the maximum correction the
rider's memory could possibly justify on this session is six turns, 35/8/8 → 29/14/8.

### The physical anchor `[--section anchor]`

| | 2026-08-29 | 2026-08-07 |
|---|---|---|
| successful takeoffs | 31 | 23 |
| takeoff entry speed, median | 6.93 kn | 7.00 kn |
| pump strokes to takeoff, median | 10 | 7 |
| takeoffs needing **no** pumping | **0 / 31** | **0 / 23** |

This rider has never once got back onto the foil without pumping, and it costs him a median
of 10 strokes. A jibe that touched the water and flew out with zero pump strokes is not a
thing he does. That is why the 29 non-pumped flew turns can be set aside on engine-internal
grounds alone, before any accelerometer is consulted.

---

## 2. What the stream actually is

`accelerometer_data` on the fenix 8, via SensorLogger: 702,800 samples over 7,028 s,
continuous at 100.0 Hz with no gap longer than 0.28 s, ±8 g full scale per axis, resting
|a| median 1.055 g. Parsed through `wingfoil_lab.parse._accel_batch` (which sniffs the
milli-g scale) and resampled onto a true 100 Hz grid. No gyroscope in the file.

The probe filters |a| into a pump band (0.5–2.5 Hz, straight from `Config`) and an impact
band (8–45 Hz — above wing handling, below Nyquist), takes zero-lag RMS envelopes, and
normalises everything by the rider's own session median so thresholds read as "× this
rider's usual".

---

## 3. The decisive experiment: the matched liftoff pair `[--section liftoff]`

The cleanest ground truth in the file is not the turns — it is the 31 successful takeoffs.
Five seconds before liftoff the board is in the water; five seconds after, it is flying.
Same rider, same wing, seconds apart, and the only thing that changed is water contact. If
the wrist can see water contact anywhere, it has to show here.

Averaged Welch spectra, 31 matched pairs (4.8 kn off-foil → 9.0 kn on-foil):

| band (Hz) | off-foil | on-foil | ratio | **shape ratio** |
|---|---|---|---|---|
| 0.5–2.5 | 1.47e-01 | 2.61e-02 | 5.64 | **1.15** |
| 2.5–5 | 2.99e-02 | 6.29e-03 | 4.75 | 0.97 |
| 5–8 | 2.99e-02 | 6.09e-03 | 4.91 | 1.00 |
| 8–12 | 8.80e-03 | 2.19e-03 | 4.01 | 0.82 |
| 12–16 | 3.42e-03 | 1.04e-03 | 3.28 | 0.67 |
| 16–20 | 1.32e-03 | 3.38e-04 | 3.89 | 0.79 |
| 20–25 | 3.71e-04 | 1.18e-04 | 3.15 | 0.64 |
| 25–30 | 1.27e-04 | 5.33e-05 | 2.37 | 0.48 |
| 30–35 | 4.67e-05 | 3.01e-05 | 1.55 | 0.32 |
| 35–45 | 2.82e-05 | 1.89e-05 | 1.49 | **0.30** |

The raw ratio column looks encouraging — the board in the water gives 1.5–5.6× more energy
everywhere. But it is *everywhere*, which is the tell: this is a broadband amplitude
difference, i.e. the rider is pumping hard before liftoff and coasting after.

The "shape ratio" column divides out overall amplitude. A board slapping water would push it
**above 1 at high frequency**. It does the exact opposite: 1.15 in the pump band, falling
monotonically to 0.30 at 35–45 Hz. Relative to its own total energy, the board-in-the-water
state is **less** high-frequency than flight, not more. The 08-07 fixture reproduces this
(1.53 → 0.44).

The impact hypothesis fails its cleanest test. The arms hold the wing, the wing holds the
rider, and that elastic chain filters the board's contact with the water out of the wrist.

---

## 4. Isolating the confound: pumping on foil vs off foil `[--section pump]`

The task flagged pumping as the confound. Here it is isolated: pump episodes that happened
*on* foil against pump episodes that happened *off* foil. Both are the same 0.5–2.5 Hz wrist
rhythm; only the board's water contact differs. AUC is P(off-foil scores higher); 0.5 is
chance.

| feature | on-foil median | off-foil median | AUC (08-29) | AUC (08-07) |
|---|---|---|---|---|
| pump-band amplitude | 0.2465 | 0.2925 | 0.682 | 0.636 |
| HF-band amplitude | 0.0790 | 0.0925 | 0.572 | 0.613 |
| **HF ÷ pump band** | 0.3373 | 0.3192 | **0.389** | **0.435** |
| HF crest factor | 2.5447 | 3.1906 | 0.610 | 0.581 |
| peak \|a\| | 2.6011 | 4.3803 | 0.724 | 0.723 |
| seconds > 2 g per s | 0.0294 | 0.1059 | 0.733 | 0.676 |

Raw amplitude features (peak |a|, time over 2 g) reach AUC ~0.72. Every one of them is also
a pump-vigour feature — off-foil pumping is simply more violent, because the rider is heaving
a displacing board rather than topping up a flying foil. The moment the HF band is normalised
by the concurrent pump band, the separation **inverts to below chance** (0.389, 0.435) on
both sessions.

That is the whole finding in one row. There is no residual water-contact information in the
accelerometer once arm effort is accounted for. And arm effort is something the engine
already measures — that is what the `pumped` flag is.

---

## 5. The per-turn battery `[--section turns]`

Eight features scored around each turn's re-derived speed minimum — seven in a ±5 s impact
window, plus `rec_hi_g` in a deliberately wider ±8 s recovery window (see below for how that
one arrived). AUC against the engine's own labels, 2026-08-29:

| feature | AUC td > flew | AUC td > suspect | AUC td > impossible-control |
|---|---|---|---|
| `pk_hf` (impact spike) | 0.761 | 0.896 | 0.671 |
| `sus_hf` (sustained roughness) | 0.775 | 0.833 | 0.763 |
| `hf_over_pump` | 0.632 | 0.812 | **0.500** |
| `pk_g` | 0.714 | 0.792 | 0.625 |
| `s_over_2g` (±5 s) | 0.811 | 0.833 | 0.789 |
| `drop_spike` (free-fall off the foil) | 0.657 | 0.667 | 0.592 |
| `pk_pump` (arm effort) | 0.746 | 0.771 | 0.724 |
| **`rec_hi_g` (recovery, ±8 s)** | **0.957** | **0.979** | **0.954** |
| `-minKn` — speed alone, already in the engine | 0.861 | 0.833 | 0.934 |
| `pumped` — already in the engine | 0.857 | — | — |

Every feature designed to catch an *impact* lands between 0.63 and 0.81 — below speed alone
(0.861), and `hf_over_pump` sits at exactly 0.500 against controls, which is the cleanest
possible statement of "no information".

`rec_hi_g` is the exception, at 0.957. It is worth being precise about what it is and how it
was found, because it was **not** the hypothesis and it emerged from a window sweep, which is
exactly the setting where a spurious result appears.

### The window sweep that found it `[--section window]`

| window | `pk_hf` AUC td>flew | td>suspect | td>ctrl | best precision |
|---|---|---|---|---|
| ±3 s | 0.718 | 0.812 | 0.638 | 38% |
| ±5 s | 0.761 | 0.896 | 0.671 | 50% |
| **±8 s** | 0.861 | **1.000** | 0.750 | 62% |
| −2/+8 s | 0.714 | 0.896 | 0.586 | 31% |
| 0/+6 s | 0.825 | 0.958 | 0.730 | 50% |
| −5/+10 s | 0.836 | 0.979 | 0.711 | 62% |

The impact score improves monotonically as the window widens. **That is itself the
refutation of the impact hypothesis.** An impact lasts milliseconds; a genuine impact feature
would peak at the *narrowest* window and decay as the window admitted more unrelated
seconds. This does the exact opposite, which means the information is not at the moment of
contact — it is in the seconds afterwards. So the honest move is to stop pretending it is an
impact feature and measure the recovery on purpose. That is `rec_hi_g`.

---

## 6. The feature that works, and the one that does not `[--section controls]`

The right control is not clean flight — it is turns that **physically cannot have touched
down**: `flew_through`, minKn ≥ 8.3 kn, and no pump afterwards (which, per §1, rules out any
recovery). There are 19 of them on 2026-08-29. Precision below is against **all 35 flew
turns**, the honest denominator.

### `pk_hf`, the impact feature — no operating point

| threshold | touchdowns | suspects | impossible controls | all flew | precision |
|---|---|---|---|---|---|
| 4 | 8/8 | 5/6 | 17/19 | 30/35 | 21% |
| 6 | 8/8 | 3/6 | 15/19 | 25/35 | 24% |
| 8 | 6/8 | 1/6 | 12/19 | 17/35 | 26% |
| 10 | 5/8 | 0/6 | 9/19 | 9/35 | 36% |
| 16 | 4/8 | 0/6 | 4/19 | 4/35 | 50% |
| 24 | 2/8 | 0/6 | 1/19 | 1/35 | 67% |

**Precision never exceeds 36% at any threshold catching most touchdowns.** The single highest
impact score of the entire session — `pk_hf` = 25.9, above every real touchdown — belongs to
ts 1076, a turn that carried 8.48 kn through the bottom and needed no pump at all. ts 5065
(9.42 kn, no pump) scores 23.1. A jibe means sheeting the wing hard, and that is what the
wrist measures. A large broadband transient is evidence the rider handled the wing, not that
the board touched water.

### `rec_hi_g`, the recovery feature — a real operating point

| threshold (s above 2 g) | touchdowns | suspects | impossible controls | all flew | precision |
|---|---|---|---|---|---|
| 0.3 | 7/8 | 1/6 | 6/19 | 9/35 | 44% |
| 0.5 | 7/8 | 1/6 | 4/19 | 7/35 | 50% |
| **0.8** | **7/8** | **0/6** | **1/19** | **1/35** | **88%** |
| 1.0 | 6/8 | 0/6 | 1/19 | 1/35 | 86% |
| 1.5 | 4/8 | 0/6 | 0/19 | 0/35 | 100% |

Raw values, 2026-08-29:

- touchdown: 0.29, 0.83, 1.32, 1.41, 1.55, 1.66, 1.85, **2.44**
- **the six suspects: 0.11, 0.12, 0.12, 0.14, 0.18, 0.54**
- all 35 flew: max 1.15, second-highest 0.75, median 0.18

Seven of the top eight turns in the whole session by `rec_hi_g` are the seven heaviest
touchdowns. The eighth (ts 1076, 1.15) is a `flew_through` that never pumped — one false
alarm in 35. The missed touchdown is ts 581 at 0.29, the gentlest of the eight (minKn 8.97).

This is a genuine result, and it is genuinely not an impact detector. It measures sustained
violent arm work over 16 s, which for a touchdown is the recovery: 9–19 pump strokes across
5–17 s of heaving the board back onto the foil. It corroborates the class the speed rule
already found. It cannot *discover* a touchdown the speed rule missed, because a touch-and-go
mild enough to evade the speed rule is by construction one the rider flew out of without a
heavy recovery — which is precisely what the suspects look like.

Cross-check on 2026-08-07: `rec_hi_g` AUC 0.889, touchdowns 0.09–3.99, flew max 0.70. At the
0.8 s threshold, 4/9 touchdowns and 0/9 flew turns — same direction, weaker separation, no
false alarms.

---

## 7. The barometer, for completeness `[--section baro]`

The obvious other channel. It works, and it is useless per event:

| | 2026-08-29 | 2026-08-07 |
|---|---|---|
| liftoff altitude step, median | **+0.60 m** | +0.40 m |
| pairs with a positive step | 22/31 | 14/23 |
| in-flight noise floor (same 5 s vs 5 s comparison), sd | 1.90 m | 1.81 m |
| effect / noise | 0.32 | 0.22 |
| events needed for a 2σ read | ~40 | ~82 |

The barometer genuinely sees the foil's ride height — +0.60 m is the right number for this
rider's setup, and the sign is right in 22 of 31 cases. It is buried under 1.9 m of 5 s-scale
noise. Real, and undetectable one event at a time. (The engine's existing use of the
barometer — `submerged`, a 25 m drop meaning the wrist went underwater — is a completely
different, much larger effect, and it works fine.)

---

## 8. The rule that is already there `[--section gate]`

This is the part that changes the conversation.

The premise in the task — "the engine can only see a touchdown when the flight detector drops
out (speed < exit threshold held ~3 s)" — is not what `turns.py` does. `flying_mask` in
`evidence.py` says so in its own docstring: flight segmentation alone is too coarse, so it
adds an *instantaneous* speed test on min(Doppler, positional). And `_outcome` has a second
touchdown path entirely:

```python
lost = np.flatnonzero(win & ~ev.flying)
if lost.size == 0:
    marginal = bool((ev.speed[win] < cfg.foil_entry_speed_kmh * KMH_TO_MPS).any())
    turn.outcome = TOUCHDOWN if (turn.pumped and marginal) else FLEW_THROUGH
    return
```

So a turn where the flight never broke at all is *still* called `touchdown` when the rider
pumped inside the outcome window and the speed dipped below `foilEntrySpeed`. That is a
touch-and-go rule, and it has been shipping.

Note the units: `foilEntrySpeed` is 12 **km/h** = **6.48 kn**, and `foilExitSpeed` is 8 km/h
= **4.32 kn**. These are much lower than the knot values they resemble.

Minimum of the gate channel — min(Doppler, positional) — over each turn's outcome window:

| outcome | n | min | median | max |
|---|---|---|---|---|
| flew_through | 35 | **6.58** | 8.39 | 9.49 |
| touchdown | 8 | 0.00 | 4.68 | **5.48** |
| fell_in | 8 | 0.00 | 0.49 | 3.39 |

**The classes do not overlap, with a 1.11 kn gap.** Every turn the engine called `touchdown`
lost real speed — down to 5.48 kn at best, 0.00 kn at worst. Every turn it called
`flew_through` held at least 6.58 kn. There is no ambiguity to resolve here, and no boundary
case for an accelerometer to adjudicate.

How far each suspect sits from the gate:

| suspect ts | minKn (maneuver) | gate channel | short of the gate by |
|---|---|---|---|
| 4341 | 7.25 | 6.75 | **0.27 kn** |
| 2679 | 8.29 | 6.93 | **0.45 kn** |
| 2284 | 7.95 | 7.73 | 1.25 kn |
| 4027 | 7.93 | 7.93 | 1.45 kn |
| 3469 | 8.25 | 8.25 | 1.77 kn |
| 4616 | 8.50 | 8.50 | 2.03 kn |

Two of the six are close enough to the gate (0.27 and 0.45 kn) that wrist-Doppler noise could
plausibly be the difference. The other four are 1.25–2.03 kn clear of it, which on a
3–4 s-smoothed Doppler channel is not noise.

---

## 9. The rule I would propose `[--section sweep]`

**Not a new accelerometer rule.** The proposal is: leave the signal set alone and treat
`foilEntrySpeed` — the `marginal` gate — as the tuning knob, because it is the only thing
that moves this tally.

Swept on both fixtures, with everything else at defaults:

| `foilEntrySpeed` | = kn | 08-29 flew/touch/fell | turns that moved | 08-07 flew/touch/fell |
|---|---|---|---|---|
| **12.0 (today)** | 6.48 | **35 / 8 / 8** | — | **9 / 9 / 12** |
| 12.5 | 6.75 | 34 / 9 / 8 | 4341 | 9 / 9 / 12 |
| 13.0 | 7.02 | **33 / 10 / 8** | + 2679 | 9 / 9 / 12 |
| 14.0 | 7.56 | 33 / 10 / 8 | (no change) | 9 / 9 / 12 |
| 15.0 | 8.10 | 31 / 12 / 8 | + 2284, 4027 | 7 / 11 / 12 |
| 16.0 | 8.64 | 28 / 14 / 9 | + 3469, 4616, **5457 → fell_in** | 7 / 11 / 12 |

The over-reach signal is explicit at 16 km/h: ts 5457 flips to `fell_in`, and it never
pumped. Past ~15 km/h the knob is inventing touchdowns rather than finding them. Note also
that 08-07 is completely insensitive until 15 km/h — a knob change tuned on one session's
memory would silently rewrite a second session that has no suspects at all.

**Signal:** min(Doppler, positional) speed, already computed in `evidence.py`.
**Features:** the existing `marginal` test and the existing `pumped` flag. No new inputs.
**Threshold:** `foilEntrySpeed`, today 12 km/h. The defensible band is 12.0–13.0 km/h.
**What changes on 2026-08-29:** 35/8/8 → 33/10/8 at 13.0 km/h. Nothing else in the session
moves — no fall becomes a touchdown, no flight boundary shifts.

### The one place the accelerometer earns a role

If the gate is ever widened, `rec_hi_g` is worth adding as a **veto, not a trigger**: promote
a turn to `touchdown` only when the widened gate fires *and* the recovery feature clears
~0.8 s above 2 g. Used that way it has 88% precision and costs one false alarm in 35.

Note what that composition produces here. The widened gate at 13.0 km/h nominates ts 4341
(`rec_hi_g` 0.12) and ts 2679 (0.54). **Both are vetoed.** Gate-plus-veto leaves 2026-08-29
at 35/8/8 — the two signals disagree, and the conservative composition keeps today's answer.
That is the strongest argument in this report for leaving the tally alone: the only
accelerometer feature with demonstrated discriminating power actively contradicts the only
knob that would move it.

### Rider-facing semantics

If anything ships here, it should be **a new flag, not a reclassification**. `touchdown`
currently means "the foil stopped carrying you and you had to get it back" — a real,
felt event, and the eight turns wearing that label on 2026-08-29 all lost 3–9 kn. Folding a
turn that held 6.9 kn and needed four pump strokes into the same bucket devalues the label
for the events that earned it.

I would add `touch_and_go` as a fourth outcome, or a boolean modifier on `flew_through`:

> **flew through (33)** · **touched and went (2)** · **touchdown (8)** · **fell in (8)**

and let the summary roll `flew_through + touch_and_go` into the "stayed up" total, so the
success percentage does not move. That keeps the rider's memory and the engine's evidence in
the same view instead of forcing one to overwrite the other. It also means the ambiguous
cases live in their own bucket where a wrong call is cheap.

### What the watch could and could not do live

- **The impact feature is not computable on the watch at all.** `SessionController._startAccel`
  registers the sensor at `PumpDetector.GRID_HZ` = 25 Hz with `:period => 1`. Nyquist is
  12.5 Hz, so the 8–45 Hz band this report used does not exist live. Recovering it means
  re-registering at 100 Hz — 4× the callback rate and 4× the box-averaging in Monkey C, for a
  feature that measures nothing. Firmly not worth it.
- **The proposed rule needs nothing new.** `marginal` is a comparison against a config
  constant on a speed channel the watch already maintains, and `pumped` comes from
  `PumpDetector`, which is already running. A live `touch_and_go` count is a threshold change
  and a counter.
- **`rec_hi_g` is the one accel feature the watch *could* compute live**, because it needs
  only |a| against a fixed threshold — no bandwidth. But the live stream is box-averaged from
  100 Hz down to 25 Hz, which attenuates exactly the short peaks the feature counts, so the
  0.8 s / 2 g operating point would not carry over unchanged; it would have to be re-derived
  against the 25 Hz replica (`watch_pump_replica.py` already has that plumbing) before anyone
  trusted a live number. Cheap to compute, not free to calibrate.
- **The one thing the watch cannot do live is the outcome window.** `_window_end` searches
  *forward* for recovery, up to `turnOutcomeLookahead` = 12 s past the turn. The watch would
  have to hold the turn unresolved for up to 12 s before displaying it, or display a
  provisional outcome and correct it. The phone stays authoritative, as `docs/plan.md` §3
  already has it.

---

## 10. What I would defend

**35 flew / 8 touchdown / 8 fell for 2026-08-29 — unchanged.**

- **The impact hypothesis is dead.** No impact feature beats the speed channel already in the
  engine; precision never exceeds 36%; the highest-scoring turn of the session is one that
  demonstrably flew clean; and the pump-normalised version scores exactly 0.500 against
  controls.
- **The one accelerometer feature that does work points against the rider's hypothesis.**
  `rec_hi_g` separates touchdowns at AUC 0.957 with 88% precision — and puts all six suspects
  at 0.11–0.54 s against a touchdown floor of 0.29 and a median of 1.48. Five of the six are
  in the bottom quarter of all 51 turns. They pumped, but they did not *recover*: four
  strokes over two seconds is a top-up, not a get-back-on-foil effort.
- **The engine's own gate agrees.** The six suspects sit 0.27–2.03 kn clear of the threshold
  that would reclassify them, and the two classes are separated by a 1.11 kn gap with zero
  overlap.

Three independent lines — the speed gate, the recovery feature, and the pump-burst shape —
say the same thing about the same six turns.

**The one move I would entertain**, and only with the rider adjudicating rather than a
detector: ts 4341 (0.27 kn short) and ts 2679 (0.45 kn short) are close enough to the gate
that wrist-Doppler noise is a real explanation, and both pumped immediately afterwards. If
Jan looks at those two turns on the map and says "yes, I dropped on there" — **33 / 10 / 8**.
That is the largest defensible correction, and it is a factor of three smaller than the six
turns his memory implies.

**Cross-check, 2026-08-07: 9 flew / 9 touchdown / 12 fell, unchanged, and not even a
candidate.** Zero of its nine `flew_through` turns pumped, so the suspect set is empty. Its
gate channel does overlap by 0.31 kn — the `pumped` half of the test is what holds the slow
flew turns in place — which is a second argument for keeping `pumped` as a necessary
condition rather than loosening it.

### Why the rider's memory and the data can both be right

`flew_through` means "no measurable interruption of flight", not "the board never grazed the
water". A wingtip skim, a tail kiss that costs 0.3 kn, a moment where the foil ventilates and
catches again — all of those are *felt*, all of them are remembered as "I touched down on
that one", and none of them are visible in a 1 Hz speed trace or, as this report shows, in a
100 Hz wrist accelerometer. The gap between 35 and the rider's memory is most likely real and
permanently unmeasurable with this hardware, and the honest response is vocabulary (a
`touch_and_go` bucket, and a label that says "no measurable interruption") rather than a
threshold tuned until the number matches the memory.

---

## 11. Limitations, stated plainly

1. **The ground truth is the rule under examination.** The 8 "known touchdowns" are
   speed-detected touchdowns. Training an accel detector on them and finding it works is
   circular; finding it *fails* is not, which is the direction this went.
2. **Those 8 are heavier events than the one being hunted.** They lost 3–9 kn. A brief
   touch-and-go is strictly quieter. The accelerometer cannot separate the loud version, so
   it certainly cannot separate the quiet one — but note this is an argument from the harder
   case to the easier one, not a direct measurement of the quiet case.
3. **n is small.** 8 touchdowns, 6 suspects, 19 controls, one session. Every AUC quoted here
   rests on 8 positives with no cross-validation possible.
4. **One rider, one wing, one spot, two sessions.** Nago-Torbole chop; a flat-water session
   or a different foil could change the wrist's coupling to the board.
5. **`rec_hi_g` was found by a window sweep, and that is a real caveat.** It was not the
   pre-registered hypothesis; it fell out of §5's sweep. Six windows and eight features is
   enough multiplicity to manufacture an AUC of 0.957 by luck on n=8. Three things argue it
   is not luck: it reproduces in direction and sign on the second fixture (AUC 0.889, zero
   false alarms); the threshold at which it works (0.8 s of >2 g in 16 s) has a physical
   reading that matches the measured recovery cost of 9–17 s of heaving; and it is *not* the
   feature that would have flattered the hypothesis. It should still be re-tested on a
   session neither of these before anyone leans on it.
6. **`rec_hi_g` cannot find what it was asked to find.** It corroborates the touchdowns the
   speed rule already labels. A touch-and-go mild enough to escape the speed rule is, by
   construction, one without a heavy recovery — so this feature is structurally blind to
   exactly the event the rider remembers. It is useful as confirmation, never as discovery.
7. **The sweep in §9 is not a clean single-knob experiment.** `foilEntrySpeed` also floors
   the recovery threshold in `_window_end`, so raising it lengthens outcome windows as a side
   effect. That is precisely why ts 5457 flips to `fell_in` at 16 km/h, and it is a further
   argument for a small change or none.

---

## Reproducing

```
cd lab
uv run python tools/touch_and_go_probe.py                      # both fixtures, all sections
uv run python tools/touch_and_go_probe.py --section gate       # §8, the real discriminator
uv run python tools/touch_and_go_probe.py --section sweep      # §9, the knob
uv run python tools/touch_and_go_probe.py --section controls --fixture 2026-08-29-1440_nago-torbole-windsurfen_ciq
```
