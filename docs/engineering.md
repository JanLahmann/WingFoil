# Engineering practices, audited

Issue #11. Mostly yes, and in places unusually well: the contract documents, the shared
goldens and the machine-readable copy in `docs/copy/*.json` beat most one-owner projects.
The weakness has one shape: **nearly everything that can say no is run by hand.** 490 lab
tests (2 m 29 s) and 998 Swift tests (86 s) are green today, and no machine runs them.
Every action below fits in a day.

**What has been done since** is at the foot of this file, "Acted on, 19 Sep 2026": items 1, 4,
5, 6 and 9 of the top ten, which are the ones that touch no product code. The findings table
below is the audit as it was written and is left that way on purpose — a finding edited into
agreement with the fix is no longer evidence that the fix was needed.

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
| **Pinning** | `lab/uv.lock` and `Package.resolved` committed (GRDB 7.11.1, FitFileParser at commit `6f50aa1`, ZIPFoundation 0.9.20); Pyodide pinned to 0.28.3 | `package.sh` picks the newest CIQ SDK with `ls \| sort \| tail -1`, a lexicographic sort that will choose 9.2.0 over a future 10.x, and pins nothing. README says "≥ 7.4.3"; installed is 9.2.0. No Xcode version recorded, no Dependabot, no linter | The compiler that produced the shipped watch binary is unrecorded | `CIQ_SDK` with `sort -V` and an env override; record Xcode and SDK in the README; add `dependabot.yml` |
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

---

# Acted on, 19 Sep 2026

Top-ten items 1, 4, 5, 6 and 9 — everything that touches no product code. Items 2 (scrub the
corpus), 3 (the README's "Getting started"; the `Makefile` itself is written), 7 (MetricKit),
8 (the CIQ SDK pin) and 10 (Dynamic Type) are still open.

## What CI runs — `.github/workflows/checks.yml`

On every push and every pull request, four jobs, each named so a red one is a finding rather
than a search:

| job | runner | what | roughly |
|---|---|---|---|
| `lab` | `ubuntu-latest` | `uv sync --locked` + `uv run pytest -q` in `lab/` | 3 min |
| `kit` | `macos-26`, Xcode 26.6 | `swift test` in `ios/WingFoilKit` | 4 min |
| `web` | `ubuntu-latest` | `verify_links.py` (which drives `verify_copy`, `verify_app_shell`, `verify_unique`, `check_voice` and `check_duplicates` in process), then `check_voice.py`, `check_duplicates.py`, `check_release_copy.py` and `bundle_lab.py --check` by name | 1 min |
| `repo` | `ubuntu-latest` | `tools/check_release.py` and `make -n all` | seconds |

uv is pinned to `0.11.19` — the version that wrote `lab/uv.lock`, because a lock file is only
a pin if the resolver reading it is one too — Python to 3.12, and the uv cache is keyed on
`lab/uv.lock`. `--locked` rather than a bare `uv sync`: it fails when `pyproject.toml` has
moved and the lock has not, instead of quietly repairing the drift in CI and nowhere else.

The **Xcode pin is soft**: the job selects `Xcode_26.0.app` when the runner image has it (the
kit is built locally with Xcode 26.6 / Swift 6.3 under `SWIFT_VERSION: "6.0"` and strict
concurrency, so the toolchain is load-bearing) and otherwise carries on with the image default
and prints a `::warning::` naming the pin and what was installed. A hard pin to an image that
has not shipped that Xcode yet is a red build for a reason that has nothing to do with the
code; the warning makes the drift visible and one line fixes it.

**The macOS runner is the only cost.** GitHub bills macOS minutes at 10× the Linux rate and
counts them against a much smaller free allowance — but that is for *private* repositories,
and this one is public, where standard runners are free with no minute cap. What a public repo
does pay is concurrency: macOS jobs queue against a per-account limit of five, so a burst of
pushes serialises. If the repo is ever made private, the `kit` job is the line to look at
first — roughly 4 min × 10 = 40 billable minutes per run against the 2,000-minute free tier.

**The Pages deploy** (`pages.yml`) is unchanged except for one added job: `gate`, which calls
`checks.yml` as a reusable workflow, and `deploy` now `needs: [check, gate]`. So the site
cannot ship on the run that first discovers a break — the audit's headline risk.

`needs:` and not a `workflow_run` trigger, deliberately. `workflow_run` would fire the deploy
after Checks finished on `main`, which loses this workflow's `paths:` filter (Checks runs on
every push, so a docs-only commit would redeploy the site), checks out the branch head rather
than the pushed commit, and splits one ship across two runs. Calling the workflow keeps
deploy-on-push exactly as it was, in one run that reads top to bottom. The gate passes
`deploy-gate: true`, which skips the `kit` job: `swift test` gates nothing the site ships, and
running the only paid-rate runner twice per web push buys no answer. The kit still runs on the
same push, in Checks' own run.

## Branch protection — one command, Jan's to run

Not run from here. It needs admin on the repository, and turning on a rule that can block a
release is the owner's click.

```sh
gh api -X PUT repos/JanLahmann/WingFoil/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -F "required_status_checks[strict]=true" \
  -f "required_status_checks[checks][][context]=lab — pytest" \
  -f "required_status_checks[checks][][context]=kit — swift test" \
  -f "required_status_checks[checks][][context]=web — verifiers and copy" \
  -f "required_status_checks[checks][][context]=repo — release check and the Makefile" \
  -F "enforce_admins=false" \
  -F "required_pull_request_reviews=null" \
  -F "restrictions=null" \
  -F "allow_force_pushes=false" \
  -F "allow_deletions=false" \
  -F "required_conversation_resolution=false" \
  -F "required_linear_history=false"
```

The four checks must pass, `main` cannot be force-pushed or deleted, and **no review is
required** — `required_pull_request_reviews=null` keeps the one-owner habit of pushing
straight to `main` that this audit's own "Deliberately not recommended" defends.
`enforce_admins` is **false** on purpose: it is the owner's bypass, for the release that has
to go out while a runner is queued. Undo the whole rule with
`gh api -X DELETE repos/JanLahmann/WingFoil/branches/main/protection`.

The four context names are the jobs' `name:` values in `checks.yml`. Rename a job and this
command has to be re-run, or the rule waits for a check that never reports.

## Tags — one per shipped thing

643 commits and no tag, so no shipped build maps to a commit and nothing can be bisected
against a rider's report. The rule, from now on and retrospectively:

| what shipped | tag | read from |
|---|---|---|
| an iPhone build uploaded to App Store Connect | `ios/<marketing>-<build>`, e.g. `ios/0.15.0-77` | `ios/project.yml` |
| a watch `.iq` uploaded to a Connect IQ listing | `garmin/<version>`, e.g. `garmin/0.9.13` | `garmin/manifest.xml` |
| a site deploy that bumped the service worker | `web/v<NN>`, e.g. `web/v76` | `web/sw.js` |

Annotated tags, created at the commit that produced the upload, never typed by hand:

```sh
make tag-ios                 # ios/<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>
make tag-ios VERSION=1.0.0   # …for a release-channel upload, whose line is its own
make tag-garmin              # garmin/<manifest version>
make tag-web                 # web/<sw.js VERSION>
git push origin <tag>        # Jan's, like every other push here
```

Each target **refuses on a dirty tree**, and the two that name a shipped binary run
`tools/check_release.py` first: a tag on a commit that is not what was uploaded is worse than
no tag, because it will be believed. Dev-only uploads (`0.9.14-dev1`, the private listing) get
no tag — they are not a shipped thing.

### The tags that should exist today

Recovered from `garmin/store/listing.md` (version history), `docs/copy/whats-new.json` (every
iPhone build with release notes) and `web/sw.js` (the service worker's version line). **Not
created from here** — a retrospective tag is a claim about which commit was uploaded, and for
a row whose commit column says "—" the only person who can confirm that is Jan.

**iPhone** — thirteen builds, all on the 0.15.0 line (the release channel's 1.0.0 has not
shipped yet), newest first:

```
ios/0.15.0-77  ios/0.15.0-76  ios/0.15.0-75  ios/0.15.0-74  ios/0.15.0-73
ios/0.15.0-72  ios/0.15.0-53  ios/0.15.0-51  ios/0.15.0-49  ios/0.15.0-47
ios/0.15.0-45  ios/0.15.0-43  ios/0.15.0-41
```

**Watch** — seventeen store versions. Nine carry a commit in `listing.md` and can be tagged
without asking anyone; the rest need Jan to name the commit.

```
with a commit:  garmin/0.9.7 347669a   garmin/0.9.6 459ae1d   garmin/0.9.3 16568d5
                garmin/0.9.2 2b3bc66   garmin/0.9.1 b891e08   garmin/0.9.0 e2cadfe
                garmin/0.8.2 3ccec57   garmin/0.8.1 6619d4f   garmin/0.8.0 5678a2f
commit unknown: garmin/0.9.13  garmin/0.9.12  garmin/0.9.11  garmin/0.9.10
                garmin/0.9.9   garmin/0.9.8   garmin/0.9.5   garmin/0.9.4
```

The data field's four store versions (`0.9.5`, `0.9.4` `8d014dc`, `0.9.3` `442ffbe` and
`0.1.0` `cc64066`) are dormant per ADR-020 and get `garmin/field/<version>` if they are tagged
at all.

**Site** — one tag today, `web/v76`, at the commit that set `const VERSION = "v76"` in
`web/sw.js`. The earlier versions are recoverable from that line's history with `git log -S`,
and are worth tagging only as far back as anyone would bisect.

## Building 1.0.1 release from its tag

The point of a tag is that this needs no memory of which commit was uploaded — the tag says
so. What a store archive adds on top of `make ios-build` (which proves the code compiles,
signing off) is real signing and the one fact `docs/channels.md` states as a rule:
**release and beta share one App Store Connect record and go up as two builds of the same
1.0.1, and the App Store build takes the lower number of the pair.** Reproducing "the 1.0.1
release" means reproducing *that specific build*, not just any build compiled from the
release scheme.

1. **Find the tag.** `git tag -l 'ios/1.0.1-*'` lists every 1.0.1 upload; the release one is
   the **lowest build number** of the pair for that version (`ios/1.0.1-111` before
   `ios/1.0.1-112`, if 112 is the beta that shipped alongside it) — never assume which one
   without checking `ios/project.yml` at the tag, since the same number briefly sits on every
   target before the two are told apart at archive time.
2. **Check out that tag**, on a clean tree (a worktree, so the working checkout is
   untouched): `git worktree add /tmp/release-1.0.1 ios/1.0.1-111`.
3. **Regenerate the project and confirm the tag's own claim**: `cd ios && xcodegen generate`,
   then `python3 ../tools/check_release.py` — the same check `tag-ios` ran before creating
   the tag, run again here to prove the checkout matches what was promised, not only what was
   pushed.
4. **Archive the Release scheme, signed this time** (the `make ios-build` recipe turns
   signing off on purpose, to prove compilation without needing the team's profiles present):
   ```sh
   xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" -configuration Release \
     -archivePath build/WingFoil-1.0.1-111.xcarchive -destination 'generic/platform=iOS' \
     archive
   ```
   This needs the signing team and provisioning profile Xcode already has configured
   (`CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: 685X8YLYSB`) — the one part of this that
   cannot run unattended or in CI.
5. **Prove the archive is what the tag claims before exporting it**: run the release check a
   third time against the executable inside the archive, which is the same binary App Review
   will see —
   `python3 tools/check_release.py --binary build/WingFoil-1.0.1-111.xcarchive/Products/Applications/WingFoil.app/WingFoil`
   — flags, plist, marks and the two door strings, against the actual signed output rather
   than against source.
6. **Export and upload** through Xcode Organizer (Distribute App → App Store Connect →
   Upload), or `xcodebuild -exportArchive` with an export-options plist naming
   `app-store-connect` — either way the build lands in App Store Connect as build 111 on
   `de.lahmann.wingfoil`, version 1.0.1, in Processing.
7. **Attach it and, for the beta upload, submit it** with
   `ios/tools/testflight_publish.py 111 --group internal --app release --wait` for the
   internal group (no review needed), and the external run once it has processed. The release
   channel itself is never "submitted" through this script — App Review for the release comes
   from the App Store submission in App Store Connect's own UI, which is Jan's click
   (`docs/release/jans-block.md`); this script's `--group external --app release` submits the
   **beta** build 112 for beta review, the parallel upload from the same tree at
   `ios/1.0.1-112`.
8. **The pair, side by side.** Steps 2–7 repeat once more for `ios/1.0.1-112` (`WingFoil Beta`
   scheme, `Beta Release` configuration) to produce the build TestFlight testers get. Two
   archives, one version, two build numbers, and the rule that made the tag worth having:
   whichever of the two is lower is the one App Review sees as "the app," because App Store
   Connect always offers reviewers the lowest build number of a version that has more than
   one — the reason `WingFoilRelease` carries no `MARKETING_VERSION` of its own and a stray
   `"1.0.0"` there once shipped 1.0.1 as 1.0.0 again (`docs/release/round-a-findings.md`,
   F-1).

None of this was run from here — no tag was created, no archive was signed, nothing was
uploaded (out of scope for this round, and archiving needs the signing team present on this
machine). What was run: `make ios-project` then a Debug-configuration, unsigned build of the
Release scheme (`docs/support.md`'s companion confirmation, step 1) and a second one at
`-configuration Release` to read the actual signed-shape binary's strings, both against this
branch's tree — the same two builds `tools/check_release.py --binary` above describes,
proving the recipe against real output rather than only against the doc.

## The release check — `tools/check_release.py`

`make release-check`, first in `make all` and a job in CI. Stdlib only, instant. It holds the
version sites together and turns docs/testing.md's four channel greps into code:

- **iOS** — `CURRENT_PROJECT_VERSION` identical at every site in `ios/project.yml`, and one
  `MARKETING_VERSION` at every target, the release included (one version across the three
  channels; the release is the lowest build of it).
- **Watch** — one version across `manifest.xml`, `manifest-beta.xml` and `manifest-dev.xml`
  (the same rule `package.sh` enforces at build time, said before the build).
- **Engine** — `lab/src/wingfoil_lab/__init__.py`, the web bundle's copy, the kit's
  `AnalysisEngine.version`, `docs/algorithms.md`'s head and `docs/channels.md`'s analysis
  table, all equal.
- **Flags** — the release target defines no `SWIFT_ACTIVE_COMPILATION_CONDITIONS`; the beta
  configurations say `BETA`, the dev ones `BETA DEV TUNING`.
- **Plist** — no `NSHealth` / `NSLocation` / `NSBluetooth` / `gpx` / `tcx` in the generated
  `WingFoil/Info-Release.plist` (skipped, with a note, until `make ios-project` has run).
- **Marks** — the release inherits `AppIcon` / `SplashMark`, beta takes `-Beta`, dev `-Dev`.
- **Strings** — with `--binary <path>`, the two door strings docs/testing.md pins
  (`version.json`, "Sync the library with iCloud Drive") must be absent from a release
  binary. Without it, the source-side stand-in: no `#if BETA|DEV|TUNING` anywhere in
  `WingFoilKit`, because the kit compiles everything in every channel (CLAUDE.md) and a gate
  there would be a door the release cannot be trusted to lack.

It found one thing on the tree it was written against: `docs/channels.md` said engine 0.18.0
where every other site said 0.20.0. Fixed.

## The rules reconciled — CLAUDE.md

Two of the four "never commit" rules were already broken, which is the worst state for a list
read at the start of every session. One decision per file:

- **`ios/WingFoilKit/Package.resolved` — the rule was wrong, and is gone.** This is an
  application repository, not a library: the resolved file is what pins GRDB 7.11.1,
  FitFileParser (commit `6f50aa1`) and ZIPFoundation 0.9.20 to the versions the shipped
  builds were compiled against, and this audit's own Pinning row credits it as committed. The rule said
  never; the tree said always; the tree was right.
- **`garmin/screenshots/source/ShotsApp.mc` — the rule was right, so the file is untracked.**
  Its own header says "THROWAWAY screenshot harness. Not shipped, not committed, not
  referenced by any build." `git rm --cached`, and `.gitignore` now carries the path with the
  reason, so it cannot come back by accident. The file stays on disk.
- **"Raw FITs are never committed" — reworded, because the scrubbed corpus is committed on
  purpose.** `fixtures/sessions/` is in the tree and is what every golden is derived from;
  what must never be committed is an *unscrubbed* recording (`lab/tools/scrub_fit.py` is the
  tool, top-ten item 2 is the work still outstanding) and the footage, which is gigabytes and
  is already ignored path by path.

## ADR statuses

All 26 ADRs now open with a `Status:` line and `docs/decisions.md`'s head says what the four
words mean. Read out of the prose, not decided afresh: **ADR-009** superseded by ADR-020,
**ADR-012** retired (the lock has been off since 0.9.11), **ADR-016** narrowed by ADR-018,
**ADR-003** narrowed by ADR-017 and extended by ADR-023, **ADR-014**'s device list overtaken
by `docs/channels.md` "Devices", **ADR-011** accepted and since carried out (the app group is
in `project.yml` for the beta channel), **ADR-026** already carried "Proposed", and the
remaining nineteen Accepted.

## Two corrections to the audit itself

- The **Tests** row says `ios/project.yml` declares no test target. It does now:
  `WingFoilTests`, Debug-only, hosted by the beta app target. The row's point survives only
  for the screenshot automation.
- The **Tests** row's `compare_speedreader.py` is removed from `docs/testing.md` rather than
  written: it was planned in `docs/plan.md`, `fixtures/speedreader/` is empty, and the GP3S
  rules are held by the goldens and `verify_presentation.py`. What remains is a gap in
  cross-validation against a second implementation, and `docs/testing.md` now says that
  instead of naming a file that does not exist.

## The security half

The **Secrets** and **Privacy** rows above are one paragraph each because this audit was
about practices. The threat model they imply — what is worth protecting, where the trust
boundaries are, who the adversaries actually are for a hobby app with a public repo and no
server, and every open finding with a severity and an effort — is **`docs/security.md`**,
written 20 September 2026. Read that one before touching a parser, the keychain, the
Strava flow or a workflow's `permissions:` block.

## Still open, in the audit's order

2. Scrub `fixtures/sessions/` with `scrub_fit.py`, regenerate goldens, add `SECURITY.md`.
3. A real README "Getting started" pointing at the `Makefile`.
7. MetricKit diagnostics into the feedback mail.
8. Pin the CIQ SDK. The line in `garmin/tools/package.sh` is the maintainer's to change:
   `SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/$(ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" | sort | tail -1)/bin"`
   becomes
   `SDK="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/${CIQ_SDK:-$(ls "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" | sort -V | tail -1)}/bin"`
   — `sort -V` so a future 10.x is not sorted below 9.2.0, and `CIQ_SDK` in the environment to
   pin the compiler that produced a shipped `.iq`. Record the chosen SDK and the Xcode version
   in the README.
10. A `UI_TEXT_SIZE` hook, one Dynamic Type pass, and the language policy as an ADR.
