# Channels — release, beta, dev

**Status:** decided with Jan on 14 September 2026 from the "Release 1 Scope" review. This file
is the single source for which feature ships in which channel; the website's "what is
coming" list, the app's Beta section and the store texts are written from it, never the
other way round.

## The three channels

| channel | how it is built | who gets it | version |
|---|---|---|---|
| **release** | scheme `WingFoil Release`, no compile flags, iPhone only, bundle id `de.lahmann.wingfoil`, no watch app and no widget extension embedded | App Store | 1.0.x |
| **beta** | scheme `WingFoil Beta`, `BETA` defined, iPhone only, same bundle id, watch app and widgets embedded | TestFlight, public link | 1.1.0 |
| **dev** | scheme `WingFoil Dev`, `BETA DEV TUNING` defined, iPhone and iPad, its own bundle id `de.lahmann.wingfoil.dev` (widgets `.dev.widgets`, watch `.dev.watchkitapp`, complication `.dev.watchkitapp.widgets`), display name "CleanJibe Dev" | TestFlight, internal group, a handful of hand-picked testers | 1.1.0 |

Release and beta share a bundle id, so a phone holds one of them; TestFlight swaps them in
place with the library kept. Dev is a second app beside either. All three are cut from the
same commit and differ only by flags, so the library schema is identical and switching is
safe; a build that meets a newer schema says so and offers a restore from backup instead of
failing to open.

Gates in code: `#if BETA` for beta rows (also true in dev), `#if DEV` for dev rows (also
`TUNING` for the tuning page, which predates this file). The kit compiles everything; gating
happens in the app, its Info.plist and its entitlements, so a gated door has no UI, no
document type, no usage string and no entitlement in the channels that lack it.

## Four rules for "proven"

1. On the water in ten or more sessions by two or more riders without an open report. Jan's
   own fenix and iPhone count as one rider.
2. Third parties are prerequisites, not features: Strava's application review clears the
   one-rider cap before the release ships; Garmin Connect Mobile owns the Bluetooth link and
   stays in dev until the link has real sessions behind it.
3. Older than a fortnight. Strava is the one exception, by Jan's call.
4. Reviewable without a watch: every release feature shows itself from the example session
   or a shared file.

A feature moves up a channel when it meets rule 1, has a help topic, is covered by the
privacy page and has no open report.

## What you need, what you get — the three recording classes

| class | you record with | you get | you do not get |
|---|---|---|---|
| a | the CleanJibe watch app on a Garmin | everything: foil time, flights, every turn verdict and clean jibe, certified speed records, wind axis, pump strokes and takeoff attempts | nothing missing |
| b | any other FIT with a Doppler speed channel (Garmin's Windsurf profile, another Connect IQ app, the CleanJibe Apple Watch app) | foil time, flights, turn verdicts and clean jibes, **certified** speed records, wind axis | pump strokes and takeoff attempts, shown as absent, never as zero |
| c | positions only (Strava, a GPX, a TCX without speed, a phone in a pocket) | foil time, flights, turn verdicts and clean jibes, wind axis, speed records **estimated from positions** and marked uncertified | certified records, pumps, takeoffs |

Release: classes a and b through intervals.icu or a file, class c through Strava. Beta: class
c through GPX and TCX as well. The app's `sourceClass` column is the source of truth
(docs/algorithms.md).

## Feature by channel

### Getting a session in

| feature | channel | note |
|---|---|---|
| intervals.icu sync, pull to refresh, background check with notification | release | |
| FIT from Files, Mail, AirDrop, the share sheet | release | |
| Strava import | release | testers Jan and Robert; needs Strava's application review first |
| GPX and TCX imports (Polar, Suunto, COROS route) | beta | in the beta from day one; the release text says "the beta reads their files" |
| Garmin export ZIP (full history) | beta | until a rider asks for it |
| Apple Health, read Apple Workout recordings | beta | unproven; off until switched on |
| Apple Health, write sessions as workouts | beta | unproven; the release has no HealthKit entitlement |
| Discipline review after import ("Which rig?") | dev | part of windsurf |

### The analysis

| feature | channel | note |
|---|---|---|
| Engine 0.18.0: foil time, flights, touchdowns, falls, wind axis | release | |
| Turn verdicts, clean jibes, JPH · CPH · WPH, dry streaks | release | |
| GP3S record set, uncertified marking | release | |
| Pump strokes, takeoff attempts | release | class a only; absence shown as absence |
| Turn page and flight-end page with the three strips | release | |
| "Wrist under" layer, why-line on every touchdown | release | |
| Windsurf discipline (foil, fin), per-discipline thresholds | dev | experimental |
| Tuning page, sliders, turn workbench, tuned chips | dev | listed as a potential beta feature on request |

### The library

| feature | channel | note |
|---|---|---|
| Session list, detail page, four tabs | release | |
| Group by month, year, spot; filter menu; chips | beta | |
| Spots, gear, periods | release | |
| Records, trends, all-time tables | release | |
| Backup and restore, deleted-session memory | release | |
| Example session, welcome screen, help catalogue | release | |

### Maps and sharing

| feature | channel | note |
|---|---|---|
| Session map, full-screen map, layers, map styles | release | |
| Replay with commentary, scrub and zoom | release | |
| Share card (session, period), QR back to the site | release | QR to grow to ~144 px |
| Replay clips with the rider's own music | release | |
| Session video export (the film) | beta | |
| Send a session to a friend, sessions someone else rode | release | the scrubbed original FIT through the share sheet |

### Watches

| feature | channel | note |
|---|---|---|
| Apple Watch app: recording, live numbers, transfer to the phone | beta | in the beta from day one; release once Jan's daughters' sessions arrive by themselves |
| Home-screen widgets (last session, this week) and the watch complication | beta | need the app group before they show anything |
| Garmin link: summary card from the watch | dev | |
| Garmin link: send wind to watch | dev | potential feature on request only |
| Garmin link: map to watch, spot picker, "Where I am now" | dev | the only location prompt in the app |
| Companion UUID probing (three watch builds) | dev | |

### Feedback and channel furniture

| feature | channel | note |
|---|---|---|
| Feedback mail with prefilled facts, footers on every page, menu Support | release | |
| "Curious about what is coming" section with the TestFlight link and this list | release | the beta shows the list without the link |
| Beta section: feature list, request a feature, extended feedback mail with usage and feature statistics | beta | counters kept on the phone, sent only in a mail the rider edits |
| Start screen, library menu order, Getting started topic | release | |

### Platforms

| feature | channel | note |
|---|---|---|
| iPad and "Designed for iPad" on the Mac | dev | release and beta build for iPhone only |

## Before the release is submitted

1. Strava's application review, requested with the release description and the privacy page.
2. The `BETA` and `DEV` flags and the gating above; the release build contains no GPX/TCX
   door, Garmin link, Health, video export, grouping, windsurf or location code and builds for
   iPhone only; its share sheet declares only the FIT type.
3. The dev bundle ids, their App Store Connect record and profiles, URL schemes and display name.
4. The Connect IQ release listing on app id `b1ef484c` only when the link graduates; the
   companion app URL on the Connect IQ listings once the App Store listing is live.
5. The App Store record: privacy labels, support and privacy URLs, age rating, category,
   screenshots for three iPhone sizes, review notes (example session, an attached FIT, no
   account).
6. The website's release state: the download button to the App Store, the TestFlight link
   under "Curious about what is coming", iPad off the product copy, a Release column on
   /whats-new.
