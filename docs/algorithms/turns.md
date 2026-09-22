> Part of `docs/algorithms.md`. Engine 0.23.0.

## Turn detection & classification

| param | default | units | notes |
|---|---|---|---|
| `turnMinAngle` | 60 | deg | net unwrapped COG change — the **detection** floor. A course change is a real thing that happened and the page marks it, so this stays where it is |
| `turnAbortMinAngle` | **45** | deg | the **aborted-turn** floor (engine ≥ 0.21.0), and the only entry condition this pass lowers. A sweep that was still turning when the sailing run ended — the rider went in — is offered to the same scoring and the same outcome ladder with this much net COG change instead of `turnMinAngle`, and is kept only where the ladder says `fell_in`. 45° is **half the classification floor**: he has to have ridden at least half the sweep that would let the engine name a maneuver at all. Below it the corpus stops describing maneuvers — at 30° four more appear, all of them wobbles that ended 66–133° from any axis, which is the mislabel `turnClassifyMinAngle` exists to refuse. 0 switches the pass off. See "The aborted turn" below |
| `turnClassifyMinAngle` | **90** | deg | the **classification** floor (engine ≥ 0.13.0). Below it a sweep is never named a tack or a jibe — **wind axis or not** — and is filed as the same uncounted bear-away/round-up the no-crossing branch already produces. A tack and a jibe both take the board through the wind and out the other side; a 70° sweep that happens to clip dead downwind is a rider bearing away, and calling it a jibe put a course change into the number he judges his session by. With no usable axis the two course-change labels are indistinguishable, so such a sweep takes the bear-away label — the verdict that matters, *not counted*, is the same either way. At or above the floor the rule is unchanged: tack/jibe by the crossings, or a counted `turn` (unclassified) with no usable axis |
| `turnAxisBeforeDeg` | **0** | deg | the **first axis requirement** (engine ≥ 0.15.0), and off at its default. A sweep whose `axisBeforeDeg` — the angle between the TWA it started on and the axis it crosses — is below this is not a tack or a jibe: it is filed as the same uncounted `bear_away`/`round_up` the classification floor produces, and its three axis fields go null with the label. It asks the question `turnClassifyMinAngle` cannot: a 100° sweep that begins 10° off dead downwind and ends 90° past it has crossed the axis without ever having been *upwind of it*, which is a rider straightening out of a reach, not a jibe. At 0 nothing is refused |
| `turnAxisAfterDeg` | **0** | deg | the **second axis requirement** (engine ≥ 0.15.0), and off at its default. A tack or a jibe whose `axisAfterDeg` — the furthest the heading carried past the axis, in the turn's own sense, by the end of the outcome window — is below this cannot be **carried**: `success` is false, and therefore so is `clean`. Jan's wording: *"it might be an additional requirement for a successful jibe to turn 30 deg after the axis. But not require that for a touch-down or failed jibe."* So it touches the score verdict and nothing else — the turn stays a counted jibe, its outcome ladder is untouched, and the JPH/TPH numerators do not move. At 0 nothing is refused |
| `turnCleanQuietS` | **10** | s | the **quiet tail** (engine ≥ 0.17.0), and the third requirement of a clean jibe. Over `[turnEnd, turnEnd + this]`, measured on the same off-foil evidence the outcome ladder reads and stopping at a recording gap, there must be no `touchdown`/`fell_in` flight end, no off-foil spell of 1 s or longer, and no submerged sample. Jan's rule: *"no touch down or fall within 10 s afterwards. This only applies to clean jibe, not to carried through."* So it moves `clean` — and therefore `jibesSuccessful` and `cleanJibesPerHour` — and nothing else: not `success`, not the outcome, not a count, not a streak, not JPH or TPH. At 0 it asks nothing. The 1 s off-foil floor is a code constant (`CLEAN_QUIET_OFF_FOIL_S`), not a parameter: it is the resolution of the question, not a threshold to tune |
| `turnMaxDuration` | 8 | s | window for the net change. Deliberately **not** widened to 12 s, and measured twice: a 12 s sweep pulls a slow exit into the scored minimum, and on the 17 fixtures that costs **26 clean jibes to buy 6 jibes** (18°/s at 8 s gives 538 jibes / 160 clean; at 12 s, 544 / 134). A carve longer than 8 s is therefore reported as the 8 s share of itself — a 10 s, 150° jibe counts as a 135° one, which is over `turnClassifyMinAngle` with room to spare and lands the verdict the rider reads. Counting it a little short beats scoring it a little more generously |
| `turnPeakRate` | **18** | deg/s | at ≥1 sample (engine ≥ 0.14.0; was 25). Richterich's ~30–40°/s for ~4 s is a *pivoted* jibe; a **carved** one is a different maneuver. At 11 kn on a 25 m radius the board turns at a steady ~13°/s and never spikes at all, so a floor set at the pivot's peak rejected exactly the jibes the rider was riding best — on one flight of the 4 Sep afternoon, three of eight ridden reversals were invisible. 18°/s is the floor below which nothing new appears but grey course-change markers |
| `turnContext` | ON_FOIL or ≤3 s after | | turns while swimming don't count |
| `turnCogSpeedFloor` | 2.0 | m/s | COG geometry read only from steps above this (same COAPS caveat as wind); a capsize below it otherwise reads as a multi-turn spin |
| `turnMinArc` | 12 | m | **spatial gate**: path length travelled across the COG sweep |
| `turnMinRadius` | 6 | m | **spatial gate**: effective radius = arc ÷ swept angle in radians |
| `turnContinueRate` | 5 | deg/s | edge trim: shrink the detected span to the actually-turning part |
| `entrySpeedWindow` | 3 | s | entry speed = max over window before turn start |
| `minSpeedLag` | 2 | s | minimum searched to `turnEnd + lag` (the collapse of a botched turn lands just past the COG sweep) |
| `turnSuccessPct` | 70 | % | success ⇒ minSpeed/entrySpeed ≥ this AND speed never ≤ `foilExitSpeed`. Both halves are read over the **scored window only** — `turnStart` … `turnEnd + minSpeedLag` — never over the outcome window: a turn carried cleanly through the sweep stays successful even when the foil is lost later in the recovery tail (that is what the outcome says). Since engine 0.12.0 that turn is nevertheless **not clean** — the clean verdict conjoins this flag with the outcome (glossary below) |
| `turnStopSpeedFloor` | 1.0 | m/s | "stopped": below this the rider is not making way |
| `turnTouchdownMaxStop` | 3 | s | longest stop still called a touchdown |
| `turnFallStop` | 5 | s | stop longer than this ⇒ fell in |
| `turnOutcomeLookahead` | 12 | s | **cap** on the tail past the COG sweep the outcome is judged over. A stalling foil bleeds from foiling speed to a standstill in roughly 10 s, so a shorter cap (the 5 s this started at) systematically misses the mush-out and scores it a fly-through |
| `turnRecoverPct` | 70 | % | of entry speed: back above this ⇒ flying again ⇒ the turn is over and its window closes early. Floored at `foilEntrySpeed` — nothing below that is flying, however slowly the turn was entered |
| `turnRecoverHold` | 2 | s | recovery must hold this long, same both-ends-qualify convention as flight `entryHold` |
| `turnPumpedOutIsTouchdown` | **on** | switch | the **pump rung's gate** (engine ≥ 0.18.0). With it set, a turn that never left the foil is still a `touchdown` when the accelerometer heard a burst in the window *and* a sample fell below `turnPumpedMarginalSpeed` (step 3 above). Off, the rung is refused whatever that speed says. The two are separate on purpose: this is whether the question is asked, the speed below is what it asks. This is the one parameter the tuning page draws as a **switch** rather than a slider (docs/presentation/channels-tuning.md, "Tuning") |
| `turnPumpedMarginalSpeed` | **8.0** | km/h | the **speed the pump rung corroborates against** (engine ≥ 0.18.0), and the change that retired it. It was hard-wired to `foilEntrySpeed` (12) until 0.17.0 — the speed a flight *starts* at rather than the speed the foil stops carrying at — and it cost Jan's Jibe 50 of 4 Sep its fly-through. The default is the same number `foilExitSpeed` carries, and since `flying` already requires speed above the exit speed the rung is thereby **unreachable at the published defaults**: the band it judges is `(foilExitSpeed, this]`, which is empty at 8.0. Deliberately its own parameter and not a reference to `foilExitSpeed`, so the retirement is a *setting* — raise it and the rule comes back over the band it opens, and at **12.0** it is the 0.17.0 reading exactly. Corpus at the default: 13 of 270 jibe touchdowns become fly-throughs. Moving it moves nothing else — flight segmentation reads `foilExitSpeed` and never this |
| `turnBaroDrop` | 25 | m | apparent altitude below the **local baseline** that means the wrist is under water. The value and the meaning of the number are unchanged since it was introduced; what moved in engine 0.22.0 is the line it is measured from — a causal baseline that walks with the altimeter and holds under a spike, rather than the session's median ("Turn outcome" step 2, ADR-029). Its three shape numbers — `BARO_TAU_S` 50 s, `BARO_SETTLE_S` 20 s, `BARO_SETTLE_M` 5 m — are **code constants and not tunables**: they describe the altimeter's slew and its re-anchoring, which is a property of the watch rather than a judgement about riding |
| `turnOutcomeWindow` | **12** | s | cap on following the recovery (engine ≥ 0.13.0; was 60 s). Equal to `turnOutcomeLookahead` on purpose: a fall the ladder blames on a turn is then always inside the tail that turn is actually *judged* over, and a fall later than that is a straight-line fall the flight-end channel counts. At 60 s a mush-out three quarters of a minute past the exit was charged to the turn |
| classification | | | tack = COG crosses wind axis through upwind; jibe = through downwind; requires wind axis; bear-away/round-up (no axis crossing) excluded from counts |
| port/starboard | | | side before the turn, from sign of TWA |
| `detectThreeSixty` | **false** | | **EXPERIMENTAL, UNVALIDATED.** Runs the 360 pass below. Off: with it down nothing detects a spin and the serialized document is byte-identical to one written before the detector existed — no `threeSixties`, no parameter echo |
| `threeSixtyMinDeg` | 300 | deg | net rotation that makes a sweep a full turn. Not 360: the COG at the entry and the exit of a spin is the *board's* heading, and a rider who exits a rotation 40° off the line he entered on has still been all the way round. Below ~300° the shape stops being distinguishable from a wide round-up into a bear-away |
| `threeSixtyMaxS` | 10 | s | window the rotation must fit in. A spin is a single continuous carve; at the 30–40°/s a jibe already reaches (Richterich), 360° takes 9–12 s, and the cap is what stops two maneuvers a minute apart from summing into one. Deliberately wider than `turnMaxDuration` (8 s), which is sized for a 180 |
| `threeSixtyReversalDeg` | 25 | deg | largest back-swing off the running extreme still called monotone. This is the parameter that refuses a tack-then-jibe pair: two same-direction sweeps that add to 360 are only a spin if nothing between them turns back, and 25° is the steering wobble a carve carries without changing its mind |
| `threeSixtyMinKmh` | 5 | km/h | Doppler floor **inside** the sweep — the gate that exists because a stopped rider's COG spins freely: with no way on, the bearing between fixes is decided by a metre of GPS noise and a rider sitting on his board produces a perfect monotone 360 out of nothing. Well below foiling speed on purpose: a spin ridden on the foil and dropped halfway is still a spin |
| 360 entry | `foilEntrySpeed` | km/h | Doppler at the sweep's first sample — "entered on foil". The stricter half of the same guard |

Entry/minimum speeds come from `speedChannelManeuvers` (positional); the "never dropped off
foil" half of the success test stays on Doppler so it agrees with flight segmentation.
Overlapping candidates are non-maximum-suppressed by net angle, widest sweep wins.

The minimum is searched to `minSpeedLag` (2 s) **past** the sweep's end because the speed
trough lags the heading: the rider finishes turning the board and the collapse of a botched
exit lands a second or two later, so a window that stopped at the COG sweep would score the
speed he still had rather than the speed he ended up with.

**What the two 0.13.0 threshold changes did to the corpus.** Measured across 21 sessions
(the fixture corpus plus the sessions not committed to `fixtures/`):

| | 0.12.0 | 0.13.0 |
|---|---|---|
| jibes | 773 | 768 |
| course changes (`rejected`) | 124 | *see note* |
| clean jibes | 263 | 263 |
| jibe outcome `fell_in` | 147 | 50 |
| jibe outcome `touchdown` | 159 | 252 |
| straight-line falls | 78 | 88 |

Five sweeps in a thousand were narrow enough to reclassify: the 90° floor is a guard against
a class of mislabel, not a re-tune. Nothing clean moved, which is the check that matters —
the headline metric is unchanged and the change is confined to what the *outcome* ladder
blames on a turn. (Note: the 124 → 17 course-change figure quoted while the change was being
weighed came from an earlier draft that raised `turnMinAngle` itself to 90°, which stopped
detecting those sweeps at all. That was reverted: detection stays at 60° and the course-change
markers stay on the page, so `rejected` **rises** with the reclassified sweeps instead. On the
17 committed fixtures: jibes 504 → 499, `rejected` 94 → 99, clean 152 → 152, jibe `fell_in`
106 → 32, jibe `touchdown` 128 → 197.)

**What 0.14.0 did to the corpus.** `turnPeakRate` 25 → 18 °/s is the whole change;
`turnMaxDuration` stays at 8 s. Over the 17 committed fixtures, regenerated from the goldens
in this release:

| | 0.13.0 | 0.14.0 |
|---|---|---|
| jibes | 499 | 538 |
| counted turns | 501 | 540 |
| course changes (`rejected`) | 99 | 147 |
| clean jibes | 152 | **160** |
| jibe outcome `flew_through` | 270 | 289 |
| jibe outcome `touchdown` | 197 | 212 |
| jibe outcome `fell_in` | 32 | 37 |
| straight-line falls | 58 | 45 |

Thirty-nine jibes the engine had never counted, forty-eight more course changes marked on the
page beside them, and eight more clean jibes. Straight-line falls drop by thirteen because a
fall that used to have no maneuver to belong to now has one — the same swim, differently
attributed. **Every number a rider reads moves the right way**: JPH and CPH both rise, and no
session in the corpus loses a clean jibe.

**What 0.15.0 did to the corpus: nothing, and that is the point.** Both axis parameters ship
at 0, so every golden is what 0.14.0 said it was — the diff is the version stamp, two config
keys and three per-turn keys. What the crossing bought is the ability to *ask*. Over the 21
sessions (the 15 committed fixtures plus the six September raw recordings), 818 jibes:

| | jibes | clean |
|---|---|---|
| defaults (both 0) | 818 | 278 |
| `turnAxisAfterDeg` = 30° | 818 | **270** |

Fifty-five jibes carry less than 30° past the axis; eleven of those flew through and **eight of
them are clean today**, so a 30° requirement would cost eight clean jibes and no jibes at all —
the count is untouched by construction, because the parameter moves `success` and not the
label. `turnAxisBeforeDeg` = 30° would uncount **seven** jibes (two of them currently clean):
sweeps that crossed the axis having started within 30° of it, which is a rider straightening
out rather than going through the wind. Neither is switched on; the evidence is here so the
decision can be made from numbers rather than from a feeling about one afternoon.

**Why the sweep window stayed at 8 s.** Widening it to 12 s was measured alongside the peak
floor and rejected, which is the second time this parameter has been proposed and declined:

| | jibes | clean | course changes |
|---|---|---|---|
| 25°/s, 8 s (0.13.0) | 499 | 152 | 99 |
| **18°/s, 8 s (0.14.0)** | **538** | **160** | **147** |
| 25°/s, 12 s | 504 | 128 | 99 |
| 18°/s, 12 s | 544 | 134 | 145 |

Going to 12 s on top of the 18°/s floor buys **6 more jibes and costs 26 clean ones** — and
on the 4 Sep session that motivated the change it added no jibe at all. The mechanism is the
one 0.13.0 already named: a longer sweep pulls the slow exit into the minimum
`turnSuccessPct` divides by, so a jibe that scored clean over 8 s of carve scores merely
*carried* over 12 s of carve-and-recovery. A carve that runs past 8 s is instead reported as
its first 8 s — a 10 s, 150° jibe is counted as a 135° one, which is the verdict that matters
and well clear of `turnClassifyMinAngle`.

**The success floor, measured against a rider's own count — open, and Jan's to decide.** The
same tester of 19 September 2026 says about **45 of his 57 jibes felt clean**; the engine gives
him **25**. The gate is unchanged and nothing below is a proposal: `success` is
`score ≥ turnSuccessPct` **and** the Doppler minimum never at or below `foilExitSpeed`, and on
his session the second half is not what is binding — only 2 of 57 touch the foil-exit floor, and
53 of the 57 flew through. What separates 25 from 45 is the score alone. His scores run
56.9–79.9 % with no gap anywhere in the middle, twenty-eight of them between 60 and 70:

| `turnSuccessPct` | his clean jibes | the 18 committed fixtures |
|---|---|---|
| **70** (today) | 25 of 57 | **161** |
| 65 | 39 | 234 (+45 %) |
| 60 | **46** | 266 (+65 %) |

So **60 %** is the number that reaches his count, and it costs what a floor costs: every clean
count in the corpus rises by about two thirds, one fixture from 3 to 16, another from 0 to 3,
and CPH with them. That is not a bug being fixed, it is a different definition of *clean* — the
word means *held at least this much of the speed he came in with*, and 60 % of 14 kn is 8.4 kn,
which is a hair over the speed the foil stops carrying at. A rider's feeling and a speed ratio
are two different measurements of one jibe, and where the two disagree the parameter is the only
honest place to argue. The evidence is here; the number stays at 70 until Jan moves it.

### The aborted turn — a turn that ends in the water (engine ≥ 0.21.0)

Jan, 20 September 2026: **"an attempted turn that ends in the water is a turn that fell in."**
A tester tried two tacks on 19 September, went in both times, and the session reported **no
tack and no fall in a turn**. The reason is the entry condition: the scan asks for
`turnMinAngle` (60°) of net COG change inside `turnMaxDuration`, and a rider who goes in
halfway round never gets there. The COG is read only above `turnCogSpeedFloor`, so the
sailing run *ends at the fall* and the maneuver is missing from the session entirely — or,
where the part he rode clears 60° but not `turnClassifyMinAngle`, it is filed as an uncounted
bear-away and the swim is charged to the flight-end channel as a straight-line fall.

**The rule.** One more sweep per sailing run is offered to the same machinery: the one that
was **still turning when the run ended**, read backwards from that last heading — the widest
net change reaching it inside `turnMaxDuration`. Everything else is the entry condition the
scan already applies, unchanged and for the same reasons: a `turnPeakRate` spike, the
`turnMinArc`/`turnMinRadius` carve gate, and `turnContext` (it began at foiling speed). Only
the angle is lowered, to `turnAbortMinAngle` (**45°**).

Nothing in that scan decides that the rider fell: the candidate is scored by the same builder
and judged by the same three-channel ladder as every other turn, and only the ones it calls
`fell_in` are kept. So an aborted turn is, always:

| | |
|---|---|
| counted | yes — it is a maneuver the rider attempted (`turnsCounted`, and `tacks`/`jibes`) |
| outcome | `fell_in`, with the ladder's own `outcomeReason` (`stop` or `submerged`) |
| `success` | false, and therefore `clean` false. Neither axis gate is asked: a turn that never finished cannot be re-filed as a course change by `turnAxisBeforeDeg`, and `turnAxisAfterDeg` moves a verdict that is already no |
| `aborted` | **true** — the one new per-turn key, so a surface can say *he fell in the turn* rather than *he turned and later fell* |
| the rates | it feeds the **denominator** population exactly as a completed turn that fell in does: TPH and JPH count *dry* turns and jibes (`turnsCounted − outcomes.fellIn`), so neither numerator moves. `wetPerHour` reads the flight-end channel and does not move either — it is the same swim, differently attributed |

Three rules keep one swim from being reported twice (`_merge_aborted`): a candidate the ladder
did not call `fell_in` is dropped; one that overlaps a **counted** turn is dropped, because
that turn already owns the fall; one that overlaps an uncounted **course change** replaces it —
the same sweep, read the same way, with one more thing known about it. The flight end itself is
then owned by the new turn (`ownedByTurn`), so it leaves the straight-line tallies the way every
turn-owned end does.

**Naming it.** An aborted turn is named by the axis it was *going through*, which is a
different question from the completed turn's. `turnClassifyMinAngle` does not apply: it reads
the angle as evidence of intent, and an aborted turn's angle is evidence of *when the rider
fell*. And a crossing cannot be required, because an aborted turn is very often the sweep that
never reached the axis — both of the tester's attempts stopped short of head-to-wind — so
requiring one would leave the label unreachable for exactly the maneuvers this pass exists to
count. Where the sweep **did** cross, that crossing names it, exactly as today; where it did
not, the turn takes the axis its own rotation was closing on: the first head-to-wind or
dead-downwind line ahead of the last heading, in the direction the board was turning. A rider
luffing up from a broad reach who goes in 45° off the wind was tacking; one bearing away from a
reach who goes in was jibing. With no usable wind axis there is nothing to be closing on and it
stays a counted, unnamed `turn`.

**Why 45°, with the corpus as the judge.** It is half the classification floor: the rider has
to have ridden at least half the sweep that would let the engine name a maneuver at all. Over
the 18 committed session fixtures:

| `turnAbortMinAngle` | aborted turns | what the extra ones are |
|---|---|---|
| 30° | 14 | the four below 45° ended **66–133° from any axis** — wobbles before a crash, the mislabel `turnClassifyMinAngle` exists to refuse |
| **45°** | **9** | every one a sweep that was carrying speed into a maneuver and stopped dead |
| 50° | 8 | loses a 48° bear-away that ended with the wrist under |
| 60° | 7 | loses a 52° luff-up that ended with the wrist under, and nothing false is bought |

**What it did to the corpus** (18 committed session fixtures, regenerated from the goldens in
this release):

| | 0.20.0 | 0.21.0 |
|---|---|---|
| counted turns | 560 | 569 |
| tacks | 2 | 4 |
| jibes | 558 | 565 |
| course changes (`rejected`) | 147 | 140 |
| turn outcome `fell_in` | 41 | 50 |
| straight-line falls | 45 | 44 |
| clean jibes | **161** | **161** |
| JPH / CPH, every fixture | — | unchanged |

Nine turns the engine had never counted, seven of them course changes it had already drawn on
the page and could not name. **No clean jibe moves and no rate numerator moves**: the pass can
only ever add a turn that fell in, which is by definition neither dry nor clean. Only one of
the nine was a straight-line fall before — the other eight were falls the page attributed to
nothing at all, which is what the tester saw.

**What it does not catch, on the tester's own recording.** His session gains one tack, which
fell in (`submerged`); the second attempt is refused twice over, and neither refusal is this
pass's to overturn. Its sweep turns at 14.6°/s, below `turnPeakRate`, so it is not a candidate;
and it stopped dead for 4 s before a **42 s recording gap**, which is one second short of
`turnFallStop`, so the ladder can only call it a `touchdown`. A stop that runs into a long gap
and resumes below foiling speed is a swim, and the engine cannot say so today — that is a
flight-end question, not a turn one.

### Glossary — four words that are not synonyms

**The rider-facing twin of this table is generated.** `ios/WingFoilKit/.../Presentation/
MetricGlossary.swift` is the author, `docs/copy/glossary.json` is its artefact
(`COPY_WRITE=1 swift test --filter CopyContractTests`), and every surface reads from it: the
app's *What the numbers mean* topic, `/help/#numbers`, the welcome screen, and
`GlossaryLintTests`, which fails when a rider-facing metric label is not one of its terms.
This table stays the **engine's** names; the JSON carries the **rider's**, the one-line rule,
every spelling a surface may print, and where each one shows. A word in one and not the other
is the drift both exist to stop.

| word | what it is | the rider's word | where it lives |
|---|---|---|---|
| **flew through** | an *outcome*: the ladder found no touchdown and no fall in the tail past the sweep. One of three rungs, and the only one that is not a loss | *Flew through* | `turn.outcome == "flew_through"` |
| **carried** / **success** | the *score verdict*: `score ≥ turnSuccessPct` **and** the Doppler minimum stayed above `foilExitSpeed`. It says what the turn cost in speed and says nothing about how it ended | **Speed kept** (20 Sep 2026) | `turn.success`, `turns.successPct`, FIT `turn_success_pct` |
| **clean** | **carried AND flew through AND quiet for `turnCleanQuietS` afterwards**, and only for a **jibe**. The product's headline verdict (engine ≥ 0.12.0; the quiet tail since 0.17.0). A strict subset of both | *Clean* | `turn.clean`, `turns.jibesSuccessful`, `cleanJibesPerHour`; `turn.cleanBlockedBy` says why not |
| **dry** | outcome is **not** `fell_in` — flew through *or* touched down. "He did not swim out of it" | *Dry* | the JPH and (since 0.13.0) TPH numerators |

They nest: clean ⊂ flew through ⊂ dry. `carried` cuts across all three, which is exactly why
it needs its own word — a jibe can be carried and still swum out of, and before 0.12.0 that
one was called clean.

**"Speed kept", and why the score verdict needed a rider word at all** (20 September 2026). A
tester compared three screens about one afternoon and read *Turn success 29 %* in Garmin
Connect, *93 % flew through* on the website, and 44 % on the phone. All three were right. Two
of them were called some form of *success*, and neither of those two was the same measurement
as the other: Garmin Connect prints `turn_success_pct`, the score verdict over every counted
turn, and the phone printed a *takeoff* success rate. CLAUDE.md has always said `success` and
`carried` are engine-internal and appear in no rider-facing text; the watch's Connect IQ label
was the one place the rule was not enforced, because the string lives in `garmin/` and the
lexicon checker reads it as an ordinary English word. So the score verdict now has a word of
its own on every rider surface — **Speed kept** — and the three numbers have three names:

| the number | the word | where a rider meets it |
|---|---|---|
| `turns.successPct` — held ≥ `turnSuccessPct` of entry speed, never off the foil | **Speed kept** | the watch, FIT `turn_success_pct`, Garmin Connect |
| the outcome ladder's green rung over the jibes | **Flew through** | the session page, the card, the website |
| flights started ÷ pumping attempts | **Got up** | the session page's takeoff cards |

The watch's own label change is **requested, not made**: `garmin/resources/strings/strings.xml`
→ `FitTurnSuccess` must read `Speed kept` instead of `Turn success` (docs/fit-schema.md, field
34). Field 34's id, type and semantics are untouched — this is a display label.

**Falls: one channel, one number** (20 September 2026). The rider-facing falls count is
`flightEnds.all.fellIn` — every fell-in flight end, in a turn or in a straight line — on the
library row (`wetExits`), in the key-metrics block, on the share card and on the session
page's *Fell in* card, and it is what WPH divides. It is *not* `outcomeSplit.falls`, which
adds the turn ladder's `turns.outcomes.fellIn` to the flight-end channel's straight-line
count: two different events, so a split printed under that total need not add up to it. The
flight-end channel's does, by construction (`all == inTurn + straight`). The turn tally keeps
its own three counts and says in its caption what they are out of ("of 57 jibes"). See "Wet is
every fall, not every fallen jibe" below, which is the same rule stated for the rate.

### What a turn records — the shape, not only the endpoints (engine 0.11.0)

Scoring computes more than it used to keep. Until 0.11.0 a stored turn carried its start,
its end, and the two speeds the score is a ratio of, so a per-turn surface could say a jibe
went 11.1 → 7.5 kn but not *when* the bottom of it was, what the rider came out carrying,
how hard he carved it, or where the wind stood at either end. Those four answers already
existed inside the detector and were dropped on the return. They are now persisted, and
**nothing about detection, scoring, classification or outcome changes** — every number on
every fixture is what it was.

| field | definition |
|---|---|
| `minTs` | time of the speed minimum: the sample `minKn` was read at, on the session clock like `ts`/`endTs`. It is the instant the outcome window is searched *past* (`turnRecoverPct` recovery is looked for after it), so it was never a derived convenience — it is the anchor the window already used |
| `exitKn` | **the one new definition.** `speedChannelManeuvers` at the *first sample at or after* `turnEnd` — the same channel and the same rounding as `minKn`, so `entryKn → minKn → exitKn` reads as one line in one unit. `turnEnd` is itself a sample time, so in practice this is the sweep's last sample; the "at or after" wording is what makes the rule total for a segment that ends there. Deliberately **not** the recovery speed: the outcome window already answers "did he get going again", and a fourth number sampled at a moving boundary would not be comparable between two turns. Exit is where the sweep stopped, full stop |
| `peakRateDegS` | the detector's own peak COG rate over the sweep, **signed** with `netDeg`'s convention (+ = clockwise/starboard). The magnitude is the one already tested against `turnPeakRate`; the sign is kept because a rate that reads +38 on one jibe and −38 on the next is the pair of directions, not two different maneuvers |
| `twaInDeg`, `twaOutDeg` | the true wind angles `classify` computed to name the turn: TWA at the sweep's entry, and TWA at its exit wrapped to ±180. **Null when the wind axis is unusable** — the same state that leaves `type` a plain `turn`. A 0 in their place would read as dead upwind, which is a claim about a session that never had a wind direction |

### The crossing, as an event — `axisTs` · `axisBeforeDeg` · `axisAfterDeg` (engine 0.15.0)

Jan defines a jibe as **"a turn through the wind axis"**, and that crossing is exactly what
`classifySweep` has always named a turn by: carry the sweep onto unwrapped TWA, and a pass
through `k·360` is a tack, a pass through `180 + k·360` a jibe. Until 0.15.0 the engine found
that crossing, used it to pick a word, and threw it away. It is now persisted, so a page can
mark the instant instead of only printing its consequence.

| field | definition |
|---|---|
| `axisTs` | the session-clock instant the unwrapped TWA passed the axis — **the same crossing the classification picked**, i.e. the multiple nearest the sweep's middle — **linearly interpolated** between the two samples astride it. Where a non-monotone sweep passes the same heading more than once it is the **first** such pass: the k-multiple was already settled by the classification, and "the moment he went through the wind" is the first time he was through it |
| `axisBeforeDeg` | \|TWA at the sweep's start − the axis\|: how far from the wind the turn began. A jibe entered on a beam reach reads ~90°, one entered already half round reads ~40° |
| `axisAfterDeg` | the **furthest** the heading got past the axis, in the turn's own sense (the sign of `netDeg`), from the crossing to the end of the outcome window (`turnEnd + turnOutcomeLookahead`) — measured on the detector's own unwrapped COG array, **not** on the sweep's endpoint. The sweep ends when the rate drops below `turnContinueRate`, not when the rider stops turning, so a slow continuation below that rate still counts; it is a maximum rather than the value at the end, because a rider who carries on round and then heads back up has still been that far past the axis. The array is the sailing run's, so a run that ends first — he stopped, the fix was lost, the segment closed — simply ends the measurement, which is the honest answer: there is no heading after a run ends |

All three are **null** on a course change, on an unclassified turn and on a session with no
usable wind axis, under the same rule the TWA pair obeys: 0 would be a claim, and there was no
crossing to claim anything about. A `three_sixty` gets nulls too — a full rotation crosses both
lines by construction, so "the axis it went through" is not a thing a spin has.

Where the measurement stops **matters to what the numbers say**: over the 21-session corpus, 66
jibes have less than 30° after the axis measured to the sweep's end and only **55** measured to
the end of the outcome window. The window is the defined one, because the question
`turnAxisAfterDeg` asks is whether the rider came out the other side, not whether he did it
before the COG rate fell below 5°/s.

**Glossary — "clean jibe", the name the UIs use, and the one rule behind it (engine
0.12.0, extended in 0.17.0).** A *clean jibe* is

```
counted  AND  type == jibe  AND  success  AND  outcome == flew_through
                                            AND  a quiet turnCleanQuietS after it
```

— it carried its speed, it flew through, **and** the seconds after it were quiet. `success` is unchanged and still means what
it always did (`score >= turnSuccessPct` **and** the speed never dropped to `foilExitSpeed`
across the *scored window*); it is still reported per turn and still what `tacksSuccessful`
and `turnsSuccessful` count. What moved is that "clean" is no longer that flag on its own.
The verdict is stored per turn as `clean`, so no surface re-derives it.

`borderline` needs no clause of its own: it only ever rides on a `touchdown`, so requiring
`flew_through` already excludes it.

**Until 0.12.0 clean was `success` alone, deliberately independent of the outcome** — the
reasoning being that a jibe carved cleanly through the sweep stayed clean even if the foil
went in the recovery tail, because the scored window ends where the sweep does. That is
defensible as a measurement and wrong as a word. On 2026-08-29, jibe 13 held 71 % of its
entry speed, spent 54 s off the foil and ended in the water, and the map starred it while
the turns table six rows below called it a swim. A rider reading that does not conclude the
two verdicts are subtly different; he concludes the app is lying. So the outcome joined the
verdict, and clean became a strict **subset** of `flew_through` rather than a reading across
it. `docs/presentation/clean-jibe.md` ("Clean jibe") holds the spelling contract and the ink rule — the
star keeps its own ink, because not every jibe that flew through is clean.

### The quiet tail — a clean jibe needs ten seconds after it (engine 0.17.0)

Jan, 7 Sep 2026: *"We should add an additional requirement for a clean jibe: 'no touch down or
fall within 10 s afterwards'. This only applies to clean jibe, not to carried through."*

**Why 0.12.0's outcome clause does not already cover it.** A turn's outcome window is not a
fixed tail: it runs from the turn's start until the rider is demonstrably flying again
(`turnRecoverPct` held for `turnRecoverHold`), capped at `turnOutcomeLookahead`. A jibe the
rider powers straight out of therefore closes its window in a second or two — which is the
right rule for the *ladder*, because a fall five seconds later is a straight-line loss the
flight-end channel counts, and blaming the turn for it as well would charge one swim twice.
It is the wrong rule for the *word*: a rider who is in the water ten seconds after his jibe
does not call that jibe clean, whatever channel owns the swim.

So `turnCleanQuietS` (**10 s**) asks one more question, of the same `OffFoilEvidence` the two
ladders already read, over `[turnEnd, turnEnd + turnCleanQuietS]`, **stopping at a recording
gap** like every other window in the engine. Three tests, most specific first, first answer
wins — the answer is stored on the turn as `cleanBlockedBy`:

| # | test | `cleanBlockedBy` |
|---|---|---|
| 1 | a **flight end** inside the tail whose outcome is `touchdown` or `fell_in`. `glide_out` and `unknown` are not losses — settling onto the board and carrying on is not a fall, and a truncated end is the recording stopping, which is evidence of nothing | `quiet_flight_end` |
| 2 | an **off-foil spell** of 1 s or longer, measured with the ladder's own `off_foil_run` so "off the foil" means here exactly what it means there. This is the loss too short to end a flight | `quiet_off_foil` |
| 3 | a **submerged** sample: the wrist went under, which the ladder treats as proof of a swim wherever it sees it | `quiet_submerged` |

The flight-end test is asked first because it is the sharpest thing that can be said: that
channel has already classified the loss, so the page can *name* it ("touched down 6 s after")
instead of describing it. The three overlap heavily by construction — a flight end is an
off-foil spell, and a submerged sample is never a flying one — and the order decides only
which word the rider reads.

`cleanBlockedBy` is **null** wherever the score or the outcome already refused the jibe: those
two are printed on every turn surface in their own words, and repeating them as a reason would
say the same thing twice. What it exists for is the two refusals nothing else shows — this one
and `turnAxisAfterDeg`, whose value is `axis_after`.

**This is a `clean` change and nothing else.** The outcome ladder, `success`, the score, every
count, both streaks, JPH and TPH are bit-identical; `jibesSuccessful`, `cleanJibesPerHour` and
the star layer move with `clean`, which is the whole list.

**Why 10 s.** Measured over the 21-session corpus (818 jibes, 278 clean at 0.16.0):

| `turnCleanQuietS` | clean jibes | blocked: flight end / off foil / wrist under |
|---|---|---|
| 0 (off) | 278 | — |
| 6 s | 273 | 3 / 2 / 0 |
| **10 s** | **263** | **13 / 2 / 0** |
| 15 s | 255 | 18 / 5 / 0 |

Six seconds catches only the losses that are visibly part of the jibe's own run-out and leaves
the ones a rider would still connect to it; fifteen starts taking jibes for a fall two thirds
of a minute later that nothing about the turn caused. Ten is where Jan drew it, and the corpus
does not argue: 15 of 278 clean jibes (5 %) had a loss of the foil inside ten seconds of the
sweep. Over the 17 committed fixtures the same change reads **160 → 150**.

The ordering this needs is worth naming, because it looks circular and is not: flight ends are
classified **first** (classification reads no turn), turns are detected **with** them, and the
*ownership* pass — which is the part that does read turns — runs last. `lab/.../goldens.py`
`analyze` and `SessionSummarizer.analyze` both spell it in that order.

### Spatial gate — "real movement around the curve" (Jan)

A COG sweep is not a maneuver. A rider swimming beside the board, or drifting while he sorts
the wing out, produces heading flips that are indistinguishable from a jibe *in angle terms*
while covering almost no water. `turnCogSpeedFloor` catches the slowest of these but not all
— a 2–3 m/s drift clears it. So a candidate must also have **carved an arc**: `turnMinArc`
metres of path across the sweep **and** an effective radius `arc ÷ |Δheading in rad|` of at
least `turnMinRadius`. Failures are **dropped**, not flagged: unlike a bear-away they are not
course changes at all, so they never reach the `rejected` count.

The gate is deliberately *geometric*, not another speed floor. Two sweeps at 4.0 m/s for 3 s
cover the same 16 m of water; the 180° one pivots inside a 5 m radius (dropped), the 90° one
carves 10 m (kept). No speed test can separate those.

**Corpus calibration.** Over the 116 candidates in the three reference sessions (2026-08-07
ciq, 2026-08-05 am, 2026-08-04 pm) the tightest genuine turn measures arc 14.4 m / radius
8.7 m, and the slowest sweeps 4.06 m/s — there is no low-radius population to cut, so at
12 m / 6 m the gate removes **nothing**, with 1.2× margin on arc and 1.45× on radius. That
is intended: it is a guard for future sessions with more swimming, not a correction to these.
That it *works* was verified by disabling `turnCogSpeedFloor`, which lets the drift rotations
back in (arc 1.3–11 m, radius 0.9–5 m, sweep speed 0.7–2.2 m/s, nearly all inside a swim):
the geometric gate removes 18 of the 33 that reappear, and the 15 it keeps are genuine turns
at 3.5–6.5 m/s that the speed floor had been over-rejecting. Radius is the discriminating
half — arc alone cannot separate a slow 8 s wallow (16 m) from a tight real turn.

Stricter settings cost real turns and were rejected: 15 m/6 m kills the 2026-08-07 06:32:50
round-up (14.4 m of arc at 4.8 m/s), 18 m/8 m kills two more 2026-08-04 jibes, and 25 m/6 m
kills 10 including five ground-truthed jibes.

### 360 spins — EXPERIMENTAL, off by default, unvalidated

A 360 is a full rotation ridden as one carve. It is **not** a maneuver in the sense the rest
of this section uses: it crosses the wind axis and the downwind line by construction, so
tack/jibe says nothing about it, and it is neither an attempt the rider made at a maneuver
nor a course change he failed to complete. It therefore gets its own kind (`three_sixty`),
its own count (`summary.turns.threeSixties`), and touches **nothing** else: not
`turnsCounted`, not `rejected`, not the outcome ladder, not the streaks, not the rates.

The detector (`lab/src/wingfoil_lab/turns.py`, `detect_three_sixties`) takes a sweep of the
unwrapped COG that turns `threeSixtyMinDeg` **one way** inside `threeSixtyMaxS`, never backing
off its own running extreme by more than `threeSixtyReversalDeg`, entered on foil
(`foilEntrySpeed` at the first sample) and never below `threeSixtyMinKmh` inside the sweep.
The monotonicity test is what refuses a tack and a jibe that happen to add up to a circle;
the speed gates are there because **a stopped rider's COG spins freely** — with no way on,
the bearing between fixes is a metre of GPS noise, and a rider sitting on his board draws a
perfect monotone 360 out of nothing at all. The pass is purely additive: it never removes or
renames a turn the main scan reported, so a spin that overlaps a detected jibe leaves that
jibe exactly where it was.

**`detectThreeSixty` is false and the whole thing is dark.** With the flag down nothing
detects a spin, `threeSixties` is absent from the document (absent, not null — a key that is
present is a key a consumer starts reading), the parameters are not echoed in `config`, and
every committed golden is byte-for-byte what it was. That is deliberate, because:

**Corpus evidence — the detector finds no ridden 360 anywhere.** Over the 16 fixture sessions
(`lab/tools/report_360.py`) the defaults yield **3 candidates**, one each in 2026-08-29 ciq,
2026-08-01 native and 2026-08-03 native. All three are the *same shape*, and it is not a spin:
the rider enters a real maneuver at 20–22 km/h, the detector's own tack/jibe scan reports it
(+293°, +161°, +102°), the foil stalls mid-turn, and the board keeps pivoting through the last
100–150° at 5–7 km/h with 1–2.5 m between fixes before he goes in. **Every one of them ends
`fell_in`**, with stops of 8, 10 and 32 s. They are botched maneuvers with a spin-out on the
end — a fourth false-positive shape, between "stopped and drifting" and "GPS noise at low
speed", and one the speed gates as specified do not catch because the *entry* is genuinely
fast.

The sensitivity is one-sided and says the same thing. `threeSixtyMinKmh` at `foilExitSpeed`
(8 km/h) removes all three and leaves **zero**; at 2 km/h the count goes to **9**, and the six
that appear are unmistakable pivots (radius down to 1.4 m, arc down to 8 m) — again all nine
`fell_in`. `threeSixtyMaxS` at 8 s (the `turnMaxDuration` value) also leaves zero: all three
take the full ten seconds, which is itself evidence that they are collapses rather than
carves. `threeSixtyReversalDeg` is not binding at all — at 60° the count is still 3.

So the honest reading of this corpus is that it contains **no 360 to calibrate against**, only
spin-outs that resemble one, and that 5 km/h is probably too permissive a floor. It is left at
5 anyway: raising it to 8 on evidence made entirely of false positives would be tuning the
detector to report nothing, which is not the same as tuning it to report spins. The parameter
that decides this is `threeSixtyMinKmh`, the fixture that would decide it is a session with a
deliberately ridden 360 in it, and until one exists the flag stays down.

### Watch approximation (garmin/source/detectors/TurnDetector.mc)

The watch runs the same parameters in one forward pass with bounded work per 1 Hz tick and no
allocation, so it necessarily differs from the lab pass. The phone recompute is authoritative;
these are the known divergences, all of them conservative (the watch under-counts rather than
inventing turns):

- **No non-maximum suppression.** The first sweep that clears the gates opens a candidate and
  the detector then *follows* the rotation while it keeps turning (`turnContinueRate`, capped
  at `turnMaxDuration`), so classification still sees the whole sweep. The lab instead scores
  every candidate and keeps the widest. Two turns inside one 8 s window merge into one.
- **Edge trim is the scan itself.** Walking back from the newest sample stops at the first
  step below `turnContinueRate`, which trims both edges greedily. A genuine turn containing a
  ≤5 °/s lull is split at the lull rather than spanning it.
- **No re-detection during the outcome window.** A second turn started before the first one's
  outcome resolves is not detected at all.
- **Doppler only.** There is no positional speed channel live, so the sharp `min(Doppler,
  positional)` test degrades to the firmware's ~3–4 s smoothed Doppler: short touchdowns the
  positional channel would expose can read as fly-throughs on the watch.
- **The outcome window is the judging window.** The watch measures the stop inside the
  recovery-gated window only, capped at `turnOutcomeLookahead`. Since engine 0.13.0 the phone
  does the same — `turnOutcomeWindow` is 12 s, equal to the lookahead — so this is **no longer
  a divergence in the cap**, only in what is reported: `stopped_s` is not published by the
  watch.
- **Recovery is searched from the sweep end**, not from the speed minimum, and the entry speed
  is the max over `entrySpeedWindow` of the *Doppler* history.
- **Submersion is read in the pressure domain.** `turnBaroDrop` (25 m of apparent altitude) is
  converted once to a ~300 Pa rise in `rawAmbientPressure` against a slow (~50 s) baseline that
  refuses to adapt while a spike is in progress. Same positive-only semantics. **Since engine
  0.22.0 the two rules are the same shape**: the phone's baseline is the same EMA, spelled as
  the time constant `BARO_TAU_S` = 50 s so that it is exact at any sample rate rather than at
  1 Hz only, and it holds under a spike exactly as the watch's does — this divergence used to
  be a real disagreement about what the wrist was measured against, and is now a difference of
  domain (pressure vs. metres) and nothing more. The **settle release** is the phone's too,
  spelled in the pressure domain (watch 0.9.17): when the rise has been over the threshold for
  `BARO_SETTLE_S` = 20 ticks *and* every sample in those 20 sits within `BARO_SETTLE_PA` =
  ±60 Pa of the current one — the phone's ±5 m at the same ~12 Pa/m this conversion uses — the
  level is accepted as the new ambient (`baseline = pa`, that sample dry). It is what keeps a
  watch whose pressure channel *re-anchors* after a dunk (a tester's fenix 5X Plus) from
  latching `submerged` for the rest of the session. A pause is a hole in the stream rather than
  quiet water, so both resumes re-anchor the baseline — the phone's `gap_before` restart, which
  the watch has no other way to see. A dunk is a spike; a level is not a dunk, and the price is
  the phone's too: water held to within 5 m for 20 s reads dry from its 20th second.
- **Every turn is RE-TYPED when the axis changes** (watch 0.9.18), which is where two divergences used to be. `TurnDetector` keeps a **turn log** — one four-byte record per counted turn: the entry bearing, the signed net rotation, the outcome, and a *clean-eligible* bit (the score cleared the bar, the foil held, and the quiet tail ran out) — written in `_resolve`, which is the first moment the geometry and the verdict both exist. Whenever the effective wind axis moves, `rebuildWindSplit` throws all eleven per-kind counters away and recomputes them from that log: `tackCount` / `jibeCount`, the six outcome rungs, `cleanJibeCount`, and the port / starboard entry split. The trigger is the axis itself (`MetricsEngine._syncWindSplit`), so the estimator locking, the estimator revising itself and the rider typing a bearing into the menu all reach the counters by one path and each of them exactly once.

  What that buys: **`flew + touch + fell == that kind's count` exactly, at all times, with an axis set** — the rows on the Tacks & jibes page add up. And a jibe the rider rode before the estimator spoke gets its star: the clean-eligible bit is a fact about the riding, the KIND is a fact about the wind, and only the second one is being re-decided. Until 0.9.18 a one-shot pass ran at the first lock and added to `tackCount` / `jibeCount` alone, so a pre-lock jibe was a jibe with no rung and never a clean one; the invariant was a `<=` that closed only for the turns typed after the lock, and the CPH the watch then printed under-read for the opening minutes.

  What it still does **not** touch, and deliberately: `turnCount`, the session-wide outcome tally, the streaks and the scores. Those were real observations made at the time and are not re-judged on hindsight evidence, so `tackCount + jibeCount <= turnCount` still holds with the difference being the sweeps that are course changes under this axis.

  **The cap.** The log holds **512 turns, 2 KB**, allocated once. A turn every thirty seconds for four hours is 480, so a session does not reach it. Past it the oldest record is dropped, and before it goes it is typed against the axis in force at that moment and folded into a frozen base every later rebuild starts from — so the invariant survives the cap. What a rebuild cannot do for a dropped record is re-type it against an axis the rider changes *later*, and a turn 512 maneuvers ago was ridden hours after the estimator locked. Asserted by `perKindOutcomesAddUpToTheKind` and `rebuildSplitsTheTurnsTheAxisWasLearnedFrom` in the barrel suite.
- **No pump corroboration** (step 3 of the ladder): the watch cannot promote a fly-through to a
  touchdown on accel evidence, so it reports slightly more fly-throughs than the phone.
- **The watch does not measure the axis crossing**, and knows neither axis parameter. It has no
  `axisTs`/`axisBeforeDeg`/`axisAfterDeg` to publish and applies neither `turnAxisBeforeDeg` nor
  `turnAxisAfterDeg`, so its clean count is unchanged by them. Both are 0 by default, which is
  the only reason this is a silence rather than a divergence: move either on the phone and the
  wrist and the page will disagree about which jibes were clean, exactly as they do for every
  other tuned threshold.
- **No aborted turn** (engine 0.21.0, and the one divergence this release adds). The watch has
  no pass for a sweep that ended in the water: its detector only ever opens a candidate that
  clears `turnMinAngle`, and a fall halfway through a tack therefore still reaches the wrist as
  nothing at all. **What it should do**, when it is ported: keep the live candidate's sweep when
  the rotation stops because the *speed* died rather than because the rate fell below
  `turnContinueRate`, and if its net change clears `turnAbortMinAngle` (45°), let the existing
  `_resolve` ladder judge it — the watch's submerged-or-stop rung is already the rung that
  matters here, and its first answer is the fall. Name it by the axis ahead of the last heading
  in the sweep's own sense (the phone's `classifyAborted`), since the watch's `classifySweep`
  needs a crossing it will not have; with no axis yet it is a counted `turn`. Until then the
  wrist under-counts turns and falls on a session with aborted maneuvers in it, and the phone
  recompute is what the rider sees — the same conservative shape as every other divergence here.
- **`turnClassifyMinAngle` — same on the watch** (engine 0.13.0, watch 0.9.7): `classifySweep`
  applies the 90° floor ahead of the wind check, so a 60–89° sweep is `rejected` (an uncounted
  course change) on the wrist exactly as on the phone, with or without a wind axis. Not a
  divergence; listed so nobody re-adds one.
- **Foil % is the same ratio over a different clock.** The phone divides `foilTimeS` by
  `timerTimeS` (T2, the cleaned track's non-gap total); the watch's screens and FIT field 22
  divide by `Activity.Info.timerTime`, its own native moving clock. Both exclude pauses, so
  the two agree to within what the cleaner trims — but they are not the same clock, and the
  divergence check's "Foil time" comparison (> 5 %) is a comparison across them.
- **Bear-aways are dropped, not carried.** They increment a `rejected` counter and are not
  given an outcome, so the watch has no equivalent of the lab's bear-away outcome window.
- **Classification IS retroactive since 0.9.18**, on the watch as on the phone: a turn is
  named by the axis in force, and when that axis changes every logged turn is named again
  (the turn-log bullet above). Until then a turn detected before the rider set the axis
  stayed generic for the rest of the session and only the auto-wind lock's one-shot pass was
  allowed to look back. The watch's wind is still the rider's bearing or the watch's own
  estimate, never a third source.
- **GPS below `Position.QUALITY_USABLE` freezes the detector**, including any open outcome
  window, matching how the other watch detectors treat a gap.
- **CPH is off the device app's screens** (device app 0.9.18; it was on the Turns page from
  0.9.5). Jan's layout review of 21 September 2026 took it, and the reason is the divergence
  this bullet used to describe. The watch divided `TurnDetector.cleanJibeCount` by
  `SessionController.elapsedNowS()` — the engine's own timer while recording, the FIT's
  `total_elapsed_time` once saved — while the phone divides by `timerTimeS`, the **cleaned
  track's** non-gap total (T2). Neither was wrong; they answered the same question over
  slightly different afternoons, and the wrist had no cleaned track to offer. But a rate is a
  *reading* of a count rather than a count, it is the kind of number a rider sits down with,
  and it was spending a whole row on a page whose four counts are the fact. The count itself
  stays on the wrist, first on the Turns page's ladder row behind its star; the rate lives on
  the phone, where it has a caption to explain itself and a clock it can name.
  `PageModel.cleanPerHour` / `fmtCph` and the 60 s no-rate floor are kept and still tested —
  the number is one page-editor decision away from coming back and the floor is the part of
  it nobody should have to re-derive.
- **The DATA FIELD still shows it**, over its own clock — see the bullet below. The field is
  parked (ADR-020) and its screens did not move.
- **A clean jibe is `cleanJibeCount`, and since 0.9.18 the axis can still award one.** This was
  a divergence: the one-shot backfill recovered the tack/jibe split from a sweep log written
  when a sweep *closed* — before its outcome window resolved — so it carried geometry only, a
  turn backfilled into `jibeCount` was never backfilled into `cleanJibeCount`, and the watch's
  star count under-read for the opening minutes of a session with no manual axis. The turn log
  above records clean-ELIGIBILITY instead, which is decided when the turn resolves and does not
  depend on the kind, and `rebuildWindSplit` applies the kind afterwards. A successful
  fly-through that was a generic turn at the time becomes a clean jibe the moment an axis says
  it was a jibe.
- **The watch holds the star for the quiet tail** (device app 0.9.9, engine 0.17.0). A clean
  candidate — a jibe that flew through and held its speed — is not counted when its outcome
  resolves; `cleanPending` is set and the detector watches the samples until
  `CLEAN_QUIET_S` (10 s) past the sweep end, on every tick whatever the state machine is
  doing. An off-foil spell of `QUIET_OFF_FOIL_S` (1 s, both-ends convention: two consecutive
  samples not in a flight, below `foilExit`, or submerged at 1 Hz) or any submerged sample
  withdraws it; the clock running out grants it and increments `cleanJibeCount`; a GPS gap
  settles it as clean on the next tick, as the phone's window stops at a gap and calls what
  it saw. `EVENT_CLEAN_SETTLED` carries the answer to the controller, which buzzes the
  clean-jibe flourish or the ordinary fly-through tick *then* rather than at `EVENT_FLEW`
  — so on the wrist a clean jibe's buzz arrives up to ten seconds after the turn, and the
  count on the glass never has to be withdrawn. The outcome (`EVENT_FLEW`, the FIT marker,
  the history log) is still final at resolve. What the watch cannot see is a *flight end*
  the phone classifies inside the tail; the 1 s off-foil spell covers the same loss one way
  or another, so the two agree on the corpus fixtures.
- **The watch never had the pump rung** (engine 0.18.0, corrected 9 Sep 2026). An earlier
  version of this list claimed the watch "keeps the old rule at the old speed"; it does not
  and never did — `TurnDetector._resolve` has three rungs, submerged-or-stop → fell in, any
  loss of the foil → touchdown, else flew through, and the accelerometer feeds none of them.
  So at the 0.18.0 defaults, where the phone's rung is unreachable, the two agree; only a
  dev build with `turnPumpedMarginalSpeed` raised above `foilExitSpeed` diverges from the
  wrist, and in the phone's direction.
- **No pump corroboration reaches the clean flag either.** Success is the score pair only
  (`score >= turnSuccessPct` and the minimum stayed above `foilExitSpeed`), read off the
  firmware's smoothed Doppler, so the watch calls slightly *more* jibes clean than the phone
  does — the same Doppler-only caveat two bullets up, inherited by the stricter metric. The
  0.12.0 rule itself is **not** a divergence: the watch applies the same
  `outcome == flew_through` test when the turn's outcome resolves, so `cleanJibeCount` counts
  the same four things the phone's `clean` flag did in 0.12.0, over the watch's own evidence.
  The **fifth** thing, the quiet tail, is a divergence, and it has the bullet above.
- **The DATA FIELD's CPH divides by the native activity's TIMER TIME** (field ≥ 0.9.6). Same
  numerator (`TurnDetector.cleanJibeCount` out of the shared barrel), same 60 s floor, same
  `--` below it, same one decimal — a third denominator. `garmin/field/` does not own the
  recording, so it has no `SessionController` and no way to ask Garmin for the wall clock since
  START; what it has is `Activity.Info.timerTime`, which is the *moving* clock and stops while
  the rider is paused. So the three implementations divide by three spans of the same
  afternoon, each the widest one available to it: the phone by `durationS`, the elapsed span of
  the **cleaned track**; the device app by `SessionController.elapsedNowS()`, the session's own
  clock **including** pauses; the data field by **timer time**, excluding them. On a session
  ridden straight through, all three agree to within what the cleaner trims off the ends. On
  one with a long lunch in it the data field reads **highest** of the three, because a rate
  whose denominator excludes the pause is a rate per hour *sailing* rather than per hour on the
  water. That is the flattering direction, and it is the one place on this list where the watch
  side is not conservative — which is why it is written down rather than left to be discovered.
  Pinned by `cphIsARatePerHourWithAMinuteFloor` and `cleanMetricsReadTheDetectorAndTheTimer` in
  `garmin/field/tests/FieldTests.mc`.
- **The data field is also the only one of the three that WRITES the clean count**
  (`clean_jibes`, session field 51 — docs/fit-schema.md). The device app's session message is
  full, so its count lives on the glass and nowhere else. Neither writes the rate.

