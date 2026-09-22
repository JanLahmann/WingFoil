# Screens — the inventory, and what each shell does with it
<!-- The one em-dash in this file is in its title. Rider text has none (docs/voice.md,
     rule 4); a doc heading is not rider text, and "—" inside a table cell means "none". -->

The structural twin of `docs/copy/`: that folder holds the sentences more than one surface
says, this file holds the *screens* more than one surface has. `docs/presentation.md` says
what a screen shows and why; `docs/channels.md` says which channel has it; this file is the
list, with a column per shell, so a web or watch agent can see at a glance what exists, what
it is called, and what it may leave out.

## The principle

**One product, three shells.** iOS is the reference: every screen is named there first, and a
name, an empty state or a door invented anywhere else is a bug until it is named there too.
The web is the **port**: the same screens, the same names, the same empty states, minus the
doors a browser has no hands for, plus the two a browser has and a phone does not (drop a
file, run without installing). The watch keeps **its own shape**, eight pages under a
thumb (or **five** with *Data screens: Large text*, the one page control every watch stream
has), no history, no browsing, but the same voice and the same vocabulary: a jibe the
watch calls *flew* is the jibe the phone calls *flew through*. Its whole surface is **22
screens** since 0.9.18 — the start page, the 8 standard data pages, the 5 large-text pages and
the 8 after-save pages — and six of the eight after-save pages are their live twins drawn by
the same code (docs/presentation/watch.md, "The after-save pages and the live ones"). And the
website's home page is
**one marketing front, not a shell**: it says what CleanJibe is, then sends the reader either
into the web analyzer or to `/invite/`, which is the one page that holds the Connect IQ store
link and the TestFlight link (and will hold the App Store one). No store URL lives anywhere
else on the site, and the home page never analyses anything itself.

## The inventory

Channel is the lowest channel that has the screen (`docs/channels.md`). "Doors" are the
buttons and links that leave the screen. *Menu* is the app menu (**What CleanJibe does ·
Getting started · Settings · Help · Support & ideas**), which sits on all four tab roots in
the same place (pattern M).

| tab / home | screen | what it shows | empty state | doors | channel | web | watch |
|---|---|---|---|---|---|---|---|
| — | **Start screen** (splash) | the channel's mark, held, then a crossfade into Sessions | — | none, it dismisses itself | release | missing. A tab does not launch | **Brand splash**, once per installed version |
| — | **What CleanJibe does** (welcome) | the headline, the promise, three highlights, three answers | — | Try the example session · Set up intervals.icu · Later | release | missing today, on the target list | **Start screen**: name, GPS state, wind, "START records · BACK saves" |
| — | **Library newer than this build** | why this build cannot open the library | — | Open TestFlight · Restore from backup | release | missing. No schema to outrun | — |
| — | **A newer build exists** | the update reminder, insist level | — | the link from `version.json` | beta | differs: the **A new version is ready.** banner, with *Reload to update* and *Later* | — |
| — | (no iOS twin) | the web's install offer | — | *Install* · *Later* | — | web only: a tab can become an app, a phone app cannot | — |
| — | **Start over needs a relaunch** | the wipe finished, the file did not reopen | — | none, the rider relaunches | beta | missing | — |
| Sessions | **Sessions** | the afternoons, newest first, each with its track, date and three numbers | first run: *What CleanJibe does · Try the example session*, then **How your sessions get in** (intervals.icu, Apple Watch in beta, Strava, Import a file). Configured: **No sessions yet** with *Import…* and *Sync intervals.icu*. Filtered: **No session matches these filters** with *Clear filters* | Menu · Filter (beta) · Import · a row · pull to sync | release | differs: the **Library** tab, second of three, lists what this browser saved. Empty: *Nothing saved yet. Analyze a file and press Save to library.* Its doors are *Download all (.zip)*, and per row *Open · .fit · .json · Delete* | none. No history, and the summary is gone when you leave it |
| Sessions | **Session page** | one afternoon, under a sticky four-way switcher | *Could not open this session*; provisional: **From your watch** | the name (rename) · Share · flick or `‹ ›` for the neighbour · the four sub-tabs | release | differs: the **Analyze** tab's result is one scrolling document, with chips **Map · Speed · Turns · Takeoffs · Data** on a narrow screen only. No rename | **Summary**, 3 to 8 pages, UP/DOWN |
| Sessions | · **Ride** | map, legend, speed chart, the shared scrubber, foil facts, the session's record table | *This recording has no GPS positions. Chart and records only.* | Open map full screen · Replay · a `?` per card | release | differs: two panels, **Track** and **Speed**, under one chip. No record table of its own. *Open map full screen* is there; the ground is a **Map / Plain** toggle on OpenStreetMap rather than the phone's four styles. No Replay | Summary **Verdict**, **Records**, **Foil**, **Track** — the last three are the live pages verbatim since 0.9.18 |
| Sessions | · **Turns** | a card per turn, then the filtered tally, map and list | *No jibes* and its line | a card opens the turn page | release | differs: the **Turns** table, one row per turn, no cards | recording **Turns** page and **Tacks & jibes** page; Summary **Turns** and **Tacks & jibes** |
| Sessions | · **Takeoffs** | takeoff and pumping tiles, the attempt map and list, what pumping cost | *No attempts* and its line | a row opens the attempt | release | same, as the **Takeoffs** panel, with the no-accelerometer line spelled out | Summary **Takeoffs** |
| Sessions | · **Details** | gear, flight ends, wind, the recording, watch against phone | a missing block is absent, never zero | gear card · a flight end · *Analyse as* (dev) | release | differs: the **Log** chip carries the gear card, **The recording** and **Watch vs phone**. **Flight ends** still sits under the Turns chip, and there is no HR card | — |
| Sessions | **Turn** *n* **of** *m* | one maneuver at its own scale: the drawing, three strips, the numbers, why it ended that way | — | swipe for the next · Done | release | missing. A table row is as deep as it goes | the event flash and its afterglow strip are the live equivalent |
| Sessions | **Flight end** *n* **of** *m* | the same page for the losses no turn owns | — | swipe for the next · Done | release | missing | — |
| Sessions | **Tuning this turn** | the workbench: the ground-truth label, the outcome ladder's working, the what-if against the published defaults, the per-sample table | — | share the CSV · back | dev | missing | — |
| Sessions | **Map** (full screen) | the same map, bigger, pannable, zoomable, rotatable, with the session's name as its caption | — | the layer chips · back | release | same: the figure and its legend move into a full-viewport shell, same camera and same chips, Back or Escape to leave. No rotate — the figure is north up | recording **Map** page; **Saved map** after save (dev) |
| Sessions | **Replay** | the scrubber, the commentary, the clip | — | Record · Play · Clear · commentary switch | release | missing | — |
| Sessions | **Replay** (the clip) | the finished clip, playable, with Save and Discard | — | Save · Discard · Done | release | missing | — |
| Sessions | **Turn page** | one maneuver at its own scale: the drawing, three strips, the numbers, why it ended that way | — | swipe for the next · Done | release | same, as a dialog a Turns row opens: the same drawing at the same scale, north up or wind up, the speed strip with the engine's windows, a heading strip and a foil-state strip, the numbers, the chips, why it ended that way, the coach line and the footnote. `‹ ›`, the arrow keys or a flick for the neighbour. No ghost toggle where there is nothing to compare with, and no dev workbench | the event flash and its afterglow strip are the live equivalent |
| Sessions | **Flight-end page** | the same page for the losses no turn owns | — | swipe for the next · Done | release | same, opened from a **Flight ends** row rather than from the Log tab, which the web has no room for. The same set the phone draws: no end a turn owns, no end the recording truncated | — |
| Sessions | **Replay clip** | the cinema run, full screen | — | scrub · stop | release | missing | — |
| Sessions | **Share** | the card, its shape and stats, or the scrubbed original file | *That image could not be read.* | Share card · Export video (beta) · Share the .fit · rename · a photo | release | differs: the **Share card** dialog, with *Download PNG* because a tab cannot hand a file to an app | — |
| Sessions | **Session video** | the reel, its preset and its progress | — | share the clip | beta | missing | — |
| Sessions | **Rename session** | one field | — | Save · Cancel | release | in the card dialog | — |
| Sessions | **Import** | one section per way in, in the guide's order, each with its class and its footer | *Not available in this build* / *Not available on this iPhone* | Sync intervals.icu · FIT or ZIP… · Import from Strava… · Import from Health… (beta) · Garmin export ZIP… (beta) · a help topic per door · Done | release | differs: the drop zone and the intervals.icu panel are the only two doors | none. The watch is the source |
| Sessions | **Whose session is this?** | Mine or a friend's, and what a friend's stays out of | — | Import · Cancel | release | same, as the **Whose session is this?** dialog | — |
| Sessions | **Which rig?** | the discipline the analysis guessed | — | confirm · dismiss | dev | missing | — |
| Sessions | **Deleted sessions** | the afternoons you deleted, to pick from | — | restore the picked · Cancel | release | differs: a Settings section rather than a sheet, one row per deletion, *Restore · Clear · Clear all*. The browser keeps the file you imported, so a restore re-reads it and goes through the same dedupe. Empty: **No deleted sessions yet.** | — |
| Sessions | **Custom range** | two dates | — | Done | beta | same, as the **Custom range** sheet behind the range on Trends: two dates, *Cancel · Done*, both dates counting | — |
| Records | **Records** | the all-time speed table and the session-record table, under the filter bar | **No records yet**, or **Your records start with your first session** when only the example is in | Menu · the filter bar · a spot or gear chip · **Spots** · a row opens its session | release | differs: the third tab, **Records & trends**, holds both tables plus the totals. Its own two empty states say the same thing in its own words. *Show the window* and *Open the session* are its row doors. One chip of the filter bar is here now, **All spots**, and it drives Records, Trends and Periods together. No gear chip | recording **Records** page (best 2 s, best 10 s) and the **NEW PB** flash, live only |
| Records | **Spots** | the clustered places, with their sessions | **No spots yet** | rename · Re-cluster spots · Look up names again · Done | release | same list, but inline on **Gear & spots** rather than as a sheet of its own, which is where the phone's Gear tab now shows it too. Same 500 m clusterer, same rename, same two doors. The name comes from Nominatim, not from Apple, and /privacy says so | — |
| Trends | **Trends** | one chart per metric over the chosen range | **Nothing in this range**, or **Your trends start with your first session** | Menu · Range · the filter bar · **Periods** | release | differs: the same **Records & trends** tab, as *Session by session* and *Sessions per week*. The **All spots** chip is here too, and it is the same chip Records carries. No range picker | — |
| Trends | **Periods** | trips, months, seasons, and a range you type | **No periods yet** | a period · a custom range | release | same, as the **Periods** block of that tab: Trips, Months, Seasons, and a from/to range with *This week*, *Last 7 days*, *This month* | — |
| Trends | **Period page** | the aggregate block for that spell | — | Share this period · a session | release | differs: each period is a fold rather than a page | — |
| Trends | **Share this period** | the period card | — | share · Done | release | same dialog as the session card, opened from the period's fold | — |
| Gear & spots | **Gear & spots** | the spots section, then wings, boards and foils, each with its totals | **No spots yet**; **No wings yet** per kind | Menu · a spot (rename) · Re-cluster spots · Look up names again · a gear row · Add wing · Show retired gear | release | differs: the spots section is the phone's, and the gear half is one free-text name per session rather than wings, boards and foils kept apart. A spot row carries the two totals the phone drops, because a browser has no session list to sort by spot | — |
| Gear & spots | **New gear** / the gear's name | name, notes, in use | — | Save · Cancel | release | same, as the **New gear** sheet: name, kind, notes, *In the quiver*, *Save · Cancel* | — |
| Menu | **Settings** | accounts and switches, nothing the menu already holds. Sections: intervals.icu · Strava · Deleted sessions · Notifications · **Garmin watch** (dev) · Analysis · Session list · Row shows · Units · **Windsurf** (dev) · **Tuning · dev** (dev) · **Apple Health** (beta) · **Beta** (beta) · Coming in a future release · Storage · Library backup · **iCloud Drive** (dev) · About | one line per section (`SettingsCopy.lead`) and a row that opens its help topic, since 20 September 2026 — pattern K | Get a key in 4 steps · Sync not working? · Connect with Strava · Restore all · Re-run analysis · Back up library · Restore from backup… · Privacy · Done, and the gated rows above | release | missing. The intervals.icu panel is on the analyzer today | none on the watch. Every setting is in Garmin Connect, including *Data screens* and the **seven show/hide switches** that decide which of the eight data screens exist at all (0.9.18, every stream). The **Wind from** menu is the one on-watch picker |
| Menu | **Restore library** | what the backup holds and what it would add | — | Restore N sessions · Cancel | release | same, as Settings → **Restore from a backup…**: what the zip holds, how many it would add, *Restore N sessions · Cancel*. It reads the file **Download all (.zip)** wrote | — |
| Menu | **Coming in a future release** | how to join the beta, what is in it, what is further out | — | Open TestFlight · cleanjibe.org/invite | release | the same list on `/invite/#coming`, from `channels.json` | — |
| Menu | **Tuning** | 27 thresholds on sliders, per discipline | *Every threshold at its default* | Reset all · Re-analyse stale sessions now · **Labels** | dev | missing | — |
| Menu | **Labels** | the turn labels you typed, scored against the engine | — | clear · back | dev | missing | — |
| Menu | **Help** | about forty topics in ten sections, searchable | the system's *No results* | a topic · Done | release | missing as a screen. The glossary fold **? What these numbers mean** and `/learn/#counts` carry a tenth of it | — |
| Menu | **Help topic** | one metric or one door, its items, its picture, its see-also | — | Open CleanJibe Settings · Load the example session · Send feedback… · What's new · a see-also · Done | release | partly, as `/learn/` and `/start/` sections | — |
| Menu | **Getting started** | the routes, one per watch, in one order | — | see-also topics · Done | release | `/start/`, written from the same JSON | — |
| Menu | **What's new** | the release notes, newest first | **Nothing yet** | Done | release | `/whats-new/` | — |
| Menu | **Send feedback** | a mail with the build and the session already in it | — | Send · Cancel | release | the footer's mail link and the GitHub issue link, on every page | — |
| Menu | **Usage report** | seventeen counters and the failure list, before you send them | — | Send · Cancel | beta | missing | — |
| Settings | **Map for the watch** | the spot to send, or where you are now | — | Send map to watch | dev | missing | phone-sent tiles under the **Map** page and the Summary **Track** page |

**The web analyzer today**, in one paragraph. One page, three tabs: **Analyze**, **Library**
and **Records & trends** (**Records** on a narrow screen). Analyze is the drop zone (*Drop a
.fit, .gpx or .tcx file, or a .zip containing one*, *Choose a file…*, *open the example
session*, and three *What you get* crops that each run the example), the optional
**intervals.icu** panel, four progress steps, an error panel that names the likely cause, and
then the result: a summary panel with the key metrics, *Share card*, *Save to library*, the
glossary fold **? What these numbers mean**, and the panels **Track · Speed · Takeoffs ·
Turns · Flight ends · The full analysis**. Library is *Session library* and its count line, with per-row
*Open · .fit · .json · Delete*. *Download all (.zip)*, *Restore from a backup…* and the
per-origin storage note are Settings → **Your data** since 20 September 2026. Records & trends holds the totals, *All-time records*, *Session
records*, *Periods* and *Session by session*, under the **All spots** chip. Three dialogs:
*Whose session is this?*, the share card, and the turn page a Turns or Flight ends row
opens. Two banners: a new version, and the install offer. Five other pages carry the
same site nav (*Get started · Help*, and *Open the app* as its one door) and the same
footer with its prefilled feedback mail: `/`, `/start/`, `/help/`, `/privacy/` and
`/impressum/`. `/strava/callback/` is a relay for the iPhone app and is in no nav, and
`/learn/`, `/watches/`, `/whats-new/` and `/invite/` are redirect stubs into the four
pages that took their content.

## Doors by platform

`docs/channels.md` is the source for which channel has a door; this table is the same list
by **shell**. The order is the one order (pattern J): Garmin, Apple Watch, Apple's Workout
app, any .fit, Strava, and the Garmin ZIP last.

| way in | iOS | web | watch |
|---|---|---|---|
| intervals.icu (Garmin and anything that syncs there) | Settings → intervals.icu, then *Sync intervals.icu*, pull to refresh, and a notification when one lands | the **intervals.icu** panel on Analyze: athlete id, API key, *List recent activities*, *Forget key* | — |
| the CleanJibe Apple Watch app | beta. Nothing to import, the session crosses by itself | — | — |
| Apple's Workout app, through Health | beta. *Import from Health…* | — | — |
| any `.fit` (plus `.gpx` and `.tcx` in the beta) | *FIT or ZIP…*, the share sheet, AirDrop, Files | the drop zone and *Choose a file…*, all four types, every visit. Installed, the page joins the Android share sheet | — |
| Strava | release. Settings → Strava, then *Import from Strava…* | missing. `/strava/callback/` only hands the iPhone app its token back | — |
| Garmin export ZIP, the whole history | *FIT or ZIP…* in every channel; the beta adds the dedicated *Garmin export ZIP…* with its walkthrough | missing. A `.zip` is read only when it holds exactly one recording | — |
| Garmin link, summary card from the watch | dev. Settings → Garmin watch | — | the *Send summary to phone app* setting |
| Garmin link, the recording itself | dev. Nothing to import: the pages arrive over the same link and the session appears by itself, sourced *Garmin watch, direct*. Settings → Garmin watch shows the last one under the link-probe row — when it was ridden, how many pages crossed, how long they took, and *cut short* where the transfer stopped part way (docs/transfer-format.md). The **wrist stream** follows minutes later and takes the same row, counted as *wrist pages*; the session it belongs to gains its pump numbers in place, with no second row and no change of class | — | the same *Send summary to phone app* setting, which gates both |
| the example session | *Try the example session*, on the welcome screen, in the empty library and from its help topic | *open the example session*, and the three crops beside it | — |

## Deviations of the web, with reasons

1. **No install, no account.** The analyzer runs in the tab and the install banner is an
   offer, never a gate. A stranger with a file should get an answer before he gives anything.
2. **Drop a file is the front door, not one of six.** A browser has no watch, no Health and
   no share sheet, so the one door it does have is the first thing on the page.
3. **The example session is the Sessions empty state.** A first visitor has no library, so
   the page shows what it does before it asks for a file.
4. **No Apple doors.** The Apple Watch app, Apple's Workout app and Health are phone
   entitlements. A tab cannot read HealthKit.
5. **No Strava import.** The client secret cannot live in a static page. `/strava/callback/`
   exists only to return the iPhone app's token.
6. **No watch link, no map to the watch.** The Bluetooth companion link belongs to the phone.
7. **GPX and TCX are read on every visit**, though they are a beta door on iOS. The web has
   one channel and runs the engine the beta runs.
8. **Sessions live in the browser, so the page says so.** *Where this lives* is the reason
   *Download all (.zip)* is on the Sessions tab rather than buried in Settings: in a tab,
   clearing site data is the thing that loses a library. The way back in is the phone's —
   Settings → *Restore from a backup…* reads that same zip, through the same engine and the
   same ±60 s dedupe.
9. **The session is one scrolling document on a wide screen.** The four section chips appear
   only on a narrow one. A phone needs the switcher; a laptop has the height.
10. **The whole Garmin history stays the phone's job.** A tab reads a `.zip` only when it
    holds exactly one recording, and says so when it does not.
11. **The store links live on one page, not on the home page.** `/invite/` holds the Connect
    IQ link and the TestFlight link. One page to keep current when a channel moves.
12. **The ground under the track is Map or Plain, not four styles.** The phone has Apple's
    four; the web draws OpenStreetMap, which has no satellite twin, so it offers the two
    states it actually has. It is off until the rider presses Map, because a background that
    fetched a stranger's home beach unasked would break the promise the analyzer makes
    loudest.
13. **A spot name comes from OpenStreetMap, not from Apple.** `CLGeocoder` is a phone
    framework, so *Look up names again* asks Nominatim instead. Same rule either way: one
    coordinate, rounded to three decimals before it is sent, one request per unnamed spot,
    cached, and a paragraph on `/privacy` that says who sees it. The clusterer is the same
    500 m single-link rule at both ends, ported rather than called through Pyodide, because
    the lab bundle's own clusterer runs at 3 km and answers a different question (trips).
14. **`/app/` wears the app's header, not the site's.** Every reader page carries the site
    nav; the app carries the mark, the name and the Menu button, because the iPhone app has
    one toolbar and a second navigation over the tab bar is a second shell on one screen
    (Jan, 19 September 2026). *Get started* and *Help* are not lost: they are the menu rows
    *Getting started* and *Help*. The footer is the site's, byte for byte, on the app as
    everywhere else, and it is the one place the repo link lives.
15. **A spot row carries its totals.** The phone dropped the distance and the foil time from
    its spot rows when the list moved onto the Gear tab, because a session list one tap away
    can be sorted by spot. The browser has no such list, so the two totals stay.

16. **The menu button sits top right on the web, top left on the phone.** Jan's exception
    to pattern M (19 September 2026): the web header already differs — it carries the mark
    and the name as the way home, which a phone tab has no reason to — so the button
    follows the header it sits in. Same rows, same order, same sheet.

17. **The reader says how much every explanation says, once, site-wide.** Jan, 20 September
    2026, from his phone: */app/#/help* and */app/#/settings* were "way too long" and parts
    of */app/#/session* with them. A browser has a scrollbar and no push navigation, so
    everything a phone puts behind a `?` sheet was on the page at once. The switch is in
    Settings and in the menu sheet's footer, **concise by default**: one line under every
    section and every figure, with a `?` into the help topic that carries the rest;
    *extensive* draws that topic's own body under the line, read from the catalogue at
    render time so there is never a second copy of it (`web/js/explain.js`, pattern F). The
    phone has the same two texts — `SettingsCopy.lead` and `SettingsCopy.footer` — and
    prints the second; it is the same copy read at two depths, not two copies.

18. **Settings → Your data is the browser's own section.** The phone has *Storage* and
    *Library backup*; a tab also has site data a rider can clear from under his library
    (deviation 8), so the three are one section with the figures, *Download all (.zip)*,
    *Restore from a backup…* and *Delete everything on this site*. The confirmation is on
    the page rather than a `window.confirm`, because a browser dialog asks in the browser's
    words over an app that has its own. *Units* and *What's new* are the web's other two
    sections the phone does not have: the phone reads the system's units, and What's new is
    a menu row there.

19. **`/invite/` is `/start/#apps`.** The install links and the walkthrough were two
    destinations for one job, and a reader met both before he had either app (Jan, 20
    September 2026). *Get the apps* is the first section of Get started, the release notes
    are its last, and `/invite/` is a redirect because the address is in every TestFlight
    mail we have sent and in the phone's own *Coming in a future release* screen. The site
    nav is two links and one door.

20. **The map legend filters by kind of turn; the phone filters by kind on its Turns page.**
    A tester, 21 September 2026: *"it would be great if you could toggle jibes and tacks on
    or off."* The web session page has three more chips beside the outcome ones — *jibes*,
    *tacks* and *aborted* — and they hide a turn on the map, in the speed strip and in the
    Turns table at once. The phone has the same two words as a segmented control
    (`TurnTypeFilter`: Both · Jibes · Tacks) on the Turns analysis page, and no kind filter
    in `MapLegendView`. *Aborted* is the engine's own per-turn flag (engine 0.21.0), and no
    iOS surface draws it yet.

Everything else that differs is a gap to close, not a deviation.

## The web after the port, as a target

Same names, same empty states, same order as iOS. Sessions is the home. The analyzer becomes
the way a session *gets in*, not the shape of the app.

| page | what it shows | empty state | doors |
|---|---|---|---|
| **Sessions** (home) | the saved sessions, newest first, each with its track, date and three numbers | the drop zone, then *open the example session*, under the words **What CleanJibe does** | Import (drop or pick a file) · Settings · Help · a row opens its session |
| **Session page** | the afternoon, with the four sub-tabs **Ride · Turns · Takeoffs · Details** under one switcher | *Could not open this session* | Share card · the turn page · rename · the neighbouring session |
| **Turn page** | one maneuver at its own scale, as on iOS | — | next turn · close |
| **Records** | the all-time speed table and the session-record table, split out of today's *Records & trends* | **Your records start with your first session**, in the app's words | the filter bar · a row opens its session |
| **Trends** | one chart per metric over the chosen range, the other half of today's third tab | **Your trends start with your first session** | Range · the filter bar · **Periods** |
| **Periods** | Trips, Months, Seasons and a range you type, as they already are, one push from Trends | **No periods yet** | a period · Share this period |
| **Gear & spots** | spots, then wings, boards and foils | **No spots yet**; **No wings yet** | rename a spot · add gear |
| **Settings** | the phone's sections in the phone's order, each a header and one line, from `SettingsCopy`: intervals.icu · Strava · Deleted sessions · Units · **Your data** · About · What's new. Done 20 September 2026, and **Units is on both shells** since the same evening | footers say why a door is off | List recent activities · Forget key · Download all (.zip) · Restore from a backup… · Delete everything on this site · Privacy |
| **Help** | the topics, from the kit's help export, in the same ten sections, as a chip index over ten shut folds with a filter. Done 20 September 2026 | the filter's *0 pages match.* | a topic · Getting started |
| **What CleanJibe does** (welcome) | the headline, the promise, three highlights | — | Try the example session · Set up intervals.icu · Later |
| **Getting started** | `/start/` as it stands, generated from `docs/guide/getting-started.json` | — | the routes, the troubleshooting list |

The home page does not move. It stays the one marketing front: what CleanJibe is, then
*Open the analyzer*, *Get the beta* and *Which watch*.

## The seven names (pattern A, settled 19 September 2026)

Writing the table found seven screens whose title did not name them. All seven are named
now, in the kit, the app and the help together. The rule they were settled by: **a title
names what the screen does**, the ordinal or the session is content, and the verb belongs on
the button.

1. **Two screens were both called "Import."** The doors list keeps the name, because it is
   the list of ways in. The question sheet takes the one the browser app already used:
   **Whose session is this?** The two sub-pages under it say what they do as well —
   **Import from Health** and **Import from Strava**, in the words of the doors that open
   them, instead of *Apple Health* and *Strava*.
2. **The full-screen map wore the session's name.** It is **Map**, with the session's name as
   the caption under it. The door is still *Open map full screen*.
3. **The replay had two names for one thing.** One feature, one name: **Replay**, on the
   setup sheet and on the finished clip. The verbs are on the buttons — *Record* or *Play*,
   then *Save* or *Discard*.
4. **The welcome screen had three names.** It is **What CleanJibe does** on the screen, in
   the menu and in the empty library, read from `AppMenuRow.whatItDoes` so there is one home
   for the words.
5. **The turn page and the flight-end page were titled by their content.** They are
   **Turn 7 of 12** and **Flight end 3 of 9**: the word is the name, the ordinal is where you
   are. *Jibe 7 · flew through · swipe for the next* is the caption under it, unchanged.
6. **The dev workbench was a heading inside the turn page.** It is a screen, pushed from one
   row, titled **Tuning this turn**. Not plain *Tuning*: Settings → Tuning is the 27 sliders,
   and two screens with one name is what this list exists to remove.
7. **"Log" did not say what was on it.** It is **Details** — the session's own facts: the
   kit, the wind, where the recording came from, and where the watch and the phone disagree.
   No narrower word covers all four. The case, the scroll anchors and the `app-shell.json`
   id stay `log`, so every deep link written before the rename still lands.
