# WingFoil

Wingfoil tracking for Garmin Fenix 8 + iPhone: a Connect IQ watch app that records
wingfoil-native metrics (flights, GP3S speed records, turns, takeoff pumping) into standard FIT
activities, and an iOS app that imports and deeply analyzes them.

**The pitch:** no Garmin app combines the full GPS-speedsurfing metric set with a real
foil/flight model — and nobody anywhere analyzes wing takeoff pumping. This one does both, and
fixes the "wingfoil sessions show up as Walk" problem by recording the proper windsurf sport
code with a `discipline=wingfoil` developer field.

| Part | What it is |
|---|---|
| `garmin/` | Connect IQ device app (Monkey C, Fenix 8, minApiLevel 5.0.0) |
| `ios/` | SwiftUI app + `WingFoilKit` Swift package (FIT import, analysis engine, GRDB) |
| `lab/` | Python playground where detection algorithms are tuned on real sessions |
| `fixtures/` | Session corpus + ground truth + golden files (the testing contract) |
| `docs/` | The contracts: `plan.md` · `fit-schema.md` · `algorithms.md` · `testing.md` · `decisions.md` |

Data pipeline (no servers): watch FIT → Garmin Connect → intervals.icu → iOS app pulls the
original FIT via personal API key. Backfill via Garmin GDPR export. Wind via Open-Meteo
(CC-BY 4.0, https://open-meteo.com/).

## Getting started

- **Lab:** `cd lab && uv sync && uv run pytest`
- **iOS:** `cd ios/WingFoilKit && swift test`
- **Garmin:** VS Code + Monkey C extension + CIQ SDK ≥ 7.4.3; build target `fenix847mm`;
  sideload the `.prg` to `GARMIN/APPS/` (macOS: use OpenMTP, quit Garmin Express first)
- **Watch settings that matter:** System → Data Recording = **Every Second**; GNSS is set by the
  app (All-Systems + Multi-band)
