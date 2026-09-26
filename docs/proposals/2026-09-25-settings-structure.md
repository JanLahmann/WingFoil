# Settings structure — proposal (F15a/e, 25 September 2026)

Status: **approved by Jan on 26 September 2026 and built on `fb/help-settings-2`**: the
order below, one chip per section (question 4: per section, kept), the Beta footer split
onto its rows, and no footer `?` under intervals.icu. On 25 September the chips and the
concise switch were built on `fb/r4-help` and no section had moved, because no move was obviously better: today's order
already follows Jan's list (sources → watch → analysis → list → units/records → sport →
health → beta/dev → storage/backup/iCloud → about) except in two places, and both are
judgement calls.

## Built

- **Jump chips** at the top of Settings, iPhone and web: one chip per section this build
  draws, in page order. Beta/dev sections only where the channel has them.
- **How much to say** (F11), right under the chips, above everything it changes: Concise
  (default) is one line and the `?`; Extensive adds the section's own paragraphs, or the help
  topic's where a section has none. Same words as the browser app's switch.

## Order today (iPhone, dev build shows all)

1. intervals.icu · 2. Strava · 3. Deleted sessions *(only when there are any)* ·
4. Notifications · 5. Garmin watch *(dev)* · 6. Analysis · 7. Session list · 8. Row shows ·
9. Units · 10. Speed records · 11. Windsurf *(dev)* · 12. Tuning *(dev)* ·
13. Apple Health ×2 *(beta)* · 14. Beta *(beta)* · 15. Coming in a future release ·
16. Storage · 17. Library backup · 18. iCloud Drive *(dev)* · 19. About

## Proposed order, grouped

| group | sections | change |
|---|---|---|
| **Your sessions come in** | intervals.icu · Strava · Apple Health *(beta)* · Notifications | Health moves up: it is a source (import) first. Its "add to Health" switch goes with it. |
| **Your watch** | Garmin watch *(dev)* | — |
| **How it reads** | Analysis · Windsurf *(dev)* · Units · Speed records | Windsurf joins Analysis: it changes what "I mostly ride" offers, right above. Units and Speed records stay together. |
| **The list** | Session list + Row shows *(one section, two headers today)* | merge: both are "what a row shows". |
| **Your library** | Storage · Library backup · iCloud Drive *(dev)* · Deleted sessions | Deleted sessions moves down: it is about the library, and it appears only when something was deleted, so it jumps the sources today. |
| **Test builds** | Beta *(beta)* · Tuning *(dev)* · Coming in a future release | Tuning leaves Analysis for the tester block. |
| **About** | About | — |

Seven groups, and the chips could become one per group (seven chips) instead of one per
section (up to fifteen).

## Open for Jan

1. Health up with the sources, or kept after the analysis block as today?
2. Merge Session list and Row shows into one section?
3. Deleted sessions beside the backup, or under intervals.icu (it only affects that sync)?
4. Chips per section (built) or per group?
5. The Beta section's footer is six paragraphs (F15e). Split into the rows' own footers?
6. The intervals.icu section has two help buttons ("Get a key in 4 steps", "Sync not
   working?") and the `?` in its footer opens the first of them again. Drop the footer `?`?
