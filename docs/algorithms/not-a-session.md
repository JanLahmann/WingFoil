> Part of `docs/algorithms.md`. Engine 0.27.0.

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
>
> Asked before it (engine ≥ 0.26.0): a recording whose FIT session sport is a **land sport**
> is not a session, whatever its foil time says. See "A land sport is not a session" below.

| param | default | units | notes |
|---|---|---|---|
| `notASessionMaxDurationS` | **120** | s | the duration floor. Only ever consulted for a recording with **no foil time at all** |
| `notASessionMaxDistanceM` | **200** | m | the distance floor, over `records.distanceM`. Same conjunction |
| `summary.isSession` | — | bool | true for every recording the rule does not catch |
| `summary.notASessionReason` | — | code | `land_sport` · `too_short` · `no_distance` · `no_recording`, else null. A **code**, never a sentence; the words are in docs/presentation/not-a-session-spots.md, "Not a session" |
| `summary.landSport` | — | string | engine ≥ 0.26.0: the land sport that decided, as the FIT profile names it (`running`, `e_biking`); null on every recording it did not decide |

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

## A land sport is not a session (engine ≥ 0.26.0) — `notASessionReason: land_sport`

Jan, 28 September 2026: his **Berlin Marathon** came in through intervals.icu and was analysed
as **98 % on foil, 10.65 kn, 2 jibes**, and a run named "9 5 4 Supporting Robert" likewise.
Two things had to be wrong for that. The intervals.icu filter rescued any activity whose name
*contained* "sup", on any type ("Supporting"), and the engine had no opinion about a sport: a
runner at 5 min/km is at `foilEntrySpeed` (12 km/h) already, so most of a marathon reads as
flight.

**The rule.** A recording whose FIT `session.sport` is one of these is not a session, and the
check runs **before** the foil-time conjunct above, because a run's foil time answers nothing:

| FIT `sport` | enum | |
|---|---|---|
| `running` | 1 | road, trail, track and treadmill are its sub-sports |
| `cycling` | 2 | road, mountain, gravel and indoor likewise |
| `cross_country_skiing` | 12 | skate skiing is its sub-sport (30 Sep 2026) |
| `alpine_skiing` | 13 | backcountry and resort are its sub-sports (30 Sep 2026) |
| `snowboarding` | 14 | 30 Sep 2026 |
| `mountaineering` | 16 | |
| `hiking` | 17 | |
| `e_biking` | 21 | |
| `motorcycling` | 22 | |
| `driving` | 24 | the watch left running in the van, on the road |
| `inline_skating` | 30 | 30 Sep 2026 |
| `ice_skating` | 33 | 30 Sep 2026 |
| `snowshoeing` | 35 | 30 Sep 2026 |
| `snowmobiling` | 36 | 30 Sep 2026 |

The skate and snow rows joined inside engine 0.27.0 (Jan, 30 Sep 2026): they are every skate
or snow sport the FIT profile has. Skateboarding has no FIT `sport` of its own, so a
skateboard recording says `generic` or `training` and is left to the other rules.

A parser that has no name for a sport reports its number, so `"1"` … `"36"` of the table count
too. The
reason is `land_sport` and `summary.landSport` carries the name (null everywhere else).

**What is deliberately not on the list.** `walking` (11), `generic` (0) and `training` (10):
the CIQ app, FoilMotion and the Walk-typed imports file real watersport sessions under them,
and `generic` is what the two app-recorded fixtures in the corpus say. Every water sport.
(Until 30 Sep 2026 the snow and skate sports were left off too, on the ground that a wing on
skis or skates is still a wing; Jan put them on the list, since this app judges foil
sessions and a snow-kite afternoon is not one.) The list only
ever *adds* a reason to stop counting, so a sport left off it is the old behaviour, never a
lost session.

**Which files say a sport.** FIT only, in practice: a TCX's `Activity/@Sport` is not read
(docs/algorithms/imports.md), and a GPX from Strava carries Strava's own `<type>` spelling
(`Run`), which is not a FIT name and is not matched. An Apple Watch session carries its
HealthKit type, which is always a water one.

**It is a label, like the other three.** The row stays in the list with its own tag, "Not a
watersport", the page opens and says what the file was recorded as, and the recording is
out of every number that describes riding by the same clause as before (`isSession = 0`).

**A snow sport gets its own line** (30 Sep 2026, ADR-036 amendment). The row's tag stays "Not
a watersport" for all fourteen land sports, skate included, but the page's line is not the
generic one for the five snow sports (`alpine_skiing`, `cross_country_skiing`,
`snowboarding`, `snowshoeing`, `snowmobiling`): "Not a watersport" undersells why, since a
wing on skis is not just the wrong sport, it has no foil at all. Jan: "CleanJibe reads
foiling on water. A snow-wing day has no foil to read." `NotASessionNote.snowSports` names
the five; `verdicts.notASession.lines.3` is the sentence, docs/copy/verdicts.json.

**The import filter, fixed at the same time** (ADR-036). The intervals.icu name rescue — the
one that catches the CIQ recordings mis-typed as Walk — now applies only to a type that could
be a watersport (Walk, Workout, Other, WaterSport, no type, or a type the list does not know)
and never to Run, Ride, Hike, Swim or the other known land and gym types; and it matches
**whole words**: "SUP", "wing foil", "foiling", "Wingfoilen" yes, "Supporting" and "super"
no. Same rule in the kit (`WatersportName`, `IcuClient.isWatersport`), `lab/tools/download_icu.py`
and `web/js/icu.js`. The Strava list keeps its any-type rescue, because the rider picks from
it, but takes the whole-word match — and since 30 Sep 2026 (Jan) a **run, ride or hike**
(`Run`, `TrailRun`, `VirtualRun`, `Ride`, `VirtualRide`, `EBikeRide`, `EMountainBikeRide`,
`MountainBikeRide`, `GravelRide`, `Hike`; `StravaActivityFilter.landTypes`) is
offered only when its name holds a **wing or foil** word: "Wingfoil Torbole" typed Ride yes,
"SUP downwinder" typed Hike no. A walk keeps the any-word rescue, as on the intervals.icu path, where watch apps file real sessions as Walk: "Kite beach" typed Walk yes. It is the same whole-word pattern,
narrowed to its words that contain "wing" or "foil" (`WatersportName.saysWingOrFoil`).
The web has no Strava door.

**Stored libraries.** The phone re-analyses every row on the version bump
(`SessionIngestor.reanalyzeStale()`, `engineVersion` is the staleness key), so a run already
in the library gets `land_sport` on the next launch. The web re-derives from the stored
digest's own `sport` (`library.entry_is_session`), so a run saved by an older engine leaves
the totals the next time the library opens.

**The corpus.** No fixture is a land sport (the 16 FIT files say `windsurfing` or `generic`, the
GPX and the two TCX say nothing), so every golden moves by the version and one null key,
`summary.landSport`; the skate and snow rows move none. The watch computes no session verdict; nothing to port.
