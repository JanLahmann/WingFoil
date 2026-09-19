# CleanJibe / WingFoil — working notes for Claude

Four implementations of one engine, one product owner (Jan, a wingfoiler). Read these
before changing anything:

- `docs/algorithms.md` — **the contract**: every threshold, clock and verdict, the corpus
  tables, the glossary, and the watch's documented divergences. A number in the lab, the
  Swift kit, the web bundle and the watch must match this file to the digit.
- `docs/presentation.md` — what the rider sees and why: labels, tabs, maps, the turn page,
  tuning, the dev workbench. One wording per metric across iOS and web.
- `docs/testing.md` — goldens, verifiers, simulator hooks, the three channels' archives.
- `docs/channels.md` — **which feature is in which channel** (release / beta / dev), and the
  four rules a feature meets before it moves up one. The website's "what is coming" list, the
  app's Beta section and the store texts are written from it, never the other way round.
- `docs/review-checklist.md` — the patterns behind Jan's feedback (A–M); every review of a
  rider-facing surface runs it and names the pattern in its finding.
- `docs/screens.md` — **the screen inventory**: every iOS screen with its empty state, its
  doors and its channel, beside what the web and the watch do with it, plus the web's
  deliberate deviations and the target the web port builds to.
- `docs/voice.md` — **how every rider-facing sentence sounds**: three registers, ten rules,
  before/after pairs. Read it before writing or editing any text a rider sees.
- `docs/decisions.md` — ADRs. `docs/fit-schema.md` — the watch's FIT developer fields.

## Layout

| path | what | tests |
|---|---|---|
| `lab/` | Python engine, **authoritative** (`wingfoil_lab`), goldens generator | `cd lab && uv run pytest -q` |
| `ios/WingFoilKit` | Swift twin of the engine + presentation rules | `cd ios/WingFoilKit && swift test` |
| `ios/WingFoil` | the iPhone app (+ watch app, widgets); `project.yml` → `xcodegen generate` | build both schemes, see below |
| `web/` | static site; the lab runs in Pyodide from `web/lab_bundle` | `web/tools/verify_*.py`, `bundle_lab.py --check` |
| `garmin/` | Connect IQ watch app + `barrel/WingFoilCore`; the data field is **parked** (ADR-020) | `garmin/tests` in the CIQ simulator |
| `fixtures/` | sessions, goldens, footage. The **scrubbed** corpus under `fixtures/sessions` is committed on purpose — it is what every golden is derived from; raw (unscrubbed) recordings and everything under `fixtures/footage` are not | |

Engine changes go lab → kit → web bundle (and docs) in one change, goldens regenerated, the
engine version bumped everywhere it is stamped. The watch is ported separately and its
divergences are written down in algorithms.md.

## Build and ship (iOS)

```sh
cd ios && xcodegen generate
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Release" -configuration Debug \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build      # release, no flags
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Beta" -configuration "Beta Debug" \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build      # beta (BETA)
xcodebuild -project WingFoil.xcodeproj -scheme "WingFoil Dev" -configuration "Dev Debug" \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build      # dev (BETA DEV TUNING)
```

**Three channels from one commit** — `docs/channels.md` says which feature is in which, and is
the single source the website, the store texts and the app's own lists are written from.
Release (`de.lahmann.wingfoil`, App Store, no flags, iPhone, no watch app or widgets) and beta
(same bundle id, `BETA`) go to the App Store record as builds N and N+1; dev
(`de.lahmann.wingfoil.dev`, `BETA DEV TUNING`, iPhone + iPad) is a second app and goes to its
own record (`--app dev`, `CJ_DEV_APP_ID`). The App Store build takes the lowest number.
`ios/tools/testflight_publish.py <build> --group internal|external [--app release|dev] --wait`.

Gating is in the app target only — the kit compiles everything. `#if BETA` (true in dev too),
`#if DEV`, `#if TUNING` (with DEV), `#if !BETA` for the release-only "what is coming" section.
A door a channel lacks has no UI, no document type, no usage string and no entitlement; the
two checks that prove it are in docs/testing.md, "Three channels".

## Rules

- Never commit `garmin/screenshots/source/ShotsApp.mc` (a throwaway screenshot harness that
  says so in its own header), `garmin/gen/UnlockPepper.mc`, `lab/.env`, or **raw (unscrubbed)
  recordings** under `fixtures/` — the scrubbed corpus there is committed on purpose, and
  `lab/tools/scrub_fit.py` is what makes a recording committable. `.gitignore` carries all
  four with their reasons. `ios/WingFoilKit/Package.resolved` **is** committed: it pins the
  library versions a shipped build was compiled against (docs/engineering.md, "The rules
  reconciled").
- Commit path-scoped (lab / kit / ios / web / docs / garmin), lowercase narrative messages.
  Commit and push only when Jan asks. The repo is public: GitHub issues stay terse.
- One entry point: `make all` — the release check, lab, kit, the web verifiers, the three iOS
  builds. `.github/workflows/checks.yml` runs the same on every push and pull request, and the
  Pages deploy will not ship a site those checks failed. Every shipped thing gets a tag
  (`make tag-ios` / `tag-garmin` / `tag-web`); the rule is in docs/engineering.md, "Tags".
- Rider vocabulary: *flew through* (kept the foil, no touchdown, no swim), *clean* (flew
  through + held speed + the gates in algorithms.md), *dry* (did not fall in). "success"
  and "carried" are engine-internal and appear in no rider-facing text.
- Rates are additive: keep JPH and TPH beside CPH. Don't rebuild swim detection unasked.
- Simulator screenshot hooks (`UI_IMPORT_FIXTURES`, `UI_OPEN_SESSION`, `UI_OPEN_TURNS`,
  `UI_OPEN_TURN`, `UI_OPEN_FLIGHT_END`, `UI_SHEET=tuning|settings|help`, `UI_SCROLL_TO`)
  are listed in docs/testing.md; the app takes ~75 s to load in the simulator.
