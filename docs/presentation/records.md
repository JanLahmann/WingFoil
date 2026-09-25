> Part of `docs/presentation.md`. Engine 0.25.0.

## Record windows

Nine kinds, in canonical order: `best2s, best10s, best5x10s, best100m, best250m, best500m,
bestNm, bestHour, alpha500` — the nine the all-time speed table below shows, in the order
it shows them (`RecordWindowSelection.catalogue`; `library.RECORD_KINDS` gives every one of
them a `window_key`).

**`bestHour` joined the other eight on 21 September 2026.** It had been inert for as long as
the picker existed, on the argument that an hour-long window lights the whole track and so
says nothing. Say what it does light, then: on the corpus's first best hour
(`2026-08-03-1440`, 6.746 kn, engine 0.23.0) the glow is 3 600 s of a 7 135 s afternoon —
half the track. On a session barely longer than an hour it is nearly all of it. That is the
truth of the record rather than a reason to hide it: the best hour of a two-hour ride *is*
most of that ride, and the rider is better served by seeing which half than by a row that
names a number and then refuses to say where it happened. It was also the one row in the
table that answered no tap, and a table where the ninth row is dead teaches that the other
eight might be too.

Default highlighted window: `best2s`. The picker: tapping a record
highlights *that* window on map and chart; tapping the selected one returns to the default;
selection is transient (never persisted); a record with no achieved window is inert and
says nothing. **5×10 s highlights all of its windows** — up to five disjoint runs, five
glows on the track and five bands under the chart — because the record *is* the five and
one segment misnames it (iOS drew only the top run until 6 Sep 2026; the web always drew
the list). **The session header carries no numbers**: it is the date, the discipline badge
and the wind line, because duration and distance are the block's first two cells eight
points lower and the block is the contract the card mirrors (6 Sep 2026).

## All-time records — two tables, one page

The **speed table** is the nine GP3S kinds above, and it is the only one that can carry the
`uncertified` mark (§ "Uncertified speed"). Under it sits the **session records** table: the
best *afternoons* rather than the best windows, in this order on both platforms —

`Longest flight` (captioned `max N m in one flight` — `summary.maxFlightM`, the **furthest
any one flight went**, because six minutes downwind and six minutes of pumping in a lull are
not the same flight. Deliberately not the winning flight's *own* distance: the number never
was that, and until engine 0.13.0 the caption said it was) · `Most flights` ·
`Highest on-foil share` ·
`Most clean jibes` · `Best CPH` · `Best clean-jibe rate` · `Longest dry streak` · `Longest
flew streak` · `Longest session` · `Most distance`.

- **CPH is `jibesSuccessful / (timerTimeS / 3600)`** (engine ≥ 0.13.0) — clean jibes per
  hour of **timer** time: the hour the recorder was running, not the elapsed span it was
  running across, so a paused break does not quietly deflate the number a rider quotes.
  `durationS` is still what the row prints as the session's *duration*.
- **The clean-jibe rate needs at least five jibes**, and the row says so. Four out of four is
  a good afternoon; it is not a rate. The floor is one constant on each side
  (`SessionRecordKind.minJibesForRate`, `library.MIN_JIBES_FOR_RATE`).
- **No certification here.** A degraded recording can misreport a speed; the number of jibes
  it holds and the minutes it lasted are not claims its speed channel makes, so the badge
  the speed table wears would be answering a question nobody asked.
- Same filters and the same exclusions as the speed table (spot / gear / since; the example
  session, a provisional row and a friend's afternoon count in neither), and the same tie
  rule: **a tie goes to the earliest session** — the record was set then, not re-set later.
- **Absent is never zero**, and here it bites twice: a stored row written before the counts
  existed (web digest schema 5, iOS schema v10) has no clean-jibe count and no streaks, and
  a kind nobody has a positive value for is dropped from the table rather than shown as a
  dash or a flattering `0`.

**The empty screen says why it is empty, and never blames a filter nobody set**
(15 September 2026, `ExampleOnlyNote`). The one-tap first run — install, *Try the example
session*, an analysed session two seconds later — used to end on Records reading *"No
qualifying speed window under this filter"* with no filter applied, and on Trends reading
*"Widen the range or clear the spot and gear filters"* on a library of one row whose range
and filters could not have helped: the example is excluded from both on purpose (the bullet
above; `LibraryStore.clause`), and no control on either screen reaches it. That exclusion was
written down for Apple's reviewer (`ios/store/appstore.md`) and for nobody else.

Both screens now branch three ways — **nothing at all** (import or sync a session), **only
the example** (`SessionStore.hasOnlyExampleSessions`, the clause restated on the in-memory
list), and **a filter that really is set**, which keeps the sentence it was written for. The
middle branch says the fact in the rider's words and ends on the step that changes it: *the
example session is on loan, not ridden, so it is kept out of your personal records on
purpose. Import a .fit file, or connect intervals.icu in Settings, and your own bests appear
here.* Its title is a promise rather than a fault — *Your records start with your first
session* — because nothing is broken and nothing is missing; the records have not been earned
yet. Trends says the same in its own terms, and neither title mentions a range.

