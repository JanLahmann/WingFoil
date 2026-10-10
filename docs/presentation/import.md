> Part of `docs/presentation.md`. Engine 0.28.0.

## Import — the doors a session comes in by

The Import sheet is a list of doors in **one order, the getting-started order** (pattern J,
docs/review-checklist.md): intervals.icu, the Apple Watch app, Apple's Workout app, a file,
Strava, and the Garmin GDPR ZIP **last** — `ImportDoor.ordered(channel:)` in the kit, asserted
against `GettingStartedGuide.routes` per channel. Every door is always drawn (pattern E/G): a
Strava section without keys, a Health section before the first import, a sync row without a
key all keep their row and change only their label and footer. Each footer says **what the
door brings in, in one line** (pattern K, at most 25 words) with what the door gets you above it
and a link to the help topic below; the *how* lives in the topic, not in the footer.

Until 18 September 2026 the order was the ZIP first, the Strava and Health doors appeared only
once used, and the footers explained the mechanism in four paragraphs. The three rules above
replaced all of that at once; the doors' wording is `ImportDoor.footer(channel:)` and nowhere
else, and Import → Apple Health carries the Apple Watch door's own sentence so a rider who
recorded on the watch is told her session arrives by itself rather than left to look for it.

### Import does, Settings configures

**Every row on this screen is an action** (Jan, build 63). It was not: *Sync intervals.icu*
sat there greyed out on a phone with no key, saying nothing about why, and the Strava section
carried a *Connected as …* line, which is an answer about an account and not a door. A screen
that both imports and sets up is two screens sharing a scroll, and the rider who taps the
disabled row learns nothing at all.

So the split is by verb. Import holds the four doors and nothing else — the file picker
(*FIT, GPX, TCX or ZIP…*, *FIT or ZIP…* in the release), **Sync intervals.icu**, **Import from
Strava…**, **Import from Health…** (beta), with the Garmin ZIP above them (beta). Settings
holds the two accounts: the intervals.icu key with *Save & check*, the last sync date and the
two help rows; Strava's *Connect with Strava*, who you are connected as, and *Disconnect*.

**A source that is not set up replaces its action with one line**, not with a disabled button
and an explanation under it: **Set up in Settings → intervals.icu** and **Set up in
Settings → Strava** (`SetUpInSettingsRow`), in the app's own path notation, and tapping one
*goes* there — the library owns the single sheet both screens are (`LibrarySheet`), so
Settings replaces Import rather than stacking on it, through the same `openIcuSettings`
action the help topics' *Open CleanJibe Settings* uses. There is no anchor to scroll to: the
sheet opens at the top and intervals.icu and Strava are its first two sections. A build with
no Strava keys says *"Not available in this build"* in both places, in the same words.

**And the footers stay on their own side of the split.** Import's say what the door brings in
— what the door gets you, then the prose (`ImportClass`) — and Settings' say what the account is
for (`GettingStartedGuide.settingsIcu` / `settingsStrava` as the section's first line, the
detail underneath). One string moved with the buttons: the Strava footer opened on *"Connect
your Strava account and import the sessions you pick…"* and now opens on *"Imports the
sessions you pick from your Strava account…"*, because the connecting is no longer on the
screen the sentence is printed on. Nothing else in it changed. **"Sync now" is gone from
Settings** for the same reason: fetching sessions is an import, and Import's *Sync
intervals.icu* and a pull on the Sessions list are the two doors onto that one call. There
was a third, *Sync now* on the first-run setup card, and it went with the card on dev 70.

### What the door gets you opens every footer

Every section footer **begins with what the door gets you**, as a label —
`ImportDoor.classLabel(channel:)`, built from the names of `RecordingClass` in the kit, one
source for the app, the help catalogue and the website:

| label | the door that prints it | the classes behind it |
|---|---|---|
| **Measured speed** | Full history (intervals.icu), Apple Health, the Garmin ZIP, Single sessions in the release | a and b: a CleanJibe recording or any other file with the watch's own speed |
| **Measured speed and the wrist** | the Apple Watch app (beta) | b + wrist: measured speed plus the 50 Hz wrist accelerometer |
| **Measured speed, or positions only from a GPX** | Single sessions in the beta, whose picker also opens GPX and TCX | a, b and c |
| **Positions only** | Strava | c: the analysis, with speed records estimated from positions and marked so |

**No class letter, anywhere a rider reads** (rider review I7 and X9, 9 October 2026). From
14 September the label was "the letter and the thing" — "Class A · Garmin watch app or
Class B · any file with measured speed" — so a rider who had read the table on
cleanjibe.org could match the row. Riders asked *"What is Class A or Class B?"* instead: a
letter in somebody else's taxonomy answers nothing, and the thing beside it already said
everything. So the names became the thing alone, said as what you get, and the letters
stayed in the engine (`sourceClass`) and in docs/channels.md. The Strava footer no longer
repeats *positions only* under a label that says it.

The help topic *Which watches work with CleanJibe* says the same per watch: every row says
measured or estimated speed, and none ends on a class name any more.

**The release footer names no beta.** It used to close on *"Their own GPX and TCX files are
read by the CleanJibe beta"*, which answers a Polar owner's question with a build he does not
have; since 14 September 2026 it closes on the two doors this binary actually has — *"Polar,
Suunto and COROS sessions come in through Strava, or through intervals.icu"*. The beta's own
footer is unchanged: there the picker really does open the file.

### Import from Strava

Strava is the second cloud source (docs/decisions.md ADR-023), and the one that reaches a rider
with no Garmin account and no intention of setting up intervals.icu. Its section is **under**
intervals.icu, deliberately: for the same afternoon intervals.icu hands over the original file
off the watch and Strava hands over positions, and the footer says so in one sentence — *if the
same session is on intervals.icu, take it from there instead.*

* **Connect with Strava / Disconnect** — **Settings → Strava**, and only there since build
  63 ("Import does, Settings configures", above): Import's Strava section shows *Import from
  Strava…* once an account is connected and one line back to Settings while it is not.
  Connecting opens Strava's own consent screen; CleanJibe only ever **reads**, and the words
  say so on both screens. A build with no API keys behind it shows *"No Strava application
  configured"* and where the keys go — a Connect button that always fails would be worse than
  no button. (`StravaImportView` still carries its own connect and unconfigured states, which
  are now the fallbacks of a screen reached with a connection in hand.)
* **The list**: the matching activities of the last two years, newest first, each one marked
  *In your library* where the ±60 s key or the remembered Strava id already knows it. Tap to
  pick, or **Import all new**. Once one session has arrived this way the automatic-pickup
  toggle appears, exactly as it does for Apple Health and for the same reason: a toggle for a
  source the rider has never used is a question about nothing.
* **Which activities** — Strava has no wingfoil type, so the rider picks the set once
  (Windsurf, Kitesurf, Surf, Workout on; Sail and Stand-up paddling off, because for most
  people those buckets hold boats and flat water). Whatever is picked, an activity whose *name*
  says wing, foil, kite, surf or SUP is offered too, as a whole word ("Supporting" is no
  SUP, ADR-036). The intervals.icu sync asks the same words, and only of a type that could
  be a watersport: never of a Run, a Ride or a Hike.
* **Both ceilings are said out loud, and neither says the app is unfinished** (reworded
  14 September 2026). Strava answers **two hundred** requests every fifteen minutes — the real
  number, in the same words on the Import screen and in the help topic, which used to disagree
  with each other — and a run that hits it stops and reports *"Strava asked us to wait"* rather
  than retrying into the quota. The rider ceiling is its own sentence too, but a neutral one:
  *"Strava lets a new app connect a limited number of riders, and CleanJibe is full right now.
  Your sessions can still come in as files exported from strava.com"* (since 9 October 2026,
  next bullet; before, it ended on *Menu → Support & ideas is the way to say so*). It used to read *"Strava has not reviewed CleanJibe yet"*, which tells an App Store
  rider that the app in his hand is waiting for permission to exist. A server error is neutral
  in the other direction as well: *"Strava answered with an error (HTTP 502)"*, never the
  response body, which can echo a request — and a token — straight back at the screen.
* **A refusal for the cap offers the way in that still works** (rider review I5, 9 October
  2026; Jan's decision the same day: keep offering Strava). The eleventh rider used to get a
  modal with the cap, a menu path and only *OK*. Now there is no modal for it: the Strava
  section he tapped from (Settings → Strava, and the Import screen's connect fallback) keeps
  the refusal under the button for as long as it is true — *"Last try failed: Strava is full
  for new riders"* — with `Copy.stravaFullExport` under it (*on a computer, open the activity
  on strava.com and choose ⋯ → Export Original; AirDrop the file to this iPhone and import
  it*) and two buttons: **Import a file instead**, the file picker itself, and **Tell us
  Strava is full**, the Support & ideas mail. `StravaFullFix` draws all of it, in every
  channel, because the refusal, the file door and the mail are all in the release. The
  library footer's *"Strava is full for new riders · Settings → Strava"* points at it, and
  the trouble clears on the next successful connect. The help topic carries the same path as
  its item *Strava full? Take the file*, and /start/'s Strava card says it above the fold
  (`notice` in docs/guide/getting-started.json, rider review S5).
* **Strava's brand, used Strava's way** (developers.strava.com/guidelines, read 14 September
  2026; `ios/WingFoil/Features/Import/StravaBrand.swift`). Three rules, and breaking one can
  cost the application and with it a whole import door: (1) the connect action is **Strava's
  own button artwork**, unaltered and unrecoloured — the orange PNGs at 1× and 2× out of
  `1.1-Connect-with-Strava-Buttons.zip`, in the asset catalogue under `Strava/`, 48 pt tall,
  wearing Strava's wording *"Connect with Strava"* and not ours; (2) **attribution wherever
  Strava data is shown** — the *Compatible with Strava* logo sits in the Import screen's Strava
  section header, **beside** the section's own name and never above the CleanJibe mark, because
  the guideline is that Strava's logo may not be given more prominence than the app's own;
  (3) **a link back** — *View on Strava* on a Strava-imported session's Details tab, under the
  Recording card, in Strava orange `#FC5200`. The activity id it needs is read back out of the
  recording's own filename (`StravaImport.activityId`, the first field of
  `<id>_<slug>_strava.gpx`) rather than stored in a column of its own: the fact is already on
  the row, and a migration to duplicate it would backfill from this same string. A build whose
  asset catalogue has lost the artwork falls back to the same spec drawn by hand — `#FC5200`,
  white text, 48 pt — and never to a label of our own spelling.
* **Class (c), and the mark that follows from it.** A Strava session is positions-only, so
  every speed record it produces wears the `estimated` chip and the session badge names both
  absences. Nothing about that is special-cased: the mapper writes a GPX, and the rest of the
  app has never known the word Strava.

### Share from the vendor app straight into CleanJibe

The door for a rider whose watch is not a Garmin and not an Apple Watch. Every vendor's phone
app can export a recording as a file, and CleanJibe declares the UTIs for all three of them
(`ios/project.yml`: `de.lahmann.wingfoil.fit`, `.gpx`, `.tcx`, all `CFBundleDocumentTypes`), so
**Open in CleanJibe** appears in the iOS share sheet wherever one of them is offered. Save to
Files and sharing from there is the same path with one more step, and it is the fallback the
help names for the case where the app row is short.

One rule covers the choice of format: **take the FIT.** A FIT carries the receiver's own speed
and certifies; a GPX or a TCX carries positions and does not. Everything else — foil time,
flights, turns, the map, the wind axis — is identical either way.

The paths below are the help topic *Share from your watch app straight into CleanJibe*
(`HelpCatalog.shareFromWatchApp`), verified against the vendors' own current help pages on
**13 September 2026**. The date is a **comment over the items** in the catalogue rather than
part of what a rider reads (Jan, dev 70): a term that read *"Suunto, verified 13 Sep 2026"* is
a fact about the author printed where the reader is scanning for his own watch. The term is
the brand alone now — **Garmin, Suunto, COROS, Polar** — Garmin first because it is the
popular watch and the one answer nobody expects, and each caveat opens its own detail:
*"No phone export. On a computer: …"*, *"Not on the phone. On flow.polar.com: …"*. Anything
that could not be confirmed is still labelled unverified rather than dressed up:

| app | path | formats | verified |
|---|---|---|---|
| Suunto | Calendar → the workout → ⋯ top right → FIT | FIT, GPX (Workout), GPX (Route) | ✅ 13 Sep 2026 |
| COROS | Activities → the activity → ⋯ top right → Export → FIT | FIT, GPX (TCX/KML unverified) | ✅ 13 Sep 2026 |
| Polar | **not on the phone.** flow.polar.com → Diary → the session → Export → FIT | FIT, TCX, GPX, CSV | ✅ 13 Sep 2026 (web only; mobile Safari unverified) |
| Garmin | **no phone export at all.** connect.garmin.com on a computer → the activity → gear → Export File | original FIT (plus TCX, GPX, KML) | ✅ 13 Sep 2026 |

Garmin is the row that matters most, because it is the popular watch and the answer is "you
cannot do it from the phone": every export path Garmin documents begins with signing in to
connect.garmin.com in a browser. So the topic sends Garmin owners to the two doors that do work
without a computer — intervals.icu, or the CleanJibe watch app — and names the computer path
for completeness, with the current menu wording (**Export File**; the label read *Export
Original* until Garmin renamed it, and the Import screen's own footer still says the old words
where it describes that page).

### No watch at all — recording with a phone

The topic beside the vendor one (`HelpCatalog.phoneOnly`, *Recording with a phone only*), for
the rider who owns none of the three things this app has a door for. It answers the question
the vendor topic cannot: how the track gets recorded in the first place.

**It names no other platform and no other app, since 14 September 2026.** It used to list five
trackers by name, three of them Android ones — which App Store guideline 2.3.10 does not allow
an iOS app to do, and which the release walkthrough caught. The answer is the *kind* of app and
the file it writes: **any GPS-logging app on your phone that writes a .fit or a .gpx**. The one
name that stays is **Strava**, because it is a door in this app rather than a recommendation —
Strava's phone app cannot export a recording as a file, so connecting *is* the export, and it
is the one path that works in every channel. The file route is written in terms of the format
rather than the channel: CleanJibe reads a `.fit` everywhere, `.gpx` and `.tcx` open in the
public beta, and the sentence names Strava and intervals.icu as the route that works today —
because a release reader must not be told that the answer to his question is a build he does
not have. It says where the phone goes — a waterproof pouch on
the upper arm or high on the chest, not a hip pocket that spends the bottom of every jibe
underwater — and it says what it costs: positions only, so the speed is estimated.

### Which watches work with CleanJibe

One table, in the help (`HelpCatalog.whichWatch`), so "will my watch work" has one place to be
answered instead of a third of an answer in each of five topics. Two axes and nothing else:
**certified speed** (did the file carry the receiver's own speed) and **pump strokes and
takeoff effort** (was a wrist accelerometer recorded, which only the CleanJibe watch apps do).

| what you ride with | how it gets in | speed records | pump / takeoff effort |
|---|---|---|---|
| Garmin + the CleanJibe watch app | intervals.icu | certified | yes |
| Garmin, any other profile or app | intervals.icu, or the FIT from a computer | certified | no |
| Apple Watch (Workout app) | Strava or intervals.icu; Apple Health in the beta | certified where the watch's own speed came with it | no |
| Apple Watch + the CleanJibe watch app | straight to the phone (beta) | certified | yes |
| Polar / Suunto / COROS | intervals.icu, or a FIT through the share sheet | FIT certifies; GPX and TCX do not | no |
| Anything that reaches Strava | Import → Strava | estimated | no |
| A phone in a pocket | Strava, or the file: .fit anywhere, .gpx in the beta | estimated | no |

**Every row of it is true in every channel** (14 September 2026). The Bluetooth summary card
is a dev door and the Health import and the Apple Watch app are beta doors, so the rows that
used to promise them — *"or over Bluetooth as a summary the moment you stop"*, *"Import →
Apple Health"* — now either name the door that exists in every build or say plainly where
the other one lives. A `HelpTopic` body cannot branch on the channel (the catalogue is pure
data, and the channel-bound filtering is on the *index*), so a sentence in it has to be true
and complete everywhere: a fact about where a feature exists is allowed, a promise is not.

The **same table is public**, at cleanjibe.org/start#watches since 19 September 2026
(cleanjibe.org/watches until then, and a redirect to it since), beside one generated
sentence about the watch app’s Connect IQ product count — so “will my watch work” has one
answer for a rider who has installed nothing yet and the same answer inside the app. The
family-by-family product list **came back on 9 October 2026** (rider review S8: *"The store
says my fenix 6 is not compatible, and the site never says what to do then"*), generated
this time: `web/tools/make_devices.py` writes every watch by family from the three
manifests, with Garmin’s own device names, into docs/copy/garmin-devices.json (`models`)
and under the table, and ends on *Not on the list? Ride with Garmin's Windsurf profile. You
still get every verdict.* A watch added to the jungles with no name there fails the
generator. The public copy carries one column
this one does not: **what each kind of recording gets you** (Everything, Measured speed and
the wrist, Measured speed, Positions only — the classes a / b + wrist / b / c of
docs/channels.md, never printed as letters), as its own table above it — “what you need, what you get” — and repeated on the homepage,
since the question arrives before the import rather than after it. The CleanJibe Apple Watch
app is **b + wrist**: class b speed, plus the 50 Hz wrist accelerometer (ADR-016) the phone
analyses afterwards, which is why its row here says *yes* to pump and takeoff effort and
Apple's own Workout app does not. The public page also answers *no watch at all* with real
instructions: which phone apps record a track and can export it. The public release notes are
cleanjibe.org/whats-new (a page of its own again since 9 October 2026), generated from
`docs/copy/whats-new.json`.

**Where the public vocabulary lives, since 14 September 2026.** Jan: *"The entry web page is
quite long."* The homepage (`web/index.html`) is now the short half — the share card as the
hero, the three product names at one line each, the recording-class table, and the channel
lists — and everything a reader goes *looking* for moved to **cleanjibe.org/learn**
(`web/learn/index.html`): the three pieces in full, the FAQ, **"What it counts"** (the eleven
glossary entries and the track motif that is their key — the same four path strings the iOS
welcome screen and `web/tools/social_card.html` carry, character for character), and "How it
is built". **On 19 September 2026 that page went too**, and this time nothing was rewritten
on the web at all: cleanjibe.org/help is `HelpCatalog` rendered, out of `docs/copy/help.json`
by `web/tools/make_help.py`, opening with the same eleven glossary lines. /learn/ redirects
to /help/#numbers. A page that answers the app's questions in the website's own words is the
drift this file spent September ending. Nothing was reworded in the move, so every metric name on that page is still the
one this file fixes. Beta-channel features carry a small `beta` pill wherever they appear on
the site — the homepage pieces, /start, and /help, where the pill is written from the
exported topic's own `channels` — written from
`docs/channels.md` and from nowhere else, with one line of legend per page: *"beta: in the
public beta today, not yet in the App Store release."* Release features are unlabelled.

