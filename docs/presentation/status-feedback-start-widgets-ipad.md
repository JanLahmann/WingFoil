> Part of `docs/presentation.md`. Engine 0.23.0.

## The status line — a toast, and toasts go away

One line at the foot of the Sessions list says what the app is doing or has just done:
*Importing 3 files…*, *Re-clustered into 4 spots*, *Backup ready — 65,9 MB*. Forty-odd places
write it and nothing used to clear it, so the last sentence any job happened to leave behind
sat there until another job replaced it — Jan found *Backup ready — 65,9 MB* still on the
list a quarter of an hour later, which turns a report of something finishing into a claim
about the present.

`SessionStore.status` now arms its own dismissal: **six seconds** (`statusLinger`), then the
line fades out. Two rules the timer keeps. **A message about work in progress outlives the
work** — `isBusy` holds the line and the clear is re-armed rather than fired, so *Packing your
library…* is up for as long as the packing is and the six seconds start when it stops. And
**only the message that armed the timer may be cleared by it**: every write bumps a
generation and a stale timer returns without touching anything, so a slow job's old toast can
never wipe out the one that replaced it. A tap on the line takes it down early, which is
allowed only while nothing is busy. Nothing else about the line changed — same place, same
`.bar` background, same spinner while work is running.

## Feedback mail — the report the app writes and the rider signs

One mail to `info@cleanjibe.org`, reachable from wherever the rider is when something looks
wrong **or when he wants something**: **Menu → Support & ideas** on the Sessions tab,
**Report a problem with this session…** at the foot of a session's share sheet, and a quiet
line at the **foot of every page** — *Something off, or an idea? Send feedback* under the last
row of Sessions, Records, Trends and Gear, and under the last card of a session
(`FeedbackFooter`). On the beta, a screenshot taken inside the app also offers Apple's
**Send Beta Feedback**, which carries the screenshot and the device logs.

**There is no Settings row, and no document may say there is.** The feedback block was
deleted from Settings in build 58 — Settings keeps switches and accounts, and the menu one tap
away already had the door — and the sentence *Settings → Send feedback* outlived it in the
app's own Help, on four website pages and in this file. Every name is `FeedbackDoors` now
(`docs/copy/feedback.json → doors`, pinned by `CopyContractTests`): the app target's three
labels, the Help topic's sentence and the beta footer's are built from it, so a renamed door
renames its own instructions.

**A wish is as welcome as a fault, and five surfaces say so in one sentence** (Jan, 14 Sep
2026). Every door to this mail was named and worded for something being *wrong*, and a beta
whose only invitation is to report faults gets faults reported and nothing else. The sentence
is written once — `FeedbackInvitation.sentence`, *"Ideas and wishes are as welcome as bugs."* —
and carried by the menu row's name, the footer line above, the welcome screen (with the way in
appended: `welcomeSentence`, *"· Menu → Support & ideas"*), Settings → Help's footer, and the
mail's own template. The release notes close on it too
(`ios/tools/testflight_publish.py`, both `WHATS_NEW` and `WHATS_NEW_INTERNAL`).
The session page's line carries the session, so the mail names the afternoon by itself; the
card is attached only from the share sheet, where it is already drawn. Every door climbs the
same ladder (`feedbackMail(on:)`): Mail, then the `mailto:` handler, then the copy sheet.
The subject is `CleanJibe feedback · build <N>[ dev] · <watch>` — the build number, not
the marketing version, because the two TestFlight variants of a release share the latter. It
said *beta feedback* until 14 September 2026: the same kit writes the App Store app's mail,
and a rider who joined nothing must not find his own mail calling the app he bought a test.
The build number still says which channel it is to anybody who needs to know.

**Two facts are left out where the channel has no door for them.** `Health import off` and
`No Apple Watch paired` are answers to questions the App Store build never asks — Health and
the watch app are beta doors — so the app passes both as `nil` outside `#if BETA` and
`FeedbackReport` omits a nil fact rather than printing it (`FeedbackFacts.Watch`).

**The body opens with three labelled blanks, and the facts are under a rule.** The template
was one word — *What happened* — and one empty line, which is a prompt for a paragraph rather
than for a report; what arrived was a paragraph, and the three follow-up mails it always cost
are now asked in advance (Jan, 14 Sep 2026). Each label owns two lines, one for the answer and
one of air:

```
What happened, or what you would like:


What you expected instead:


Which session, its date and spot, if it is about one:


Ideas and wishes are as welcome as bugs.

----------------------------------------
Below is what the app knows about this phone and build. It helps analysis. Delete any line you would rather not send.

App
  …
```

The first label asks two questions on one line on purpose: a rider with a feature wish must
not have to decide whether the form is for him. The third is **answered for him** where the app
knows — from the share sheet's "Report a problem with this session…" the date and the spot are
written onto the first of its two lines, and nothing else about the session is, because the
rest is diagnostics and diagnostics live under the rule. The rule's own sentence is what makes
the facts below it *deletable* rather than merely present: they include a phone model, a
locale, a library shape and sometimes a spot, which is a map pin to where somebody rides.

Everything the phone knows is *below* that rule: a mail that opens with twenty lines of
diagnostics makes the reporter scroll past them to write his report. Prefilled, in this order
(`FeedbackReport`, composed in the kit and asserted line by line in `FeedbackReportTests`):

| section | what it carries |
|---|---|
| App | marketing version and build, **the channel in one word** — `release build`, `beta build` or `dev build, TUNING on` — `AnalysisEngine.version`, and the count of tuned thresholds. That last line only when there are some, and only on the dev build, which is the only one that applies them. The channel line said *public build* on the App Store app and on the public beta alike until 22 September 2026, so a reader answering a report could not tell a tester's phone from a buyer's, and nearly every report comes from the beta (pattern L: one taxonomy per concept). It is `AppChannel.channel`, the one `#if` the app keeps for the purpose, handed to the kit as `FeedbackFacts.App.channel` |
| Phone | the model identifier (`iPhone18,2`) with its marketing name in front of it where the table knows one, the iOS version, the locale |
| Watch | the paired Garmin's name from the companion link, the CleanJibe watch app's version decoded from the last BLE card's build tag (`APP_MINOR * 256 + FIT schema`), whether an Apple Watch is paired (`WCSession`, omitted when it cannot be asked), Health auto-import on or off |
| Library | how many sessions, and the count per door they came in by — a session merged from two sources is counted under both, which is the answer a duplicate report needs |
| Session | *only from a session page*: its date in its own zone, spot, discipline, duration, source-class letter, the `engineVersion` stamp (tuning fingerprint included) and the stable row id — with that session's **share card attached** as a PNG |

It closes with `sent from CleanJibe`. **Nothing leaves the phone until the rider taps Send**:
the mail is `MFMailComposeViewController`, every line of it is editable, and there is no
CleanJibe server for it to go to in any case. Where Mail is not configured
(`canSendMail == false`) the same subject and body go to the system's `mailto:` handler; where
that too goes nowhere, a sheet shows the report in full with one button that copies it. The
help topic is "Sending feedback", last in *Getting set up* — the section's way back out.

**And that topic offers the mail rather than only describing it** (Jan, dev 65). It named
three doors and had none: a page about sending feedback that asks the reader to go and find
one of them is a page he has to leave to use. It carries `HelpAction.sendFeedback`, and the
sheet draws **Send feedback…** wherever somebody can honour it — the Sessions list hands the
action down (`\.sendFeedback` in the environment, the same `feedbackMail(on:)` ladder Menu →
Support & ideas climbs), exactly as it hands down *Open CleanJibe Settings* and *Load the
example session*; anywhere else the button simply is not there. The topic keeps naming the
three doors, because they are where the rider starts next time. Its **invitation is said
once**: `FeedbackInvitation.sentence` opened the summary *and* the first paragraph, one line
under the other, and it now stays in the summary, which is the line the index shows.

### The beta's usage report

**Beta only** (`#if BETA`, docs/channels.md). The same mail with one more block at the foot of
it, under one sentence that says what the block is: *"The block below is what the beta counts
on this phone. It helps development and is a key part of being in the beta. Delete any line
you would rather not send."* The subject is its own — **`CleanJibe beta usage report`** — so a
mailbox sorted by subject does not file it as a bug report and answer it as one.

The block is headed **Usage and features** (`UsageCounters.report`, asserted line by line in
`UsageCountersTests`) and carries, in this order: the build, the first-launch date, how many
days the app has been used on and the day the mail was written; then one line per door that
has been opened — `share card · 12 · last 13 Sep`; then, on **one** line, every door that has
not been opened at all, which is the half that decides what ships (channels.md, rule 1);
then the failures this phone has shown, newest first, deduplicated by message with a count
beside each — the rider-facing sentence, exactly as it was on the screen.

Seventeen doors are counted, one call site each: app opened · the six import doors
(intervals.icu, file, Strava, Apple Health, share sheet, Garmin ZIP), counted in **sessions**
rather than in taps · session opened · turn page · share card · replay clip · session video ·
backup made · backup restored · settings opened · feedback mail · Strava connected. Counts and
a last-used date, never a timestamped trail: "share card · 12 · last 13 Sep" answers the
question the beta has, and a log of twelve moments would additionally describe a rider's
afternoons. They live in this phone's `UserDefaults` (`usage.counters.v1`), they are never
uploaded, and the only way a number leaves the phone is that mail.

**The ask.** After every fifth session imported, or a fortnight since the last ask — whichever
comes first — the library shows one card at the top of the list: *Help the beta: send your
usage report*, with **Write the mail** and **Not now**. A card in the list rather than an
alert, because the honest answer is often "not while I am standing on a beach": it waits where
the rider is already looking, and "Not now" buys a fortnight of quiet rather than ending the
conversation. Either button answers it and the card is gone. **Settings → Beta → Send usage
report** is the permanent door, for the rider who did not wait to be asked and the one who
said Not now and changed his mind.

### The beta's update reminder

**Beta and dev only** (`#if BETA`, docs/channels.md). TestFlight *offers* a build; it does not
insist on one, and a tester with notifications off goes on riding — and reporting — with a
build we have already read the reports of and fixed. The cost is reports against the wrong
build and a rider who believes a mended thing is still broken, so the app says so itself.

**One static file is the whole mechanism.** `web/app/version.json` on cleanjibe.org carries,
per channel, four things: `minBuild` — *the oldest build still worth a report*, not the newest
that exists — one sentence in Jan's words, a level, and where *Update* goes. Jan edits it by
hand and commits it with any other web change; there is no server, no account and no push, and
deleting a channel's entry is how a reminder is taken back off every phone
(web/app/version.README.md says who edits it and what the two levels mean).

**What the app does with it.** At launch and on every return to the foreground, at most once
every 24 hours, it fetches the file, looks up its own channel (`ChannelFeatures.channel`) and
compares `minBuild` with its own `CFBundleVersion`. The comparison is `UpdateVerdict.decide`
in the kit, where the suite holds it; the fetching, the remembering and the drawing are
`UpdateReminder` / `UpdateReminderViews` in the app. A build *at or above* `minBuild` sees
nothing, and so does a build *ahead* of it — a dev build cut this morning is never told to go
back. The last answer is kept in `UserDefaults`, so the line is on the first frame of the next
launch rather than only on the one launch in twelve that falls after the 24 hours.

**Two levels, and only two.** `remind` is one dismissable line at the top of the library, above
the empty state and beside the usage ask, with the message, an *Update* link and a ✕. The ✕ is
remembered against that `minBuild` and not as a flag, so the next raise of the number asks
again by itself; Settings still says a newer build is out. `insist` is one full screen with the
message and an *Update* button, in front of the whole app and not dismissable — the third
screen in the app argued for that way (`LibraryNewerThanAppView`, `StartOverRelaunchView`),
because behind a banner the four tabs would go on inviting the rider to record, import and
report with the build the screen exists about. It says plainly that nothing has been changed
and nothing is lost. A word in the file that is neither reminds rather than insists: a typo
must not be able to put a screen in front of every tester.

**Failure is silence, everywhere.** Offline, a 404, a half-written file, a build number the
plist does not carry: the rider is told nothing, the last answer is kept, and the app tries
again later. He did not ask a question, so he gets no error. The one place he *did* ask is
**Settings → Beta → Check for a newer build now**, which ignores both clocks and prints the
running build, the verdict in one sentence and when the file was last read — the only surface
that names all four verdicts, and the way back for the tester who closed the line and changed
his mind.

**What it costs him.** One GET of about three hundred bytes a day, to the site he installed
the app from, with no query string, no header of ours, no cookie store and no identifier — it
does not even say which build is asking, because the comparison happens on the phone. The
privacy page carries it as the ninth entry under "what leaves your phone". The release build
does none of this: the whole feature is behind `#if BETA`, and `strings` on the App Store
binary finds no `version.json` (docs/testing.md, "Three channels").

### Start over

**Beta and dev only** (`#if BETA`, docs/channels.md), last row of the Beta section, red, and
the only destructive button in the app. It exists because deleting the app does not do what a
tester means by it: iOS keeps keychain items across a delete, so the intervals.icu key and the
Strava connection come back with the reinstall and the fresh first run he was trying to see
never happens (Jan, 14 September 2026 — he deleted the app, reinstalled it, and found both
already there).

The confirmation names everything that goes, because a rider cannot check "all data" and
because the two items he would never guess at are the whole point: *your whole library —
every session, its analysis and its archived recording, the deleted-session memory and any
backup file still waiting on this phone; your intervals.icu key and your Strava connection,
both of which live in the iOS keychain, which is why deleting the app leaves them behind and
this does not; every setting — the welcome screen's flag, map style and layers, replay length,
framing and music, the notification choices, the map picks for the watch and the tuning
sliders; the beta's usage counters and the widgets' snapshot; cached thumbnails, imported
files and anything half-exported.* It closes with what is **not** touched — the sessions on
intervals.icu, the activities on Strava and the recordings on the watch are somebody else's
copy — and with "make a backup first if you want one", because there is no undo.

**It does not ask for a relaunch.** Settings closes, the library's GRDB pool is parked in
memory, the container, the defaults domain and the two keychain items go, a new pool is
opened on the same path where the migrator writes an empty schema, every property that
mirrors a default is read back from the now-empty domain, and the empty library is read —
which is the same event a first launch has, so `RootView` raises the welcome screen by the
ordinary route.

**And the welcome is promised to the next launch as well, in writing** (Jan, build 63: *Start
over, restart, and the app opened on Sessions — this is a mistake*). Everything above is an
argument from **absence**: no `welcomeShown.v1`, no sessions. A wipe can create an absence but
it cannot hand one to the next launch — the screen it raises in-process writes the flag again
the moment it goes up, and a library that has rows once more before the screen is raised (a
sync, a watch transfer, a re-import, or the relaunch the failed-reopen screen asks for) reads
as a *history*, at which point the upgrade path marks the screen seen on sight and the rider
never gets it. So `startOver()` writes one positive fact back immediately after the wipe —
`welcomeRequested.v1` — and `showWelcomeIfNeeded` honours it **first**, before the silent mark
and before the flag: a request outranks `hasSeen` and a library of any size, only a screen
already up defers it, and it is cleared the moment the welcome actually appears. So the
welcome happens exactly once after a Start over — now if nothing is in the way, on the next
launch otherwise — and the screen it appears on is the full-screen cover in front of the tabs,
not a sheet with Sessions in charge behind it. `WelcomePrompt.shouldShow(… requested:)` holds
the rule and `OnboardingTests` pins it at 300 sessions with the flag already written. The
`UI_RESET=1` screenshot hook deliberately does **not** write the request: it wipes before the
store exists so a first run can be photographed, and a staged welcome over a staged library
would be a screenshot of neither. The one thing that can fail is reopening the file, and there the app says so
rather than running on a library that is not on disk: one full screen, *"Start over done —
close the app and open it again"*, with no button, because iOS gives an app no supported way
to quit itself and `exit(0)` reads as a crash in the feature the rider just used.

## Start screen — the mark, held for two seconds

**The phone opens on the brand, and the handover is invisible.** iOS draws `UILaunchScreen`
(ios/project.yml) before a line of our code runs: the `SplashMark` asset on the
`LaunchBackground` navy, and — measured on the simulator rather than assumed — it draws that
image at its **natural point size, centred in the safe area**. The asset is therefore
140 / 280 / 420 px at 1×/2×/3×, which puts a 140 pt mark at the centre of the safe area on
every device, and `SplashView` opens with the same artwork at the same size in the same
place. Nothing moves when our own first frame replaces the system's; the mark carries no
shadow and no corner clip for exactly that reason, because a launch screen can draw neither.
(`LaunchMark` is unchanged and still the full-resolution artwork the share card, the QR's
centre mark and the welcome screen use.)

**The channel wears its own mark.** The beta's launch screen, splash, welcome page, icon and
watch start page show the mark with a red BETA label upper right; the dev app's show it
mirrored, wing upper right; the App Store app's is the mark as drawn. `CJ_SPLASH_MARK`
picks the launch image per configuration and `ChannelArt` the two the code names, so the
handover above stays invisible in every channel. The share card and the QR keep the
release mark (docs/channels.md, "Telling the channels apart").

The clock moves as little as the mark does: `UIStatusBarStyle: UIStatusBarStyleLightContent`
is what the *launch* screen reads and `preferredColorScheme(.dark)` is what the splash asks
for, so the status bar is white over that navy on both frames. It changes nothing afterwards —
`UIViewControllerBasedStatusBarAppearance` defaults to on, so the library keeps its own.

Under the mark, and the only thing that moves — they fade up over 0.35 s — the wordmark
**CleanJibe** and the share card's call to action *without its address*: "analyze your
wingfoil sessions free". Same line, one source (`Branding.callToAction`), minus the
`cleanjibe.org` that exists for a receiver who does not have the app yet. **The address then
follows on a line of its own** (`Branding.site`), so the screen reads mark · CleanJibe · what
the app is for · cleanjibe.org — the start screen should say where to find us and not only who
we are (Jan, 14 Sep 2026), and a rider showing the app to someone on the beach is the reader it
is written for. It survives landscape where the call to action does not, being one short line
rather than a wrapping sentence; the words hang off the mark as an overlay and grow
downwards, so neither line can move the mark off the centre the launch screen put it on.

**The three lines are set in points, and they were made bigger** (Jan, 14 Sep 2026: too small
on a phone). The first cut was `.largeTitle.bold`, `.footnote` and `.caption2` at 55 % of the
paper — 13 pt and 11 pt of small print on a screen whose entire job for two seconds is to be
read at arm's length, often over somebody's shoulder. Now, and named in `Splash` so the
lockup's proportions are one decision:

| line | portrait | landscape | ink |
|---|---|---|---|
| wordmark `CleanJibe` | **34 pt semibold** (`Splash.wordmarkPoint`) | 28 pt (`wordmarkPointShort`) | paper |
| tagline | **17 pt** (`taglinePoint`) | dropped | paper at 80 % |
| `cleanjibe.org` | **15 pt** (`sitePoint`) | 14 pt (`sitePointShort`) | paper at 80 % |

Semibold rather than bold: at 34 pt bold reads as a shout, and the mark above it is already
the loud half. Fixed points rather than text styles, and this is the one screen that earns
them — the lockup hangs under a mark the launch screen has pinned to the pixel, so it may not
reflow with Dynamic Type; at the largest accessibility size it would push the address off the
bottom of a phone in landscape, and the mark cannot move to make room. Every other screen in
the app follows Dynamic Type. The landscape column is the same lockup with the tagline gone and
the two survivors stepped down, which keeps the block inside the ~195 pt a compact height
leaves below the centred mark (140/2 + 16 + 28 + 6 + 14 ≈ 134 pt).

**It stays for max(2 s, the library).** Jan set the floor — *"Don't make it too short; can be
2 seconds or so"* — and the second half of the rule is what makes it honest: a cold start
still reading the library at the end of those two seconds goes on showing the brand rather
than handing over to an empty list (on a simulator stuffed with fixtures that is a minute or
more, by design). Then a **0.4 s crossfade** into Sessions — under Reduce Motion, a cut after
the same hold. It is **cold start only**: the view is built once per process, so a return
from the background shows nothing. It is one accessibility element labelled "CleanJibe", and
it dismisses itself on a clock, so VoiceOver has one thing to say and nothing to escape. The
simulator screenshot hooks switch it off outright — any `UI_` variable means an automated
launch, the hold is 0 s and the splash is never built, so every existing shot is unchanged.

**The watch has no splash, and the mark is simply on the start page.** A phone app opens into
a library that takes a moment to read; a watch app opens into a button the rider is standing
in the shallows waiting to press, and two seconds of brand there would be two seconds of
nothing at the worst possible moment. So `StartView` wears the mark above its own name — the
first thing seen, one lockup with the wordmark — and the GPS line and START are where they
always were. The mark is **a fraction of the glass** (14 %, clamped to 26–36 pt: 28 pt on a
40 mm SE, 35 pt on an Ultra) and the page **scrolls** now, both for the same reason: a 40 mm
watch has about 165 pt of usable height and the page had already spent it, so at a fixed size
the "Allow Apple Health to record heart rate" note lost its second line and truncated
mid-word. Nothing moves under the thumb when everything fits (`.basedOnSize`).

## Home-screen widgets — three, and what each of them says

Beta and dev only (docs/channels.md): the release app embeds no widget extension. All three
read one small JSON blob the app publishes after every library change and decode it and
nothing else — the extension does not link the kit and cannot open the library (ADR-011), so
every question that needs a library row is answered on the app's side and arrives here
already answered.

| widget | families | what it says |
|---|---|---|
| **Last session** | small · medium · large | the last afternoon **ridden**: its name, its date, on-foil share, best 2 s, flights, the turn tally, and the track behind the numbers |
| **This week** | small · medium | foil time over the last seven days — or, in a week with nothing in it, "since your last session" |
| **Personal bests** | small · medium | best 2 s, longest flight, best JPH, each with where and when |

**The last session is the last one ridden**, which is not the same as the newest row. On
14 September 2026 the newest row in Jan's library was a dry test recording and his home
screen read `FOIL 0 % · BEST 2 S — · FLIGHTS 0` while the afternoon before it sat one row
down. The rule is the newest non-provisional row with foil time on it
(`WidgetSnapshot.isRidden`), falling back to the newest row of all only when the library
holds no ridden session at all — a rider whose library is one dry test still gets his row.
A provisional row is excluded for the same reason it is badged in the library: it is the
watch's BLE card with no analysis behind it, and it has no numbers to print. The title is
the library's own (`SessionDisplay.title`: the rider's name for it, else the spot the
filename implies), the date under it, and the tally is shown only when the session has one.

**The track behind the numbers.** The session's outline is drawn as one thin line in the
brand green *behind* the block, at 38 % on medium, 45 % on large and 16 % on small, where
the numbers own every pixel. It is the app's own outline and not a second drawing: the
snapshot carries the cached `TrackThumbnail`'s vertices, already normalized into a unit
square with the aspect preserved by the same projection the list row, the map and the share
card use, thinned to ~150 evenly-spaced points and rounded to four decimals in the *builder*.
The widget owns no projection code and must not — a second projection is a second shape. A
session with no positions, or one whose thumbnail has not been built yet, simply has no
track, and the widget draws none.

**"Since your last session" — the week with nothing in it.** A week away from the water used
to render `0 m on the foil · 2 sessions · 0.0 h out`, which is both dispiriting and, with
two dry test rows in it, wrong. Both windows now count ridden afternoons only, and when the
seven days ending on the day the widget is *drawn* hold none of them the widget switches:

* **days since the last session**, counted against that day rather than against the day the
  snapshot was written;
* **the season so far** — the app's own season, 1 April → 31 March, labelled the way the
  Periods screen labels it ("Season 2026/27") — sessions, hours on the foil, clean jibes;
* **one rotating fact**, changing at midnight.

The rotation is the season's own bests — best 2 s, longest flight, best JPH, longest dry
streak — plus **on this day**: a session in the *same ISO week* of an earlier year, which is
the honest window for a sport whose calendar is weather ("Two years ago this week: Nago
Torbole, 11 flights, best 2 s 24.13 kn"). Before the first afternoon of a new season the
rotation falls back to the all-time bests rather than going blank. The fact of the day is
picked by **ordinal day of year**, so it stays put for the day it is the day's fact; the
timeline carries one entry per day for a week, which is also what turns "11 days" into
"12 days" at midnight without the app being opened.

**Personal bests are three, and JPH is one of them.** Rates are additive (CLAUDE.md): JPH
sits beside the speed and the flight here, and displaces CPH nowhere. The speed record is
**certified sources only** (`RecordBest.certified`) — a class (c) recording can misreport a
speed, and a personal best nobody can stand behind is worse than none — while the flight and
the rate take no such filter, because how long an afternoon flew is not a claim its speed
channel makes. JPH takes the same session-length floor "Best CPH" takes
(`SessionRecordKind.cphMinDurationS`): a rate a rider can set by going home early is not a
record. JPH itself is the engine's — dry jibes over timer hours, read back off the `turn`
table by `LibraryStore.jibeRates`, because the session index denormalizes CPH and not JPH.

**The words and the numbers are the app's.** The extension cannot call `Fmt` or
`KeyMetrics`, so `WidgetFormat` copies the four rules it needs and names, in each doc
comment, the kit function it may not drift from: the percent rule (`47 %`, one decimal below
ten), knots at two decimals, the `1:57 h` / `10:45 min` duration, and a rate at one decimal.
Rider vocabulary throughout — *flew through*, *touchdown*, *fell in*, *clean*, *dry*.

**When the widget shows nothing.** Two different empty states, and they say different
things: "No sessions yet." for an empty library, and "Open CleanJibe to finish setting up
the widget." when the shared container is not reachable, which is a setup fact and worth
saying out loud (ADR-011 — the App Store profile carries no app group today).

## iPad and Mac — one column, wider glass

The iPhone app **is** the iPad app (`TARGETED_DEVICE_FAMILY: "1,2"` on the app and the widget
extension, 13 Sep 2026), and because `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` is on by default
an Apple-silicon Mac gets the same binary from the App Store as **"Designed for iPad"**. There
is no third UI: one build, three shapes of window.

**What is deliberately unchanged.** The tab bar is still four tabs, the library is still a
list that pushes a session, and the session is still one scrolling page over the four-way
switcher of "Sections". There is no `NavigationSplitView`, no sidebar, no two-column
library-and-session, and no iPad-only screen. A sidebar would make the session page the
*detail* of a list, and the session page is the app — the tabs are four ways of asking about
the library, not four folders to keep open beside it. The phone layout is the answer at every
width; the iPad only changes how much glass one answer is entitled to.

**What changes at regular width** — and only at regular width in *both* axes
(`SizeClass.isWideScreen`, because a Pro Max phone on its side is horizontally regular and is
still a phone):

* **One readable column, centred** (`ContentWidth.column`, 740 pt — `readableColumn()`). Every
  scrolling surface takes it: the library, Records, Trends, Gear & spots, Periods, the session
  page, the turn and flight-end pages, Settings, Tuning, a help topic, both card composers.
  Without it the key-metrics block puts three numbers a hand's width apart, a card grid
  (`GridItem(.adaptive(minimum: 150))`) lays six tiles across a row that holds four facts and
  orphans the seventh, and a footnote runs twenty-five words to the line.
* **The figures buy their room back in height, not width** (`figureHeight(regular:compact:wide:)`).
  Inside a 740 pt column a phone-height map would gain nothing from an iPad at all, and an
  iPad has the vertical room a phone does not: the track map goes 260 → 380 pt, the speed
  chart 190 → 260, the turn map 260 → 340, the turn strip 170 → 220, the heading strip
  140 → 180, the baro strip 120 → 155, the focus map 240 → 330. The full-screen map
  (`FullScreenMapView`) is still full-bleed — it is the one surface whose whole point is all
  the glass there is. The one thing this costs is worth naming: on an iPad *in landscape* the
  map and the speed chart no longer both fit above the fold. They did not quite fit at the
  phone's heights either (a 1 024 pt window minus the key-metrics block leaves about 530 pt
  for a 260 pt map, its two control rows and a 190 pt chart), and the "one instrument" rule
  of "Pairing" is about the shared playhead and the shared tap, not about a scroll — which is
  why the compact heights exist for the one screen where it *is* about the fold, a phone on
  its side.
* **The speed table's fixed columns widen** (`RecordColumns`): 66 / 58 / 56 pt on a phone,
  112 / 78 / 64 on an iPad. The three fixed columns are what makes the table scannable, and at
  the phone's widths `Best 5×10 s` printed as `Best 5×…` with 300 pt of empty "when · where"
  beside it.
* **Sheets are pages, not form sheets** (`.presentationSizing(.page)`). A `.large` detent is a
  compact-width idea; on an iPad the system's default form sheet is about 570 × 640 pt, which
  is a *smaller* window than the phone's. The screens that are screens get `.page` — the turn
  and flight-end drill-ins, Settings, Tuning, the Help index and each help topic, both card
  composers, the clip setup and the video export (whose finished state is a 420 pt tall 9 : 16
  player with a share button under it). The sheets that are questions keep the form sheet,
  which is what a question should look like: the rider prompt, the discipline review, the
  re-add offer, the gear editor, Import.
* **All four orientations** (`UISupportedInterfaceOrientations~ipad`). An iPad has no wrong
  way up; the phone list still leaves upside-down out, because a phone flipped over hides the
  earpiece.

The **navigation bar belongs to the window, not to the column**: on the four tab roots the
large title and the toolbar buttons stay at the window's edges while the list under them is
centred. That is left alone deliberately — pulling the whole `NavigationStack` into the column
would centre the title at the cost of a 740 pt bar with hard edges and empty glass beside it
every time the content scrolls under it, which is a worse thing to look at than a title above
a centred card. The session page does not have the question at all: its title is inline.

**Widgets.** The extension ships for both families too. Its three widgets declare
`.systemSmall` and `.systemMedium` (and `.systemLarge` on the last-session one), every one
of which is valid on iPad, on the Home Screen and in Today view alike; the snapshot they
draw is the same JSON the phone writes.

