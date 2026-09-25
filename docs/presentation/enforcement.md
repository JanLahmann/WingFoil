> Part of `docs/presentation.md`. Engine 0.25.0.

## Enforcement

1. `design/tokens.json` + generated constants + a CI staleness check (bundle_lab-style) —
   colour/glyph values cannot drift silently.
2. Presentation goldens (`fixtures/presentation/*.expected.json`): per-fixture marker counts
   per layer, filter tallies and record-window sets, asserted by BOTH the Swift
   `PresentationTests` and the web verification scripts. A count that differs between
   platforms is a failing test, not a bug report.
3. **Flight-count invariants**, in the same goldens and asserted on both platforms. Every
   flight is started by exactly one takeoff and stopped by exactly one end, so
   `takeoff.pumped + takeoff.free == flightCount` and `flightEnds.total == flightCount`,
   per fixture — with `flightEnds` partitioned into the three buckets the marker rules
   already distinguish (`drawn` + `ownedByTurn` + `truncated`). They are the arithmetic the
   pairing above depends on: a takeoff that cannot name its flight, or a flight with two
   ends, would render a wrong number in a popover long before anyone noticed a tally was
   off. `failed` attempts are deliberately outside both sums — a failed attempt is the one
   takeoff-layer mark that starts no flight.
