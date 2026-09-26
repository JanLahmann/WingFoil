# Channels — release, beta, dev

**Status:** decided with Jan on 14 September 2026 from the "Release 1 Scope" review. This file
is the single source for which feature ships in which channel; the website's "what is
coming" list, the app's Beta section and the store texts are written from it, never the
other way round.

**Its machine-readable twin is `docs/copy/channels.json`** — the same beta and dev rows, the
same section title, in a form a test and a Python verifier can read. `ChannelFeatures` in the
kit is asserted equal to it by `CopyContractTests`, the website's two lists by the web
verifier, and `docs/copy/check_release_copy.py` asserts that no release copy names a door the
release lacks. Edit this file first, then the JSON and the kit together.

## The three channels

| channel | how it is built | who gets it | version |
|---|---|---|---|
| **release** | scheme `WingFoil Release`, no compile flags, iPhone only, bundle id `de.lahmann.wingfoil`, no watch app and no widget extension embedded | App Store | 1.0.x |
| **beta** | scheme `WingFoil Beta`, `BETA` defined, iPhone only, same bundle id, watch app and widgets embedded | TestFlight, public link | 1.1.0 |
| **dev** | scheme `WingFoil Dev`, `BETA DEV TUNING` defined, iPhone and iPad, its own bundle id `de.lahmann.wingfoil.dev` (widgets `.dev.widgets`, watch `.dev.watchkitapp`, complication `.dev.watchkitapp.widgets`), display name "CleanJibe Dev" | TestFlight, internal group, a handful of hand-picked testers | 1.1.0 |

### Switching channels

Release and beta share a bundle id, so a phone holds one of them; TestFlight swaps them in
place with the library kept. Dev is a second app beside either. All three are cut from the
same commit and differ only by flags, so the library schema is identical and switching is
safe; a build that meets a newer schema says so and offers a restore from backup instead of
failing to open. What is *not* identical is when each was cut — an older App Store build put
back on a phone a newer beta has already migrated is the real case — so `AppDatabase` checks
`PRAGMA user_version` and the applied migration list before it migrates anything and throws
`LibraryNewerThanApp`, which `RootView` turns into one full screen with *Open TestFlight* and
*Restore from backup* on it; docs/testing.md says how to raise that screen in the simulator
with one `sqlite3` line.

Gates in code: `#if BETA` for beta rows (also true in dev), `#if DEV` for dev rows (also
`TUNING` for the tuning page, which predates this file). The kit compiles everything; gating
happens in the app, its Info.plist and its entitlements, so a gated door has no UI, no
document type, no usage string and no entitlement in the channels that lack it.

**Help topics are channel-bound too, and the kit does not gate them — it is told.** The
catalogue is pure data in `WingFoilKit/Help/HelpCatalog.swift` and compiles whole in every
build, so a topic about a door a channel lacks would otherwise sit on that channel's Help
index describing a screen the rider cannot reach. Every `HelpTopic` therefore carries a
`channel: HelpChannel` — the *lowest* channel that has the door it explains, `.release` by
default and for almost every topic — and the app hands its own channel in
(`ChannelFeatures.channel`, the one `#if DEV` / `#elseif BETA` / `#else` in the app that the
kit reads). `HelpCatalog.indexTopics(channel:windsurfEnabled:)` is what the index lists and
what its search may match, and `HelpCatalog.relatedTopics(of:channel:)` is what a topic's
"see also" may render, so a visible page can never offer a button onto a hidden one. What is
*not* filtered is `HelpCatalog.topic(_:)`: it stays total, so a `?` on a card the build does
draw always opens and a deep link written down in a mail keeps working. Bound today:
*Recording with the Apple Workout app* (beta, the Health door) and *Windsurf (experimental)*
(dev, and also behind its own switch). Two kit tests hold the line — no beta or dev topic on
the release index, and no visible topic linking at a hidden one.

Where one sentence has to serve two channels, the release wording names the beta as the place
a door is rather than pretending the door is here: *"GPX and TCX files are read by the
CleanJibe beta; a FIT is read by every build."* That is the same rule the import footer
follows, and the only place the release is allowed to mention a channel at all — beside
Settings → "Coming in a future release", which is the app naming its missing doors on purpose.

## Four rules for "proven"

1. On the water in ten or more sessions by two or more riders without an open report. Jan's
   own fenix and iPhone count as one rider.
2. Third parties are prerequisites, not features: Strava allows ten connected riders since the
   14 September self-service upgrade. Its Developer Program review lifts that cap, but Strava
   only reviews apps that have *reached* the ten (the form says applications below the
   threshold are denied; checked 14 September, one rider connected), so the release ships at
   the cap and the form goes in the day the tenth rider connects — see "The Strava review"
   below. Garmin Connect Mobile owns the Bluetooth link and stays in dev until the link has
   real sessions behind it.
3. Older than a fortnight. Strava is the one exception, by Jan's call.
4. Reviewable without a watch: every release feature shows itself from the example session
   or a shared file.

A feature moves up a channel when it meets rule 1, has a help topic, is covered by the
privacy page and has no open report.

### The release gate: used successfully, on two phones

Jan's rule (24 September 2026, F16): **no feature enters the release before testers have used
it successfully.** The usage report is how that is proven, not a hunch. A beta feature moves
to the release when, across the usage reports in the mailbox,

- its row shows **at least N successes (✓) on at least two testers' devices** — two different
  device lines at the top of the counters, and Jan's own iPhone and iPad count as one tester,
  as in rule 1;
- **no failure is open** — on every phone that reported it, the newest outcome is a success
  (`UsageCounters.Tally.failureIsOpen` is false), so a ✗ after the last ✓ holds the feature
  back until a later report shows it working again;
- and it meets rules 1 to 4 above.

**N = 5 is a placeholder** (flagged for Jan): the number is a decision, and 5 was chosen as
the smallest count that is more than a first try. Until it is confirmed, a move-up names the
counts it relied on in the commit message. A feature with no row in the table below cannot
pass this gate, which is the point: a door the report does not count is a door nobody has
shown to work.

## What the usage report counts

One row per feature, generated from `UsageCounters.Feature` (`UsageFeatures.swift` in the kit)
by `COPY_WRITE=1 swift test --filter UsageCountersTests` and checked by the same suite, so the
report and this file cannot disagree. Each row counts tries, successes (✓) and failures (✗),
the date of the last of each, and the last failure's reason — a short code such as
`NSURLErrorDomain -1009` or an error's type and case, never a file name, a spot or a
sentence. "Lowest channel" is the first build that has the door; the report names a door as
*Not used yet* only in a build that has it.

Where the outcome is decided: an import when its files are read (a run with a file that would
not read is a ✗); intervals.icu and Strava when the service answered; a map to the watch when
Connect IQ reports it delivered; the wind likewise; Apple Health export per workout Health
accepted; a backup when the file is written; a restore when it finished; a notification when
iOS accepted it; a share card, a FIT or a clip when the rider tapped Share or Save and the file
was there; a page or a tab when it opened; a setting when it changed. The Normal layout of the
mail prints one line per used feature (*Send map to watch ✓ 12 · ✗ 1*); Extended adds tries
without an answer, the dates, the reason, the share card's variants and the failure sentences
the phone showed. Both open with the build and the device.

<!-- usage-features:begin -->
| group | feature | key | lowest channel |
|---|---|---|---|
| App | App opened | `appOpen` | release |
| Sources | intervals.icu sync | `importIcu` | release |
| Sources | intervals.icu in the background | `icuBackground` | release |
| Sources | Strava connect | `stravaConnected` | release |
| Sources | Strava import | `importStrava` | release |
| Sources | Apple Health import | `importHealth` | beta |
| Sources | Apple Health auto-import | `healthAutoImport` | beta |
| Sources | File import | `importFile` | release |
| Sources | Share-sheet import | `importShareSheet` | release |
| Sources | Garmin ZIP import | `importZip` | release |
| Sources | Direct watch transfer | `watchTransfer` | dev |
| Watch | Send map to watch | `mapToWatch` | dev |
| Watch | Send wind to watch | `windToWatch` | dev |
| Watch | Choose or forget a watch | `chooseWatch` | dev |
| Watch | Apple Watch recording | `appleWatchRecording` | beta |
| Analysis | Open a session | `sessionOpened` | release |
| Analysis | Re-run analysis | `reanalysis` | release |
| Analysis | Tuning | `tuning` | dev |
| Analysis | Windsurf mode | `windsurfMode` | dev |
| Analysis | Turn-direction setting | `turnDirection` | release |
| Reading | Turn detail | `turnPage` | release |
| Reading | Flight-end detail | `flightEndPage` | release |
| Reading | Replay | `replay` | release |
| Reading | Record replay | `recordReplay` | release |
| Reading | Map styles | `mapStyle` | release |
| Reading | Full-screen map | `fullScreenMap` | release |
| Reading | Filters | `filters` | beta |
| Reading | Month, year or spot grouping | `grouping` | beta |
| Reading | Session paging | `sessionPaging` | release |
| Reading | Trends | `trends` | release |
| Reading | Records | `records` | release |
| Reading | Periods | `periods` | release |
| Share | Share card | `shareCard` | release |
| Share | Replay clip saved | `clipExported` | release |
| Share | Session video | `videoExported` | beta |
| Share | FIT share | `fitShare` | release |
| Share | Send session to us | `sendToDeveloper` | beta |
| Share | Period share | `periodShare` | release |
| Library | Rename or caption | `rename` | release |
| Library | Assign a rider | `riderAssign` | release |
| Library | Gear and spots | `gearSpots` | release |
| Library | Delete a session | `deleteSession` | release |
| Library | Restore deleted sessions | `restoreDeleted` | release |
| Library | Backup | `backupMade` | release |
| Library | Restore from backup | `backupRestored` | release |
| Library | iCloud sync | `iCloudSync` | dev |
| Library | Start over | `startOver` | beta |
| Settings | Settings opened | `settingsOpened` | release |
| Settings | Units | `units` | release |
| Settings | Speed-record rule | `speedRecordPolicy` | release |
| Settings | Row metrics | `rowMetrics` | release |
| Settings | Notifications delivered | `notifications` | release |
| Settings | Apple Health export | `healthExport` | beta |
| Feedback | Feedback mail | `feedbackMail` | release |
| Feedback | Usage report | `usageReport` | beta |
| Feedback | Most-wanted ticks | `mostWanted` | release |
<!-- usage-features:end -->

## What you need, what you get — the three recording classes

The order here is the order every rider-facing table prints, and it is the site's one
rule for watches: **Apple Watch comes right after Garmin**. So a, b + wrist, b, c — on
/watches, on /start and here. `docs/copy/recording-classes.json` keeps the kit's own
order (`RecordingClass.allCases`) and is not reordered for a table.

| class | you record with | you get | you do not get |
|---|---|---|---|
| a | the CleanJibe watch app on a Garmin | everything: foil time, flights, every turn verdict and clean jibe, certified speed records, wind axis, pump strokes and takeoff attempts | nothing missing |
| b + wrist | the CleanJibe Apple Watch app: class b speed, plus the 50 Hz wrist accelerometer (ADR-016) | everything class b gets, and pump strokes and takeoff attempts analysed on the phone | nothing missing; the watch itself detects nothing live |
| b | any other FIT with a Doppler speed channel (Garmin's Windsurf profile, another Connect IQ app) | foil time, flights, turn verdicts and clean jibes, **certified** speed records, wind axis | pump strokes and takeoff attempts, shown as absent, never as zero |
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
| Strava import | release | testers Jan and Robert; cap 10 riders today, Developer Program review for more. The rider-facing text never says Strava has not reviewed the app: "Strava lets a new app connect a limited number of riders", and Menu → Support & ideas is the way to say so |
| GPX and TCX imports (Polar, Suunto, COROS route) | beta | in the beta from day one. The release names no beta as the answer: "Polar, Suunto and COROS sessions come in through Strava, or through intervals.icu" |
| Garmin export ZIP (full history) | **release** | moved up 14 Sep 2026 from the release walkthrough: the release already declares `public.zip-archive`, its button already says "FIT or ZIP…" and `ZipWalker` / `ingestContainer` are ungated, so the door was open and only the list said otherwise. The beta keeps the dedicated **Garmin export ZIP…** button with the Export-Your-Data walkthrough on it |
| Apple Health, read Apple Workout recordings | beta | unproven; off until switched on |
| Apple Health, write sessions as workouts | beta | unproven; the release has no HealthKit entitlement |
| Discipline review after import ("Which rig?") | dev | part of windsurf |

### The analysis

| feature | channel | note |
|---|---|---|
| Engine 0.25.0: foil time, flights, touchdowns, falls, wind axis | release | the number is the engine the three channels share; `docs/algorithms.md` is the contract and `tools/check_release.py` holds this row to it |
| Turn verdicts, clean jibes, JPH · CPH · WPH, dry streaks | release | |
| GP3S record set, uncertified marking | release | |
| Pump strokes, takeoff attempts | release | class a and the Apple Watch app (wrist accelerometer); absence shown as absence |
| Turn page and flight-end page with the three strips | release | |
| "Wrist under" layer, why-line on every touchdown | release | |
| Windsurf discipline (foil, fin), per-discipline thresholds | dev | experimental |
| Tuning page, sliders, turn workbench, tuned chips | dev | listed as a potential beta feature on request |

### The library

| feature | channel | note |
|---|---|---|
| Session list, detail page, four tabs | release | |
| Group by month, year, spot; filter menu; chips | beta | |
| Fold a group; Collapse all / Expand all | beta | with the grouping it folds, 25 Sep 2026 (F7e). Before release: moves with the grouping |
| Swipe a row → Rider: change whose session it is | beta | 25 Sep 2026 (F7d). The import's own picker; release keeps the swipe's Delete only. Before release: **rule 1**, a session reassigned both ways on a real device with Records and Trends checked after each |
| Spots, gear, periods | release | |
| Records, trends, all-time tables | release | |
| Speed records: only verified / prefer verified / include unverified | **release** | Settings → Speed records, 22 Sep 2026. Whether a record off a track with no Doppler speed may stand. One rule in the kit (`SpeedRecordRule.eligible`, pattern L) read by the records table, the personal bests, the celebration, the Trends best-2 s series, the share card and the widget snapshot, and one function in Python (`library.eligible`) read by the browser's aggregate. Applied at query time, so moving it re-reads the same rows and re-imports nothing. Release because it meets all four rules on the day it ships: it is a setting over an engine number that has been in every build since 0.9.0, it has a help topic (*Verified and unverified speed records*), it needs no watch to review (the example session and any GPX show both answers), and it removes a report rather than opening one |
| Backup and restore, deleted-session memory | release | |
| iCloud Drive library sync: two devices, one library | dev | issue #7, ADR-026. Settings → iCloud Drive, one switch, `#if DEV`. Before beta: **rule 1** on two real devices — Jan's iPhone and iPad, ten or more sessions crossing both ways with a rename, a gear change and a delete on each side, no session doubled and none resurrected; a help topic on what does and does not travel (the analysis is redone on each device, the folder counts against the rider's iCloud storage); the privacy page naming iCloud Drive as a destination for recordings; the container registered on the App Store app id and both profiles regenerated, which is what moving the entitlement out of the dev-only container needs |
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
| Send a session to the developer | beta | Share → *Send this session to the developer*, 21 Sep 2026. A comment field, a consent sentence, and the ordinary feedback-mail path carrying the **archived original, scrubbed** (22 Sep 2026, `FitShareFilter`, same rule the friend's share uses) plus this session's headline numbers and any watch-vs-phone rows. `#if BETA` in the app, so the release build has no row, no sheet and no attachment path; the help topic is bound to `.beta` and never reaches the release index. The "decide before release" item is decided — scrub (docs/analytics.md). Before release: **rule 1** on ten mails from two riders |

### Watches

| feature | channel | note |
|---|---|---|
| Apple Watch app: recording, live numbers, transfer to the phone | beta | in the beta from day one; release once Jan's daughters' sessions arrive by themselves |
| Home-screen widgets (last session, this week — "since your last session" in a week off the water — and personal bests) and the watch complication | beta | need the app group before they show anything |
| Garmin link: summary card from the watch | dev | |
| Direct transfer from the Garmin watch | dev | issue #14, ADR-027, docs/transfer-format.md. The recording itself over the Connect IQ link, in 8 KB pages, about twenty seconds on the beach. No new switch on either side: it rides the card's `phonePush`. All four rules are **unmet** — (1) nothing has crossed on the water yet, only the probe of 19 Sep 2026 and the tests; (2) Garmin Connect Mobile owns the link and keeps the whole Garmin story in dev until it has real sessions behind it; (3) it is days old, not a fortnight; (4) it cannot be reviewed without a watch, because there is no way to see it from the example session or a shared file. Before beta: ten sessions across two riders, a help topic on what arrives and what still comes from the FIT, the privacy page naming the link as a way a recording reaches the phone, and a `cutShort` column so a transfer the rider walked away from says so on the session and not only in Settings |
| Garmin watch: the crash breadcrumb | dev | The watch has no crash reporting: an unhandled exception drops the rider to the watch face and writes `CIQ_LOG.YML` on a watch on a beach. `CrashBreadcrumb` counts the runs that never reached `onStop` and keeps the screen the last of them was on; the dev build prints `crashes N (last: view)` on the link probe's Results page at start, and the summary card carries the count as `cx` in **every** stream (docs/testing.md, "The watch's crash hunt"). **Closed on the phone side, 20 Sep 2026**: `CompanionSummary` takes `cx` off the card (optional, and never a reason to refuse a card), `SessionIngestor` keeps it on the session the card wrote (`SessionRow.watchCrashes`, GRDB v18) and the feedback mail prints one line under the phone's own "Recent crashes" — *Watch app: 3 runs ended without a save*, *Watch app: no crashes reported* when the watch has lost none, nothing when no card ever said. No Settings row and no screen: a crash count is a diagnostic, and the mail is the one reader who can act on it (docs/transfer-format.md) |
| Garmin link: send wind to watch | dev | potential feature on request only |
| Garmin link: map to watch, spot picker, "Where I am now" | dev | the only location prompt in the app |
| Companion UUID probing (three watch builds) | dev | |

### Feedback and channel furniture

| feature | channel | note |
|---|---|---|
| Feedback mail with prefilled facts, footers on every page, menu Support | release | |
| "Coming in a future release" section with the TestFlight link and the beta list | release | named *"Curious about what is coming"* until 14 Sep 2026 and *"What is being tested"* until 15 Sep; the row answers the rider's own question — when do I get these — rather than naming the room they are tried in. **Settings only**: it had a row in the library menu in the release channel and lost it on 15 Sep, because the menu is for what a rider needs now (Jan, build 58). It lists the **beta** rows of this file and nothing else: the dev rows are `#if BETA`, because a handful of hand-picked phones is not a promise to anybody on the App Store. On the page, *How to join the beta* is the **first section and a step** — one tap, library kept, a prominent TestFlight button — not a footnote under the lists. The beta shows the same list without the join section, and the dev rows under it as *Further out*. It is the only surface either list appears on: the Beta section stopped repeating the beta rows on 15 Sep (Jan, dev 68) |
| The Beta page: Menu → *Join the beta*, the welcome's footer and the Apple Watch app's card | release | 25 Sep 2026 (Jan's plan of 24 Sep, section 5). Every channel has it, gated inside: the release titles it *Join the beta* and carries the public TestFlight link (`AppChannel.testFlight`); the beta and dev title it *You are in the beta* and have no join step. The list on it is this file's beta rows (`ChannelFeatures.beta`), not a second list. The web has the release's page (`#/beta`) |
| Beta section: request a feature, extended feedback mail with usage and feature statistics, check for a newer build, start over | beta | counters kept on the phone, sent only in a mail the rider edits. **Actions only, no list**: it checked the beta rows off one row above the page that lists them again, so a tester read them twice on one screen (Jan, dev 68) |
| The usage report: tried / worked / failed per feature (the table under "What the usage report counts"), the failure list, a *Your feedback* field and a Normal / Extended switch in its sheet, and the card the library raises every fifth session or fortnight | beta | `UsageCounters` in the kit, `usage.counters.v1` on the phone (a blob from build 107 or older decodes, each old count read as that many successes); subject "CleanJibe beta usage report", Settings → Beta → Send usage report is the permanent door (docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's usage report"). It is the evidence for the release gate above |
| "Most wanted" in the feedback mail: the rows of "Coming in a future release" as ticks, plus one free line | release | the general feedback doors (Settings, the page footers, the menu) open a short sheet first; a session's *Report a problem* goes straight to the mail. The ticks travel under the fixed heading **Most wanted**, one line each ending in the row's `channels.json` id, so replies are tallied by searching for `· appleHealth`. The release offers the beta rows its own Coming page lists; beta and dev add the dev rows (`MostWanted.offered(in:)`) |
| Start over: the tester's uninstall, done properly | beta | last row of the Beta section, red, behind an alert that names every item. iOS keeps keychain items across an app delete, so a reinstall hands the intervals.icu key and the Strava connection back and the fresh first run never happens (Jan, 14 Sep 2026). `StartOver.wipe` is the one wipe — keychain pair, the whole defaults domain plus the app group's, and the container — and `SessionStore.startOver` closes and reopens the library around it, so the welcome screen comes back without a relaunch. The `UI_RESET=1` screenshot hook calls the same wipe (docs/presentation/status-feedback-start-widgets-ipad.md, "Start over") |
| The update reminder: "there is a newer build than the one you are holding" | beta | `web/app/version.json` on cleanjibe.org is the whole switch — one static file Jan edits, with a `minBuild`, a sentence, a level and a link per channel (web/app/version.README.md). The app reads it at most once every 24 hours, compares `minBuild` with its own `CFBundleVersion` and shows either nothing, one dismissable line at the top of the library (`remind`) or one full screen it cannot get past (`insist`). The comparison is `UpdateVerdict` in the kit, where it is tested; `UpdateReminder` and `UpdateReminderViews` are `#if BETA` in the app, so the release binary carries no URL and `strings` finds no `version.json`. Network failure is silence. Settings → Beta carries the manual check (docs/presentation/status-feedback-start-widgets-ipad.md, "The beta's update reminder") |
| Start screen, library menu order, Getting started topic | release | |

### Platforms

| feature | channel | note |
|---|---|---|
| iPad and "Designed for iPad" on the Mac | dev | release and beta build for iPhone only |
| A live view on the Apple Watch (foil state, flights, records, turn verdicts on the wrist, as the Garmin app shows them) | beta list, as a plan | listed 16 Sep 2026 as a dev idea; on the **beta** list since 19 Sep (Jan: name it on the beta outlook explicitly), with the row's first word saying *Planned*, because nothing is built — the watch app records, the kit does not yet run on watchOS and the live detectors exist only in Monkey C |

## The watch — the same three streams

Decided with Jan on 15 September 2026: the Garmin app ships in the same three streams as the
phone, from one commit and one version number, each under its own Connect IQ app id, which on
a watch means its own app.

| stream | jungle · manifest | app id | listing | name on the watch |
|---|---|---|---|---|
| **release** | `monkey.jungle` · `manifest.xml` | `b1ef484c` | **CleanJibe Wingfoil Watch App** — opened when the iPhone app is on the App Store, so the two listings can name each other | CleanJibe |
| **beta** | `monkey-beta.jungle` · `manifest-beta.xml` | `28942317` | **CleanJibe Wingfoil Watch App Beta** — the existing public listing, open to anyone, no key; it runs ahead of the release and says so | CleanJibe Beta |
| **dev** | `monkey-dev.jungle` · `manifest-dev.xml` | `953f7547` | "CleanJibe – private", installable by Jan's account only, Pending by design | CleanJibe Dev |

The listing's first sentence names the family: *the watch app of CleanJibe Wingfoil Analyzer
for iPhone and browser.* The watch records and judges live; the deep analysis is the phone's,
which is why the watch listing is not called an analyzer.

**Rules.** A version reaches the beta first, always; it moves to the release listing when it
meets the four rules above (ten sessions, two riders, a fortnight, no open report). Dev gets
every build, with a `-devN` suffix on the version string, and is where the experiments live.

**Gates in code.** Monkey C has no `#if`; the jungles exclude annotations instead. `(:dev)`
marks an experiment and its switch (today: the map after save, GitHub #4, whose property and
setting live in `resources-dev/base/`; the link probe, GitHub #14, a hidden item under
Wind from that times a page of bytes to the phone, docs/direct-transfer.md; and since 0.9.16
the **per-page data-screen editor**, below); a `(:notdev)` twin with the same name stands in
for it everywhere else. `monkey.jungle` and `monkey-beta.jungle` exclude `dev`, `monkey-dev.jungle`
excludes `notdev`, so a release or beta build carries neither the switch nor the code behind
it. `resources-beta/base/` turns raw accelerometer logging off for beta riders (the developer's
validation vehicle, not the rider's). The invite lock of ADR-012 is retired: every stream
compiles the all-zero pepper.

**What each stream shows of the data screens** (0.9.16). Two features, and they went
deliberately opposite ways:

| feature | channel | |
|---|---|---|
| **Page set: standard / large text** — one Garmin Connect enum, five big screens or the eight standard ones (docs/presentation/watch.md, "The watch's two page sets") | **release** | it is one enum with two values, it needs no explanation, and it is the answer to the one piece of feedback that started the round ("I need my glasses"). A rider who never opens it gets exactly the app he had |
| **The per-page editor** — eight screens, each a layout plus five metric slots, plus *Reset pages to defaults* (`pg1Layout` … `pg8s5`, `resetPages`) | **dev** | 49 rows in Garmin Connect for a rider who mostly wants one thing bigger. It is a tuning instrument, and it moved out of `resources/settings/` into `resources-dev/base/settings/` in this round along with its strings; `PageModel._store` is the `(:notdev)` twin that answers with the default table, so release and beta show the eight pages the table holds. **Candidate for beta the day a rider asks for it**: one jungle line moves the resources, and the four rules are already met on the code (it shipped to every rider from 0.8.2 to 0.9.15 with no report against it) — what it lacks is anyone asking |
| **The direct transfer's progress line and its buzz** — `phone 4/13`, then `wrist 2/8`, then `phone ok` on the SAVED and start screens, one tick when the last stream is whole | **dev** | it rides with the direct transfer itself (below), and moves when that does |
| **The wrist stream** — the 25 Hz magnitudes as a second stream after the recording (docs/transfer-format.md §2b, ADR-031), and the **packed page** that lets the pre-6.0.0 fleet carry either | **dev** | same: it is part of the direct transfer and has no life without it. The packed encoder is untested on hardware until a fenix 5 Plus runs the probe (docs/direct-transfer.md §5) |

**Devices.** The app needs Connect IQ 3.3.3 and about 770 KB of app memory: the fenix 7 and 8 families, the fenix 5 Plus family (since 0.9.11), epix 2, the Forerunners 255/265/570/955/965/970, MARQ 2, D2, Descent Mk3, Enduro 3, Venu 2/3, vívoactive 5/6 and Instinct 3 AMOLED. The plain fenix 5/5S (128 KB), the 5X (no System 5) and the Instinct 2 family and Instinct 3 Solar (96–128 KB) cannot run it; their riders record with Garmin's own Windsurf or SUP profile and come in as class B through intervals.icu.

**What is different from the phone.** A different app id is a different app on the watch: a
rider moving from the beta to the release installs the second beside the first, deletes the
first and enters settings once more — said once, in the release notes. Every public listing
goes through Garmin's review on every upload, so a release costs two reviews. The three
packages come from one script, `garmin/tools/package.sh [N]`, which refuses to run when the
three manifests disagree on the version.

## Telling the channels apart — the mark

Three builds can sit on one phone (the App Store app, the beta, the dev app) and two on one
watch, so each channel wears its own cut of the brand mark, decided with Jan on 14 September
2026:

| channel | the mark | where |
|---|---|---|
| release | as drawn in `brand/icon-square.svg` | App Store icon, launch screen, splash, welcome page, watch icon and start page, Garmin launcher and splash |
| beta | the same mark with a red **BETA** label in the upper right | the same places, from `AppIcon-Beta` / `SplashMark-Beta` / `LaunchMark-Beta` / `BrandMark-Beta` and `garmin/resources-beta/` |
| dev | the mark mirrored left-to-right, wing upper **right** | the same places, from the `-Dev` sets and `garmin/resources-dev/` |

The label is red because nothing else in the mark is; the mirror keeps every colour and
proportion, so the dev app still reads as CleanJibe. Below 14 px of label height the word
becomes a plain red block (the 40 px Garmin launcher, the 19 px badge); on the Apple Watch
icon the label moves inward so the circular mask does not cut it. The watch complication is
tinted by the face, so a label would vanish: dev wears the mirror (`ComplicationMark-Dev`,
decided with Jan on 26 September 2026), beta and release the plain `ComplicationMark`.

What does **not** change with the channel: the share card, its QR centre and the replay
clip cards. Everything that leaves the phone carries the release mark, because a card
promotes CleanJibe, not the build that rendered it.

How it is wired: the cuts are generated from the two release renders by
`brand/tools/make_channel_marks.py` (iOS asset sets, Garmin launcher icons, the reference
PNGs and SVGs in `brand/`) and `garmin/tools/make_brand_mark.py` (the watch's ink-only
cuts), both reading the treatments from `brand/tools/channelmark.py`. On iOS the
configuration picks the icon (`ASSETCATALOG_COMPILER_APPICON_NAME`) and the launch image
(`CJ_SPLASH_MARK` → `UILaunchScreen`), and `ChannelArt` picks the splash and welcome marks
under `#if DEV` / `#if BETA`; the watch app has the same flags for its start page. On the
Garmin, `monkey-beta.jungle` (the open beta) and `monkey-dev.jungle` (the private dev
listing) append the channel's directory after each size class so its resource ids win.

## The Strava review

The form is the HubSpot one linked from developers.strava.com/docs/getting-started ("please
submit your app for review"): share.hsforms.com/1VXSwPUYqSH6IxK0y51FjHwcnkd8. Jan fills and
submits it himself (his name, jan@lahmann-online.de, company "Jan-Rainer Lahmann", app
"CleanJibe", client id 279015, no additional apps, the current authenticated count, intended
users "a few hundred", support URL cleanjibe.org/start, the three compliance boxes). Prepared
answers:

*Application description.* CleanJibe is a free, open-source wingfoil analysis app (iPhone,
and the same engine in the browser at cleanjibe.org). A rider connects their own Strava
account and picks one of their own activities; the app downloads that activity's position
stream and analyses it on the phone — foil time, flights, turn verdicts, speed records — and
shows the result to that rider only. Nothing is uploaded to Strava, no other athlete's data
is read, nothing is stored outside the rider's phone, and the imported session links back
with "View on Strava". Read scope only (activity:read_all for private activities).

*Images.* Every place Strava data or branding appears: the Import screen with the official
"Connect with Strava" button and the "Compatible with Strava" mark; Settings → Strava; the
session page of a Strava import with its "View on Strava" link; the session list row with
the Strava source tag. Rendered from the simulator into the scratchpad's store-shots
folder alongside the App Store screenshots.

## Before the release is submitted

1. Strava's application review, requested with the release description and the privacy page.
2. The `BETA` and `DEV` flags and the gating above; the release build contains no GPX/TCX
   door, Garmin link, Health, video export, grouping, windsurf or location code and builds for
   iPhone only; its share sheet declares FIT and ZIP and nothing else.
   The release also **never calls itself a beta and never names a door it lacks**: no other
   platform or third-party app in the help (guideline 2.3.10), no "the beta reads their
   files" on Import, no dev list under "Coming in a future release", and a feedback mail whose
   subject is *CleanJibe feedback · build N · watch*. `strings` on the archived binary shows
   no "Android", no "beta feedback" and no "not reviewed CleanJibe".
3. The dev bundle ids, their App Store Connect record and profiles, URL schemes and display name.
4. The Connect IQ release listing on app id `b1ef484c` only when the link graduates; the
   companion app URL on the Connect IQ listings once the App Store listing is live.
5. The App Store record: privacy labels, support and privacy URLs, age rating, category,
   screenshots for three iPhone sizes, review notes (example session, an attached FIT, no
   account).
6. The website's release state: the download button to the App Store, the TestFlight link
   under "Coming in a future release" (the section's name since 15 September 2026, and the
   pinned one — `docs/copy/channels.json` → `sectionTitle`), iPad off the product copy, a
   Release column on /whats-new.
