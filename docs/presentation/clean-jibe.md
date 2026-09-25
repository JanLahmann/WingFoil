> Part of `docs/presentation.md`. Engine 0.25.0.

## Clean jibe — the name of the strict verdict, and how it is spelled

**A clean jibe is a counted jibe you fly all the way through, carrying your speed, and stay
up for ten seconds after — no touchdown, no swim, at or above the success threshold of your
entry speed.**

That is the engine's per-turn `clean` flag, and every surface reads it rather than
re-deriving it: `counted && type == jibe && success && outcome == flew_through`, plus a quiet
`turnCleanQuietS` after the sweep (`docs/algorithms/turns.md`, "The quiet tail"). The metric was
called "turn success" or "carried through" or "held speed" on four screens and is called one
thing on all of them.

**The quiet tail is the third clause, and it arrived on 7 Sep 2026** (engine 0.17.0). Jan:
*"an additional requirement for a clean jibe: no touch down or fall within 10 s afterwards.
This only applies to clean jibe, not to carried through."* A turn's outcome window closes as
soon as the rider is flying again, so a jibe powered straight out of is judged over two
seconds and the touchdown at +7 s belongs to the flight-end channel — right for the ladder,
wrong for the word. On the corpus it costs 15 clean jibes in 278. Only `clean` moves: the
outcome chip, the score, the counts and both streaks say exactly what they said before, which
is why a rider who reads "flew through" over a jibe with no star has to be told why — see
"Turn detail".

**Until engine 0.12.0 clean was the `success` flag alone** — the score verdict, deliberately
independent of how the turn *ended*. That let a jibe be starred as clean on the map and
listed as a swim in the table six rows below it, which is what happened to 2026-08-29's jibe
13: 71 % of its entry speed held, 54 s off the foil, in the water. The word had to mean what
a rider means by it, so the outcome joined the verdict and the clean counts fell on eleven of
the seventeen fixtures.

**The rider has two tiers, and `success` is not one of them** (7 Sep 2026). What a rider
reads is:

| tier | what it asks | engine |
|---|---|---|
| **flew through** | did the foil survive the turn *and* the recovery out of it — no touchdown, no swim | `outcome == flew_through` |
| **clean** | that, **and** did it hold its speed, **and** were the ten seconds after it quiet — a jibe word | the per-turn `clean` flag |

`success` / `turnsSuccessful` / `successPct` / `tacksSuccessful` — the score verdict on its
own, over every counted turn — is an **internal** quantity. It is the input to `clean` and
it is never a label: no card, row, chart, caption, column or total may print it under any
name. It was briefly to be called "carried"; that name is retired, and the word does not
appear on a surface. What *is* rider-facing is the **score** itself — "held 71 % of entry
speed" — because that is a number and its meaning is on its face; a boolean derived from it
is a verdict the rider did not ask for.

Where a surface used to print the score verdict, it prints the **outcome** instead: the
session grid's card is "Flew through" over the jibe share, the trend chart is
"Flew-through rate" over every counted turn, the library totals row is "Flew through", and
the per-turn table keeps `score` and `clean` and dropped its boolean column.

**The spelling is a contract, both halves of it:**

| context | spelling | example |
|---|---|---|
| the product | **CleanJibe**, one word, camel-cased | "CleanJibe for Garmin" |
| the metric / the sport term | **clean jibe**, two words, lowercase | "7 of 10 clean", "12 clean" |
| a label position that capitalizes | **Clean jibes** | the session card's title, the trends chart |

Never "CleanJibes" for the metric and never "clean jibe" for the app. A sentence that
means the count is lowercase even when it opens with the word.

**It is not the ladder's green, and no surface may let the two blur.** "Flew through" is
how the turn *ended*; clean asks that *and* what it cost. Since 0.12.0 clean is a strict
**subset** of `flew_through` — every clean jibe flew through, and on the corpus session 24 of
the 35 jibes that flew were clean. That is the whole reason the two must stay visibly separate: the
distinction is no longer "these disagree" but "this one is narrower", and a surface that drew
them alike would be claiming every jibe that flew was ridden. So the clean count never wears
the outcome ladder's inks, never sits inside the three-count tally, and never borrows the
word "flew". Where it is a *count* beside the tally it is drawn in neutral ink, as the
stricter reading of the same set of turns; where it is a *mark of its own* — the map's star —
it carries the clean ink (`DesignTokens.Clean.jibe` / `--wf-clean-jibe`), a green chosen to
be nothing on the ladder. Either way the rule is the same one: clean is the narrower of two
verdicts, and no ink may say they are one.

