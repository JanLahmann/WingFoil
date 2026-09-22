> Part of `docs/algorithms.md`. Engine 0.24.0.

## Disciplines — one engine, three rigs (engine ≥ 0.18.0, EXPERIMENTAL)

A discipline is **not a fork of the engine**. Every stage, every clock and every verdict in
this file is the one that runs; a *preset* only picks the numbers a few of them are asked
against, and switches off the one channel a windsurfer does not have. `wingfoil` is the
default and is **not applied at all** — not "equal to the defaults", skipped — so a wingfoil
run is byte-identical to one produced before presets existed, and a tuning slider survives a
preset untouched.

| preset | flight thresholds | pumping | turns | notes |
|---|---|---|---|---|
| `wingfoil` | `foilEntrySpeed` 12.0 · `foilExitSpeed` 8.0 | on | unchanged | the published contract, the default, and the only validated one |
| `windsurfFoil` | identical to wingfoil | **off** | unchanged | a foiling windsurfer flies the same foil at the same speeds; he does not pump |
| `windsurfFin` | `foilEntrySpeed` **20.0** · `foilExitSpeed` **15.0** — *PROVISIONAL* | **off** | unchanged | a fin board planes rather than flies, and it planes far faster |

**Pumping off** means the pump channel is never built. `PumpAnalyzer.track` / `pump_track` is
not called, and every consumer is handed the `nil` a source with no accelerometer already
hands them — so there is no second code path, and every stage degrades exactly the way it has
always degraded: no pump episodes, no `takeoffs[].pumps`, no `flights[].takeoffPumps`, no
`summary.takeoff.totalPumpStrokes`, `turn.pumped` and `flightEnd.pumped` never set, no HR pump
cost. The pump rung of the outcome ladder is **refused** rather than merely unreachable
(`turnPumpedOutIsTouchdown` = false): with no burst to corroborate, a switch left on would
claim otherwise. The takeoff analysis reduces to what the speed channel alone can state —
*planing started*, at the flight start, with the run that produced it.

**The two speeds move in four configs at once**: the flight hysteresis, the turn ladder's
`foilExitSpeed`/`foilEntrySpeed`, the flight-end ladder's, and the takeoff analyser's. They
have to: `analyze` shares one off-foil evidence object between the three ladders only while
they agree, and the outcome ladder's "lost the foil" rung is read off the exit speed — which
on a fin board is what *stopped planing* means. Holds, `minFlightDuration` and every turn
parameter are unchanged: a plane holds like a flight does, and a jibe is a jibe.

**Tuning is per preset too.** The dev build's threshold sliders are three sets, one per
discipline, applied *after* the preset and stamped inside that preset's own staleness key —
which is how a fin threshold is argued with without re-deriving a library of wingfoil
afternoons (docs/presentation/channels-tuning.md, "Tuning").

**`windsurfFin`'s 20/15 are provisional.** They are a first guess at planing thresholds, not a
reading off a corpus — there is no fin session in one. GitHub issue #6 gates them on 5–10
windsurf sessions with ground truth; until then every windsurf reading is marked experimental
on screen (docs/presentation/labels.md, "Discipline lexicon").

**Where a session's preset comes from.** The rider's per-session override
(`session.disciplineOverride`, schema v14) first; the recording's `discipline` developer field
(docs/fit-schema.md) second; wingfoil third. **The FIT sport code is never consulted** —
ADR-004 records sport 43 (windsurfing) for a *wingfoil* session, so every
`…-windsurfen…` recording in the corpus is a wingfoil afternoon and the sport code is the one
piece of evidence here that is systematically wrong about the question. `Discipline.resolve`
does not take it as an argument, which is how that is enforced rather than promised.

A session that has never been imported has no override, so on the way *in* the ladder is the
developer field first and the rider's declared default second (Settings → "I mostly ride",
`SessionIngestor.riderDiscipline`, wingfoil unless he says otherwise) — the sport code is a
hint shown beside the question and still decides nothing. A preset that came from the default
rather than from the recording is marked as a guess (`session.disciplineGuessed`, schema v15)
and the app asks him to confirm it (docs/presentation/labels.md, "Confirming the discipline on
import"); confirming changes no number, and correcting it writes the override above.

**In the document.** `config.discipline` carries the preset's name — and only when there is
one to carry: absent, never `"wingfoil"`, the same rule the experimental 360 block follows, so
no committed golden moves for a layer that the default never reaches. `ENGINE_VERSION` is
**unchanged**: a preset is not a new engine. Staleness rides in the analysis' `engineVersion`
the way tuning's fingerprint does — `0.20.0+disc.windsurfFin`, composing inside the tuning
stamp (`0.20.0+disc.windsurfFin+tuned.2.a1b2c3d4`) — so switching one session's discipline
marks that one session stale and `reanalyzeStale()` re-derives it through the mechanism that
already existed. The comparison is per row rather than in SQL, because the version a row
*should* carry depends on that row's own preset.

**Goldens.** Two cross-check documents, `fixtures/goldens/discipline/<stem>.<preset>.expected.json`,
on the 2026-08-30 CIQ recording. They sit in a subdirectory because `test_corpus.py`,
`GoldenTests` and `make_presentation_goldens.py` all glob `goldens/*.expected.json`
non-recursively, and a preset run of a recording the corpus already holds is a *re-reading* of
it, not a nineteenth session. The **watch** knows nothing about disciplines and records
wingfoil only.

