> Part of `docs/algorithms.md`. Engine 0.24.0.

## Flight (foil) detection — hysteresis state machine

States: `OFF_FOIL → (entry) → ON_FOIL → (exit) → OFF_FOIL`. A third derived state `PUMPING`
(off-foil + active takeoff attempt) exists for display/record `foil_state` only.

| param | default | units | notes |
|---|---|---|---|
| `foilEntrySpeed` | 12.0 | km/h | speed ≥ entry … |
| `entryHold` | 2 | s | … sustained this long ⇒ ON_FOIL (flight start backdated to first qualifying sample) |
| `foilExitSpeed` | 8.0 | km/h | speed ≤ exit … |
| `exitHold` | 3 | s | … sustained this long ⇒ OFF_FOIL (flight end backdated to first sub-exit sample) |
| `minFlightDuration` | 5 | s | shorter flights discarded (no lap, not counted) |
| `touchdownMergeGap` | 0 (off) | s | phone-only: merge flights separated by ≤ gap as one flight + touchdown event (v2) |
| `foilTimeS` · `foilPct` · `timerTimeS` | — | s, %, s | **Foil % = `foilTimeS ÷ timerTimeS`.** `foilTimeS` is the sum of the kept flights' durations; the denominator is **T2, timer time** (the clocks, below) — the session minus its pauses and gaps, *not* the elapsed span and *not* the FIT's `total_elapsed_time`. A recording that sat paused on the beach did not spend that time off the foil, and dividing by elapsed reported the corpus roughly 19 points low. The watch computes the same ratio over its own native timer (`Activity.Info.timerTime`); see the divergence list |
| `maxFlightM` | — | m | the **largest** distance any one flight covered. Deliberately not the *longest* flight's own distance: six minutes downwind and six minutes of pumping in a lull are not the same flight, and the two questions have different answers. Named `longestFlightM` before engine 0.13.0, which is what its captions claimed it was |

### The clocks — three of them, and only two are engine outputs

| # | name | key | definition | who reads it |
|---|---|---|---|---|
| **T1** | elapsed cleaned span | `summary.durationS` | last − first **cleaned** sample; **gaps included** | the duration the phone and the web *display*; the period block's "hours on the water" (`rateDurationS`); the rolling window rates' timeline |
| **T2** | timer time | `summary.timerTimeS` | Σ dt over **non-gap** steps — the session minus its pauses | **the denominator of `foilPct`, `avgSpeedKmh` and all four per-hour rates** (engine ≥ 0.13.0), a period's four included — summed, `timerTimeS` (digest schema 9, GRDB v13) |
| — | watch clocks | — | `Activity.Info.timerTime` (moving) and `Activity.Info.elapsedTime` (wall) | the watch prints its session timer and its foil % over its own timer, and its post-save summary over its own elapsed. Neither is T1 or T2 — they are the device's, measured live |

T1 is what a rider means by "how long was I out"; T2 is what a rate has to divide by, because
an hour the recorder was not running is not an hour on the water. They are kept as two named
keys rather than one blurred number, and every surface says which it is showing.

Prior art anchors: WindsportTracker wingfoil threshold ≈ 9.7 km/h; Surf Tracker run recipe
(9 km/h entry / 6 s / 13 km/h peak). Our entry is higher because takeoff pumping produces
9–12 km/h taxi speeds. User-tunable on watch (GCM settings) and phone; thresholds used are
echoed in session fields 40–42.

