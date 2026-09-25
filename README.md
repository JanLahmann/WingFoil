# CleanJibe

**Your WingFoil session, measured.**

Did you fly through that jibe? CleanJibe reads your session off the watch. It tells you your
time on the foil, every flight, your speed records, and a verdict on every turn. Flew
through, touchdown, or fell in.

*(The repository keeps its original name, `WingFoil`. The apps and the site are CleanJibe.)*

No Garmin app combines the full GPS-speedsurfing metric set with a real foil and flight
model. Nobody anywhere analyzes wing takeoff pumping. This one does both. It also fixes the
"wingfoil sessions show up as Walk" problem: it records the proper windsurf sport code with
a `discipline=wingfoil` developer field.

There are no servers. The watch writes a standard FIT. Garmin Connect and intervals.icu
carry it. The phone and the browser analyze it on the device. Wind is estimated from the
track, so no weather service is contacted either.

## Three shells

| shell | what it is | where it lives |
|---|---|---|
| **watch** | Connect IQ device app, Monkey C. Records flights, GP3S speed records, turns and takeoff pumping into a standard FIT | [Connect IQ store](https://apps.garmin.com/apps/e77867b5-e972-4eb2-be1b-90077cfac806); the open beta is on `/invite/` |
| **phone** | SwiftUI app plus `WingFoilKit`. Imports the FIT, analyzes it, keeps the library | TestFlight, [public link](https://testflight.apple.com/join/nygqGGcn). The App Store release follows |
| **web** | the analyzer at [cleanjibe.org/app/](https://cleanjibe.org/app/). Drop a file, read the session, keep a private library in the browser | cleanjibe.org, installable as a PWA and usable offline |

The site at [cleanjibe.org](https://cleanjibe.org) is the front door for all three.

## One engine, four implementations

Every threshold, clock and verdict is written down once, in **`docs/algorithms.md`**. A
number there must match in four places to the digit.

| path | what | tests |
|---|---|---|
| `lab/` | the Python engine, `wingfoil_lab`. **Authoritative.** Generates the goldens | `make lab-test` |
| `ios/WingFoilKit` | the Swift twin of the engine, plus the presentation rules | `make kit-test` |
| `web/lab_bundle` | `lab/src/wingfoil_lab` unchanged, run in the browser under Pyodide. Not a third implementation | `make web-verify` |
| `garmin/barrel` | the watch port. Ported separately, and its divergences are written down in `docs/algorithms.md` | the CIQ simulator, `garmin/tests` |

An engine change goes lab, then kit, then web bundle, in one change. The goldens are
regenerated and the engine version is bumped everywhere it is stamped.

`ios/WingFoil` is the iPhone app, the watch app and the widgets. `fixtures/` is the session
corpus, the ground truth and the golden files.

### The contracts

Read the one that covers what you are about to change. They are the source; the code is the
reading.

- **`docs/algorithms.md`** every threshold, clock and verdict, the corpus tables, the
  glossary, the watch's documented divergences
- **`docs/presentation.md`** what the rider sees and why. One wording per metric, on iOS and
  on the web
- **`docs/testing.md`** goldens, verifiers, simulator hooks, the three channels' archives
- **`docs/channels.md`** which feature is in which channel, and the four rules a feature
  meets before it moves up one
- **`docs/voice.md`** how every rider-facing sentence sounds. Three registers, ten rules
- **`docs/decisions.md`** the ADRs. **`docs/fit-schema.md`** the watch's FIT developer fields
- **`docs/review-checklist.md`** the patterns behind the product owner's feedback, A to M

## Three channels, one commit

Release, beta and dev are cut from the same commit and differ only by compile flags.
`docs/channels.md` is the single source for which feature is in which; the website, the
store texts and the app's own lists are written from it.

| channel | flags | bundle id | who |
|---|---|---|---|
| release | none | `de.lahmann.wingfoil` | App Store |
| beta | `BETA` | `de.lahmann.wingfoil` | TestFlight, public link |
| dev | `BETA DEV TUNING` | `de.lahmann.wingfoil.dev` | TestFlight, internal |

Gating happens in the app target only. The kit compiles everything. A door a channel lacks
has no UI, no document type, no usage string and no entitlement.

## Getting started on a second machine

Install the toolchain. The versions below are what the repo pins or what it is built with
today; anything newer is fine unless a file says otherwise.

| tool | version | pinned by |
|---|---|---|
| Xcode | 26.6 | `SWIFT_VERSION: "6.0"` and iOS 18.0 in `ios/project.yml` |
| XcodeGen | 2.46.0, at least 2.42.0 | `minimumXcodeGenVersion` in `ios/project.yml` |
| uv | 0.11.19 | `lab/pyproject.toml`; it makes the venv itself |
| Python | 3.12, at least 3.11 | `requires-python` in `lab/pyproject.toml` |
| Connect IQ SDK | 9.2 | `minApiLevel="3.3.3"` in `garmin/manifest.xml` |

Then run the checks. Each target is one documented command, and `make -n <target>` prints
it without running it.

```sh
make all            # lab-test, kit-test, web-verify, ios-build
make lab-test       # the authoritative engine, about a minute
make kit-test       # its Swift twin
make ios-build      # the three channels, no signing
make web-verify     # links, copy, voice, and a bundle that is not stale
make web-bundle     # regenerate web/lab_bundle after an engine change
make garmin-package # the three .iq files
```

`make all` is everything a clean checkout can run unattended. `garmin-package` is not in it
because it signs with `garmin/developer_key.der`, which is not in the repo. The watch also
needs the Connect IQ SDK and, for the simulator, VS Code with the Monkey C extension.

Three more web checks need the lab venv and the corpus. Run them from
`lab/.venv/bin/python` when the engine moves: `web/tools/verify_web_entry.py`,
`verify_library.py`, `verify_presentation.py`. `web/README.md` lists all eleven.

**Watch settings that matter:** System, then Data Recording, set to **Every Second**. The
app sets GNSS itself to All-Systems plus Multi-band.

## Contributing

Open an issue. Keep it to a line or two: this repository is public, and a long plan in an
issue is a plan on a billboard. Say what you saw, on which watch or phone, and what you
expected. A session file helps more than a screenshot.

## Licence

[Apache-2.0](LICENSE) for all code and documentation.

The CleanJibe name, wordmark and logo are trademarks and are **not** licensed for reuse.
Apache-2.0 §6 grants no trademark rights, stated here so nobody has to read §6.

The session recordings under `fixtures/` are the author's own scrubbed data, provided for
testing the engine. Raw recordings are never committed.
