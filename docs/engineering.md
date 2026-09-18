# Engineering practices, audited

Issue #11. Mostly yes, and in places unusually well: the contract documents, the shared
goldens and the machine-readable copy in `docs/copy/*.json` beat most one-owner projects.
The weakness has one shape: **nearly everything that can say no is run by hand.** 490 lab
tests (2 m 29 s) and 998 Swift tests (86 s) are green today, and no machine runs them.
Every action below fits in a day.

## Findings

| Area | In place | Gap | Risk | Action |
|---|---|---|---|---|
| **CI** | `pages.yml` runs `bundle_lab.py --check`, `check_tokens.py --check` and three `verify_*.py`; `tokens.yml` guards generated tokens | No `pytest`, `swift test`, Monkey C, `verify_links.py`, `check_release_copy.py` or `check_voice.py`. Every run is a `push` on `main`; the `pull_request` triggers have never fired (the 49 merges are local) and `main` is unprotected | `deploy` ships the site on the same run that first discovers a break | `checks.yml`: `uv run pytest` on ubuntu, `swift test` on `macos-15`, plus the unrun verifiers |
| **Tests** | `fixtures/goldens/*.expected.json` cross-checked by `GoldenTests.swift` against a written tolerance table; six web verifiers; `CopyContractTests` | `ios/project.yml` declares **no test target**: 105 app Swift files (views, Strava OAuth, watch transfer) are untested. No screenshot automation; the 49 `UI_*` hooks stage screens for a human. `docs/testing.md` names `compare_speedreader.py`, which does not exist | The layer riders touch is the only layer nothing tests | Add an app test target; move `TurnAnalytics`, `FlightEndAnalytics` and the formatters under it; delete or write `compare_speedreader.py` |
| **Parity** | Lab authoritative, Swift re-derives per turn, web runs the same Python hash-pinned by `bundle_lab.py`; the 120 s / 200 m rule pinned three times | Watch parity rests on hand-written Python transcriptions (`make_autowind_arrays.py`, `watch_pump_replica.py`); nothing asserts one still matches its Monkey C original | Editing `AutoWind.mc` alone leaves a green test measuring the wrong reference | Put the `.mc` path and hash in each transcription's header; `--check` fails when it moved |
| **Version control** | `.gitignore` covers `.env`, `Strava.xcconfig`, `developer_key*`, `garmin/gen/` and footage, with reasons | `CLAUDE.md` forbids committing `Package.resolved` and `garmin/screenshots/source/ShotsApp.mc`; `git ls-files` shows both tracked. **No tags** across 643 commits. 30-odd stale `worktree-agent-*` branches | Two of four written rules are already broken, and no shipped build maps to a commit | Tag shipped versions from `garmin/store/listing.md`; correct `CLAUDE.md` (keep `Package.resolved`); untrack `ShotsApp.mc` |
| **Secrets** | A full scan finds no credential in the tree. `Strava.example.xcconfig` documents the split, the pepper generates into ignored paths (ADR-012), the ASC key lives outside the repo | `ios/tools/testflight_publish.py` hardcodes `/Users/majl/.appstoreconnect/private_keys/AuthKey_HZT9694JZ4.p8` | Only one machine can publish | Read `KEY_PATH` from the environment, defaulting to today's value |
| **Privacy** | No servers, wind estimated on device, entitlements and usage strings minimised per channel, Strava read-only with scope disclosed (ADR-023) | The corpus is unscrubbed: `fixtures/sessions/windsurf-native/*.fit` carry `serial_number 3489711811` and `user_profile` weight, height and gender. `scrub_fit.py` ran on one file only | A public repo publishes a device serial and body metrics the repo's own tool removes | Run `scrub_fit.py` over `fixtures/sessions/`, regenerate goldens, confirm no number moves; add `SECURITY.md` |
| **Release** | `package.sh` refuses to build when the three manifests disagree on version; `testflight_publish.py` encodes the beta-review lesson; channel copy pinned doc → JSON → kit → site | `CURRENT_PROJECT_VERSION` is hand-bumped at four sites in `project.yml` with no check (the watch has one), `minBuild` in `web/app/version.json` by hand, and the four release-safety checks (flags, plist, marks, `strings`) are one-liners in prose | A release binary carrying a beta-only door is caught only by remembering four greps | `ios/tools/check_release_build.py`: run `xcodegen`, the four greps, assert the four version sites agree, exit non-zero |
| **Docs / ADRs** | 25 ADRs, honest about their own weaknesses; `algorithms.md` as the numeric contract; `voice.md` and `review-checklist.md` script-enforced | No ADR carries a status: 009 superseded by 020, 016 softened by 018, 003 narrowed by 017, 012 retired, 014's device floor contradicted by `channels.md:207`. `channels.md` says engine 0.18.0, `algorithms.md` 0.19.0. `testing.md` says 17 and 21 fixtures; disk has 20 | A reader cannot tell which decision is still true | Add `Status:` and `superseded by` to every ADR head; fix the engine version and the fixture counts |
| **Pinning** | `lab/uv.lock` and `Package.resolved` committed (GRDB 7.11.1, FitFileParser 1.5.2, ZIPFoundation 0.9.20); Pyodide pinned to 0.28.3 | `package.sh` picks the newest CIQ SDK with `ls \| sort \| tail -1`, a lexicographic sort that will choose 9.2.0 over a future 10.x, and pins nothing. README says "≥ 7.4.3"; installed is 9.2.0. No Xcode version recorded, no Dependabot, no linter | The compiler that produced the shipped watch binary is unrecorded | `CIQ_SDK` with `sort -V` and an env override; record Xcode and SDK in the README; add `dependabot.yml` |
| **Monitoring** | Nothing beyond `Logger` in the watch recording path, `UsageCounters` mailed by the rider (beta only) and the divergence banner | No crash reporter, no release-channel failure signal. The known incidents (68 minutes with zero GPS fixes, the build-21 launch crash, the wedged discard dialog) all reached riders first | App Store users have no route for a crash except writing an email | Collect `MXDiagnosticPayload` into the file the feedback mail already attaches: no SDK, no server |
| **A11y / i18n** | 84 accessibility call sites in `ios/`; the watch rule that a value never degrades to a label font | Nothing tests Dynamic Type or VoiceOver, and no hook sets text size. English only: one `NSLocalizedString`, no String Catalog, and the copy contract pins one language (issue #12) | A rider at an accessibility text size gets a layout nobody has seen | Add a `UI_TEXT_SIZE` hook, shoot the five help screens at XXL; write the language policy as an ADR |
| **Reproducibility** | `uv sync && uv run pytest` works from clean; `xcodegen generate` copies the Strava template so a fresh clone builds; the kit builds with no ConnectIQ framework | README "Getting started" is three lines and names neither `xcodegen`, the three schemes nor the web verifiers. No entry point runs everything. `developer_key.der` is required and undocumented | A second machine builds some targets, not all | One `Makefile` with `check-lab`, `check-kit`, `check-web`, `check-copy`, `check-all`, linked from the README (issue #10) |

## Top ten, by risk reduction per hour

| # | Action | Why here |
|---|---|---|
| 1 | `checks.yml`: pytest, `swift test`, the remaining verifiers | ~1,500 existing tests move from honour system to enforced |
| 2 | Scrub `fixtures/sessions/` with `scrub_fit.py` | Removes a real serial and body metrics from a public repo; tool and proof already written |
| 3 | A `Makefile` and a real README "Getting started" | Makes 1 possible, closes #10, and is the only route to a second build machine |
| 4 | `check_release_build.py` for the four greps and four version sites | The highest-consequence checks are today the least automated |
| 5 | Tag every shipped version, retrospectively and onwards | Without it no shipped build can be reproduced or bisected |
| 6 | `Status:` on every ADR; fix the 0.18.0 / 0.19.0 drift | Cheap, and the decision log is load-bearing for four implementations |
| 7 | MetricKit diagnostics into the feedback mail | The only field-failure signal that keeps the no-servers stance |
| 8 | Pin the CIQ SDK; record Xcode and SDK versions | Latent: the picker silently stops upgrading at 10.x |
| 9 | Reconcile the three `CLAUDE.md` rules with what is tracked | Restores trust in a rule list read every session |
| 10 | `UI_TEXT_SIZE` hook, one Dynamic Type pass, language ADR | The only rider-facing dimension with no coverage at all |

## Deliberately not recommended

Pull-request review, coverage targets, a staging environment and a formatter are standard
practice and wrong here: one owner, and a codebase whose contract is a golden file rather
than a line count. The gap is CI and release safety, not ceremony.
