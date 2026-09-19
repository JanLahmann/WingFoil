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
| Engine 0.18.0: foil time, flights, touchdowns, falls, wind axis | release | |
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
| Home-screen widgets (last session, this week — "since your last session" in a week off the water — and personal bests) and the watch complication | beta | need the app group before they show anything |
| Garmin link: summary card from the watch | dev | |
| Garmin link: send wind to watch | dev | potential feature on request only |
| Garmin link: map to watch, spot picker, "Where I am now" | dev | the only location prompt in the app |
| Companion UUID probing (three watch builds) | dev | |

### Feedback and channel furniture

| feature | channel | note |
|---|---|---|
| Feedback mail with prefilled facts, footers on every page, menu Support | release | |
| "Coming in a future release" section with the TestFlight link and the beta list | release | named *"Curious about what is coming"* until 14 Sep 2026 and *"What is being tested"* until 15 Sep; the row answers the rider's own question — when do I get these — rather than naming the room they are tried in. **Settings only**: it had a row in the library menu in the release channel and lost it on 15 Sep, because the menu is for what a rider needs now (Jan, build 58). It lists the **beta** rows of this file and nothing else: the dev rows are `#if BETA`, because a handful of hand-picked phones is not a promise to anybody on the App Store. On the page, *How to join the beta* is the **first section and a step** — one tap, library kept, a prominent TestFlight button — not a footnote under the lists. The beta shows the same list without the join section, and the dev rows under it as *Further out*. It is the only surface either list appears on: the Beta section stopped repeating the beta rows on 15 Sep (Jan, dev 68) |
| Beta section: request a feature, extended feedback mail with usage and feature statistics, check for a newer build, start over | beta | counters kept on the phone, sent only in a mail the rider edits. **Actions only, no list**: it checked the beta rows off one row above the page that lists them again, so a tester read them twice on one screen (Jan, dev 68) |
| The usage report: seventeen counters, the failure list, and the card the library raises every fifth session or fortnight | beta | `UsageCounters` in the kit, `usage.counters.v1` on the phone; subject "CleanJibe beta usage report", Settings → Beta → Send usage report is the permanent door (docs/presentation.md, "The beta's usage report") |
| Start over: the tester's uninstall, done properly | beta | last row of the Beta section, red, behind an alert that names every item. iOS keeps keychain items across an app delete, so a reinstall hands the intervals.icu key and the Strava connection back and the fresh first run never happens (Jan, 14 Sep 2026). `StartOver.wipe` is the one wipe — keychain pair, the whole defaults domain plus the app group's, and the container — and `SessionStore.startOver` closes and reopens the library around it, so the welcome screen comes back without a relaunch. The `UI_RESET=1` screenshot hook calls the same wipe (docs/presentation.md, "Start over") |
| The update reminder: "there is a newer build than the one you are holding" | beta | `web/app/version.json` on cleanjibe.org is the whole switch — one static file Jan edits, with a `minBuild`, a sentence, a level and a link per channel (web/app/version.README.md). The app reads it at most once every 24 hours, compares `minBuild` with its own `CFBundleVersion` and shows either nothing, one dismissable line at the top of the library (`remind`) or one full screen it cannot get past (`insist`). The comparison is `UpdateVerdict` in the kit, where it is tested; `UpdateReminder` and `UpdateReminderViews` are `#if BETA` in the app, so the release binary carries no URL and `strings` finds no `version.json`. Network failure is silence. Settings → Beta carries the manual check (docs/presentation.md, "The beta's update reminder") |
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
setting live in `resources-dev/base/`); a `(:notdev)` twin with the same name stands in for it
everywhere else. `monkey.jungle` and `monkey-beta.jungle` exclude `dev`, `monkey-dev.jungle`
excludes `notdev`, so a release or beta build carries neither the switch nor the code behind
it. `resources-beta/base/` turns raw accelerometer logging off for beta riders (the developer's
validation vehicle, not the rider's). The invite lock of ADR-012 is retired: every stream
compiles the all-zero pepper.

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
icon the label moves inward so the circular mask does not cut it.

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
