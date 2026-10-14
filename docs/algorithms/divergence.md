> Part of `docs/algorithms.md`. Engine 0.28.0.

## Divergence check (phone, source class (a) only)

Banner when watch session fields vs phone recompute differ by: foil time > 5 % · any speed
record > 0.3 kn · flight/turn/attempt counts off by > 1. Divergences are tuning issues, not bugs
by definition — file them against the session fixture.

**Its scope is deliberately narrow, and this is the statement of it.** Twelve metrics are
compared: foil time, six speed records (2 s, 10 s, 5×10 s, 500 m, NM, alpha 500 — of which the
watch only ever supplies the first two, see "Speed records"), flights, tacks, jibes, takeoff
attempts and takeoff successes. Nothing compares **clean jibes**, the streaks, the outcome
tallies, the wind axis, foil *percentage*, or `total_pump_strokes` — the last of which the
watch's own divergence list says *will* differ on installed watches. The check exists to
catch a *recording* fault (a channel the watch and the phone read differently), not to police
metrics whose divergences are already enumerated and intended above; adding clean jibes would
mean picking a threshold for a metric whose watch-side evidence is documented as coarser.
**Takeoff attempts are compared only when the file carries the accelerometer** (rider feedback,
13 Oct 2026). Without it the phone cannot see a failed takeoff and counts flights alone, so a
beta watch — which logs no raw accel — would always show its failed efforts as a disagreement
("watch 31, phone 19"). The phone's `total_pump_strokes` is `None` exactly then, and that is
the test; flights and takeoff successes are still compared.
The foil-time comparison is of the **seconds**, not the percentage, which matters because the
two sides normalise that percentage by different clocks (see the watch divergence list).

---

