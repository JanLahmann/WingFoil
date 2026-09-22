# Agent brief and report — the fixed form (22 Sep 2026)

Every agent brief the master writes follows this shape, at most 300 words, and every
report answers in the ten lines at the bottom. The point is tokens: a brief that repeats
the contract costs 100 k before the first edit, and a round that grows past one concern
compacts twice and re-reads everything.

## Brief

1. **Goal** — one sentence, the rider-visible or engine-visible outcome.
2. **Read** — the two or three files that matter, by path and section. Never "read
   algorithms.md"; name the section. CLAUDE.md is assumed.
3. **Do** — numbered steps, each one concern. A round is ONE concern; a second concern is a
   second agent, started after the first reports.
4. **Done when** — the checks that must be green, named. Default: the touched test suite with
   `--filter`; the full suite ONCE before the report; the three iOS builds only when the
   app target changed; `make all` only for an engine round.
5. **Do not** — the standing list is in CLAUDE.md "Rules"; the brief adds only what is
   specific (e.g. "no garmin/").

## Verification budget

- Watch sheets: the family the change was made for, once; the short set (six) only at the
  end of a round that changed a public page, once. Never three passes — fix from the first.
- Screenshots (iOS/web): only when the brief asks, one per surface, at the end.
- Full kit suite (1 200 tests, 8 min): once. Lab full suite: once. Goldens: once.
- Reading a PNG into the model costs ~1.5 k tokens; a 2 000-line doc ~30 k. Read the
  section, not the file.

## Model

- **Sonnet** for mechanical rounds: version bumps, copy regeneration, build pairs,
  release-note entries, listing rows, dependency pins.
- **Opus** for engine changes, layout work, anything that decides a rule.

## Report — ten lines, no prose

1. What changed (one line per surface).
2. Deviations from the brief and why (or "none").
3. Tests, verbatim counts.
4. Goldens moved (count + headline delta) or "none".
5. Commits (hashes + subjects).
6. Screenshots/sheets (paths) or "none".
7. Memory/perf numbers if the brief asked, else "—".
8. Open questions for Jan (numbered, one line each) or "none".
9. Anything you were unsure about.
10. Files you touched that a verifier pins (so the master knows what to re-run).
