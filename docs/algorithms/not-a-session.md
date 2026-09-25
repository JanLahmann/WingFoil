> Part of `docs/algorithms.md`. Engine 0.25.0.

## Not a session (phone/web, engine ≥ 0.19.0) — `summary.isSession` · `summary.notASessionReason`

Every number a library reports is an average or a total over "sessions", and until 0.19.0 the
engine had no opinion about what one is. A recording was a session because it was a file.
Jan's library on 14 September 2026 held thirteen recordings from the two days before it —
**0:00–0:24 min, 0.0 km, 0 % on foil** each, the ones a rider makes pressing start on the beach
and stopping again — and every one of them was in "44 sessions", in the period totals, in the
gear totals, and in the Trends *on foil* line, which it dragged to zero at the right-hand end.

**The rule, in one line:**

> A recording is **not a session** when `foilTimeS == 0` **and** (`durationS <
> notASessionMaxDurationS` **or** `distanceM < notASessionMaxDistanceM`).

| param | default | units | notes |
|---|---|---|---|
| `notASessionMaxDurationS` | **120** | s | the duration floor. Only ever consulted for a recording with **no foil time at all** |
| `notASessionMaxDistanceM` | **200** | m | the distance floor, over `records.distanceM`. Same conjunction |
| `summary.isSession` | — | bool | true for every recording the rule does not catch |
| `summary.notASessionReason` | — | code | `too_short` · `no_distance` · `no_recording`, else null. A **code**, never a sentence; the words are in docs/presentation/not-a-session-spots.md, "Not a session" |

**Zero foil time is the conjunct that does the work, and the other two only qualify it.** That
ordering is the whole design. A *skunked* afternoon — an hour of pumping in no wind, two
kilometres of it, never once up on the foil — **is a session**, and the rider's own memory of
it says so; a rule of "no foil time ⇒ not a session" would throw away exactly the afternoons a
rider most wants to look at afterwards. What is not a session is the recording that has no
foil time **and** never lasted or never went anywhere.

**Where the two numbers come from.** The corpus separates the two populations by a wide
margin and the thresholds are set in the middle of it, not at either edge:

| | duration | distance | foil time |
|---|---|---|---|
| the junk Jan saw (13–14 Sep 2026, ×13) | 0:00–0:24 | 0.0 km | 0 s |
| `smoke-60s`, the shortest recording the corpus calls a session | 59.0 s | 226 m | 30.0 s |
| `2026-08-30-1407` (the clipped CIQ excerpt), the shortest *real* one | 645 s | 2 540 m | 431 s |
| every other fixture | 2 524 – 10 414 s | 6.5 – 32.4 km | 1 214 – 5 242 s |

A duration floor anywhere between 24 s and 59 s, or a distance floor anywhere between 0 m and
226 m, would already separate the two populations. **120 s and 200 m are deliberately set
past those bounds rather than inside them**, because the conjunction makes generosity free:
neither floor can reach a recording in which the rider flew — `foilTimeS > 0` has already
answered — so they only have to be comfortably above the junk, and there is no cost to their
sitting above the shortest session ever recorded either. The 60 s smoke fixture is the corpus's
own proof: at 59.0 s it is **inside** the duration floor, `too_short` would catch it outright,
and it is a session because the first conjunct is asked first and 30 of those 59 seconds were
spent flying. (Its 226 m, incidentally, clears the distance floor on its own.)

**A card with no recording behind it is not a session yet.** A provisional row (the watch's BLE
card, its FIT still to arrive — ADR-013) carries `isSession = false` with reason
`no_recording`. It is the only reason the engine never writes: there is no analysis to write
it from. The moment the recording lands, the ordinary verdict is computed over it and
overwrites this one, and on every afternoon actually ridden that verdict is "a session".

**It is a label and never a deletion.** Nothing is removed, hidden, or refused on import. The
row stays in the list with a quiet tag, its page opens, its map draws, its records are on its
own page. What it is kept out of is every number that claims to describe riding: the library's
session count, the trends, the session and all-time records, the period and season blocks, the
gear totals, the widget snapshot's week, and the spot's visit count. One rule, one place per
platform — `LibraryStore.clause` on the phone, `counts_towards_records` on the web.

**Nothing in the corpus moves.** All 21 goldens report `isSession: true` and a null reason, and
the two keys are the only lines that change in any of them. `ENGINE_VERSION` bumps to 0.19.0
all the same: a 0.18.0 document cannot answer the question, and a stored row reading "session"
because nobody asked is a different statement from one reading "session" because the engine
said so. GRDB **v16** adds the two columns and seeds them by re-deriving the same rule from
`foilTimeS`, `rateDurationS`/`durationS` and `distanceKm`, so a library's junk leaves the
totals at migration rather than whenever re-analysis reaches that row; digest **schema 10**
does the same on the web (`library.py`, `entry_is_session`).

