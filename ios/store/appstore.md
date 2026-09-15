# App Store metadata — CleanJibe for iPhone

**A record of the live listing, not a draft of one.** ASC app `6800401377`, bundle
`de.lahmann.wingfoil`, version **1.0.0**. Every block inside a fence below is what is in App
Store Connect today, character for character; the prose around them is why, and what has yet
to be fixed. Written against **build 60, 15 September 2026**.

Edit App Store Connect and this file together, in that order or the other, but never one
alone — the live record is what a reviewer reads, and this file is what the next author
reads.

`testflight.md` remains the source of truth for the *TestFlight* fields (beta app
description, What to Test, beta review contact). The two files do not overlap: nothing in
here is a TestFlight field, and nothing there is an App Store field.

Locale: **en-US only.** No other localization is planned for 1.0.

---

## What this build is, and what it is not

The App Store build is the **release** channel (docs/channels.md): no compile flags, iPhone
only. Four things a reader of the older drafts of this file would expect are **not in it**,
and no line of the copy above may imply otherwise:

| not in the release | where it is | the rule |
|---|---|---|
| `.gpx` and `.tcx` import | beta | no document type, no parser path in the shipped binary |
| Apple Health, both ways | beta | **no HealthKit entitlement and no Health usage string** |
| The CleanJibe Apple Watch app, and the widgets and complication beside it | beta | **no watch extension and no widget extension embedded** |
| The Garmin link, windsurf, the tuning page, iPad | dev | a second app, a second ASC record |

`docs/copy/channels.json` holds that list as `forbiddenInRelease`, and
`python3 docs/copy/check_release_copy.py` asserts none of it appears in the blocks below.
The one place the doors *are* named is the review notes, which exist to tell the reviewer
what the Settings section he will find is for — see the exemption in the checker, and the
note under those notes.

## App name

30-character limit. **27 used.**

```
CleanJibe Wingfoil Analyzer
```

**Not the same name as the Connect IQ watch app.** That claim was in this file until
15 September 2026 and was never true of the live listings: the watch app's public listing is
*CleanJibe Wingfoil Tracker (Beta)* today, and docs/channels.md has decided it becomes
**CleanJibe Wingfoil Watch App Beta**, with the
release listing called **CleanJibe Wingfoil Watch App**. Two products, two names, and the
listings name each other in prose instead. `docs/copy/phrases.json` → `ciqListingTitle`
carries whatever the Connect IQ store actually shows, and flips on the day it changes.

*Analyzer* rather than *Tracker*: the app does not track anything — it never turns the GPS
on — and what it sells is the reading of a recording somebody else made. It is also the word
the browser tool and the watch listing's first sentence use for this app ("the watch app of
CleanJibe Wingfoil Analyzer for iPhone and browser"), so the family has one surname.

## Subtitle

30-character limit. **29 used.**

```
Flights, turns, speed records
```

Apple indexes name + subtitle + keywords as one bag, so the subtitle spends its words on
terms the name does not carry: *flights*, *turns*, *speed*, *records*. It is also the
product's own vocabulary (docs/copy/glossary.json), which is the point — a rider who reads
the subtitle and then opens the app meets the same three words on the session page.

## Promotional text

170-character limit. **145 used.** Editable without shipping a build — this is the
field to change when there is news, so keep it newsworthy rather than descriptive.

```
Every flight, every jibe, every swim from your wingfoil session - analysed on your phone, nothing uploaded, no account needed. Free, open source.
```

It is `WelcomeGuide.headline` ("Every flight, every jibe, every swim.") with the rest of the
sentence around it, which is deliberate: the App Store card and the app's first screen say
the same seven words. `docs/copy/phrases.json` → `headline` pins them.

## Description

4000-character limit. **3998 used.**

```
CleanJibe turns a wingfoil session into the numbers you actually argue about at the beach: how much of it you spent up on the foil, how long each flight lasted, your speed records, and - for every single turn - whether you flew through it, touched down, or fell in.

It reads the .fit file your watch recorded and re-analyses the whole thing on your phone. Nothing is uploaded, because there is nowhere to upload it to.

WHAT YOU GET

- Foil time and every flight: when the board was really flying, how long the longest one lasted, and how much of the session you spent off the water.
- A verdict on every turn: flew through, touched down, or fell in - with your dry streak, your clean jibes per hour, and the port/starboard split that tells you which side you are quietly avoiding.
- Speed records that mean something: best 2 s, best 10 s, 5 x 10 s, 100 m, 250 m, 500 m, 1 NM and Alpha 500, drawn on the track and on the speed chart so you can see where they happened. Records from a positions-only recording are estimated, and say so.
- The full track on a map, with the flown stretches, the pumping, the takeoffs and every turn marked - tap any of them to see the numbers behind it.
- A replay you can scrub through, with commentary as it plays, and short clips of it with your own soundtrack to post.
- A share card for the sessions worth showing: your track, your numbers, and an optional map behind it.
- All-time records and trends across everything you have ridden, filtered by spot and by gear.
- The gear you were on, session by session.
- Send a session to a friend: the recording travels with an invitation, and what they receive is kept out of their own records.

HOW SESSIONS GET IN

Sessions arrive on their own if you sync your watch to intervals.icu - paste your own key once in Settings and that is the last time you think about it. Or open a .fit file straight from Files, Mail, AirDrop or a message. Or connect Strava and pick a session from your feed: Strava carries positions only, so the speed records from it are estimates, marked as such - but every flight and every turn verdict is there.

An example session is bundled. You can see the entire app - map, verdicts, replay, share card, records - before importing anything or connecting anything.

WORKS WITH YOUR GARMIN, OR WITHOUT ONE

The most complete picture comes from the free CleanJibe Connect IQ watch app: it records the wrist accelerometer, which is what pump strokes and takeoff attempts are counted from. Any other recording with a proper GPS speed channel - Garmin's own Windsurf profile, another Connect IQ app - gives you everything but the pumping. A positions-only recording, from Strava or a phone in a pocket, gives you the flights, the turns and estimated records.

No Garmin at all? The same engine runs free in any browser at cleanjibe.org, from any watch's file.

ABOUT PRIVACY, PLAINLY

There is no account and no login. There is no CleanJibe server, so your sessions are not uploaded, not analysed remotely and not stored anywhere but your own phone. There is no advertising and no tracking of any kind - no analytics, no third-party SDK collecting anything. The app never asks for your location; every coordinate it shows was already inside a file you imported. The servers it can contact are intervals.icu and Strava, each with your own credential and only if you connect them, plus Apple: for the map when a map is on screen, and one rounded coordinate per new sailing spot to look up its name. Full policy: cleanjibe.org/privacy

OPEN SOURCE, AND ARGUED WITH

CleanJibe's verdicts were checked by riders against what actually happened on the water, and the detection thresholds moved because of it. Those thresholds are published - the whole engine is open source at github.com/JanLahmann/WingFoil - so if you think a jibe was scored wrong, you can read exactly why it was scored that way, and say so. Ideas and wishes are as welcome as bugs: Menu -> Support & ideas, or info@cleanjibe.org.
```

The opening sentence is the product's one promise, and it is the same sentence the homepage,
the Connect IQ listing and the library's empty state say — `docs/copy/phrases.json` →
`promise`, pinned to `WelcomeGuide.promise` by `CopyContractTests`. The store's voice puts
its own paragraph around it; the sentence itself does not get a second wording.

The turn-verdict bullet said "your no-fall streak" until 15 September 2026, 15:00; the live
description now says **dry streak**, the product's word (CLAUDE.md, `docs/copy/phrases.json` →
`lexicon`), and `check_release_copy.py` no longer carries an exemption for it.

## Keywords

100-character limit, comma-separated, **no spaces after commas** (a space costs a character
and buys nothing). **98 used, 14 terms.**

```
wing,wind,gybe,tack,hydrofoil,windsurf,kitefoil,foiling,knots,watersport,downwind,surf,fit,session
```

Reasoning, since this is the field that is hardest to second-guess later:

* **Nothing here repeats the name or the subtitle.** Apple indexes name + subtitle +
  keywords as one bag, so `wingfoil`, `foil`, `jibe`, `flights`, `turns`, `speed`,
  `records`, `analyzer` and `cleanjibe` are all already covered and would be wasted slots.
* **`wing` earns its place twice over.** Apple combines keywords into phrases, so `wing` +
  the name's `wingfoil` covers *"wing foil"* as two words — which is how a large part of the
  sport spells it, and which the one-word app name misses.
* **`gybe` is the British spelling** of the thing this app is named after. Leaving it out
  would lose every UK and Australian search.
* **`windsurf`** is a recording source, not a promise: Garmin's own Windsurf activity
  profile is a class B recording and the description says so. The *windsurf discipline* —
  foil and fin, with thresholds of its own — is a dev door and is named nowhere in this
  listing. `check_release_copy.py` carries that distinction as a written-down exemption.
* **`fit`** is there for *".fit file"*, which is what a Garmin owner types when they are
  looking for something to open one with. It will draw some irrelevant fitness traffic;
  that is an acceptable price for the searches it does catch.
* **`hydrofoil`, `kitefoil`, `foiling`, `downwind`, `surf`, `watersport`** are the adjacent
  sports whose riders record the same kind of session and are served by the same analysis.
* Not included, deliberately: competitor and brand names (against Apple guidelines), and
  plurals (Apple handles them).

## URLs and category

| ASC field | Value |
| --- | --- |
| Support URL | `https://cleanjibe.org/start/` |
| Marketing URL | `https://cleanjibe.org/` |
| Privacy Policy URL | `https://cleanjibe.org/privacy/` |
| Primary category | **Sports** |
| Secondary category | **Health & Fitness** |
| Price | Free, no in-app purchases |
| Copyright | `2026 Jan-Rainer Lahmann` |

The support URL is the **getting-started guide**, not the homepage: a rider who taps Support
has a problem getting a session in, and that page answers it route by route. The guide itself
is generated from `docs/guide/getting-started.json`, the same source the app's own *Getting
started* topic is cut from, so the page a reviewer lands on and the page in the app are one
guide.

Secondary category note: Health & Fitness is the honest second home — the app analyses effort
and heart rate out of the recordings it reads — but it is **not** a claim about Apple Health.
The release neither reads from nor writes to HealthKit, and the privacy label below says so.
Navigation and Utilities were considered and rejected: nobody looking for a wingfoil app
browses either.

## Age rating

Answer every questionnaire item **None / No**. The result is **4+**.

| Question | Answer |
| --- | --- |
| Cartoon or fantasy violence | None |
| Realistic violence | None |
| Prolonged graphic or sadistic realistic violence | None |
| Profanity or crude humor | None |
| Mature/suggestive themes | None |
| Horror/fear themes | None |
| Medical/treatment information | None |
| Alcohol, tobacco, or drug use or references | None |
| Simulated gambling | None |
| Sexual content or nudity | None |
| Graphic sexual content and nudity | None |
| Contests | None |
| Unrestricted web access | **No** — the app has no in-app browser. Links to cleanjibe.org and GitHub open in Safari; there is no field anyone can type a URL into. |
| Gambling and contests | No |
| Age Assurance / age verification | Not applicable |

## App Review Information

| ASC field | Value |
| --- | --- |
| Contact | Jan-Rainer Lahmann |
| Phone | `+49-172-7383481` |
| Email | `info@cleanjibe.org` |
| Demo account required | No |
| Attachment | one real `.fit` session in a zip — the same recording that ships as the bundled example |

## Review notes for Apple

The live "Notes" field of App Review Information.

```
CleanJibe analyses wingfoil sessions recorded by a GPS sports watch. It reads the .fit activity file and works out, on the device, how much of the session was spent flying on the hydrofoil, how long each flight lasted, the rider's speed records, and for every turn whether the rider flew through it, touched down, or fell in.

NO ACCOUNT AND NO LOGIN. There is nothing to sign up for and no demo credentials are needed. There is no server component of any kind.

HOW TO REVIEW WITHOUT ANY HARDWARE. A complete real session is bundled, so every feature can be exercised on a simulator or a plain iPhone with no watch and no files:
1. Launch the app. The welcome screen offers "Try the example session" - tap it. (If the welcome screen has been dismissed, the same button is on the empty Sessions tab, and under Menu > What CleanJibe does.)
2. The session opens on its summary: the numbers, the track on the map, the speed chart with the record markers, the replay with its scrubber.
3. The Turns section lists every turn's verdict; tapping one opens the turn page with the track and speed through the turn.
4. The share icon (top right) opens the share card composer - portrait, square or landscape, an optional map background - and the "Send to a friend" option.
5. "Record replay" saves a short clip of the replay to Photos (the app asks for add-only Photos access at that moment; in the Simulator the clip is empty by design).
6. Records, Trends and Gear fill from imported sessions; the bundled example is deliberately excluded from personal records, so with only the example those tabs show their empty state. Import the attached session (next paragraph) and Records fills; Trends needs sessions across more than one month.

IMPORTING A FILE. The attached zip holds a real .fit session (the same one that is bundled as the example). Unzip it, then open the .fit from Files, Mail or AirDrop, or share it to CleanJibe; the app reads it and shows the same pages as the example.

THIRD-PARTY SERVICES ARE OPTIONAL. Settings offers a field for an intervals.icu API key (an independent training-analysis service; the key is the user's own and the app only downloads that user's own activity files) and a "Connect with Strava" button (OAuth in the system browser, read scope; the user picks their own activities to import). Strava caps a new app at ten connected riders until it has reviewed the app, which Strava only does once the cap is reached; if your test connection is refused as "full", that is Strava's cap, not a defect, and the app says so. Both are inert until the user sets them up and nothing is uploaded to either. Reviewing these paths is not necessary; the bundled example and the attached file cover everything.

PERMISSIONS. Photos, add-only, only when saving a recorded replay clip. Notifications, only if the user enables the optional background check for new intervals.icu activities. The app never requests location: all GPS shown comes from inside the imported files. No Health, no Bluetooth.

THE "COMING IN A FUTURE RELEASE" SECTION in Settings lists features that are in our public TestFlight beta and not in this release (GPX/TCX files, Apple Health, an Apple Watch app, home-screen widgets, video export, grouping and filtering of the library). It links to the TestFlight public link. This release is complete on its own; the section only tells the user where those features are being tested.

The bundled example is one of the developer's own sessions, stripped of all identifying data before shipping. The app is open source: github.com/JanLahmann/WingFoil.

Questions: info@cleanjibe.org
```

**These notes may name the beta doors, and must.** They exist to explain a section the
reviewer will find in Settings, and a section that lists features the build does not have
reads as a bug until somebody says what it is for. `check_release_copy.py` allows the door
names in this block only, by name, with the reason written down beside them — nowhere else
in the listing.

Both were corrected in App Store Connect on 15 September 2026, 15:00: the notes name the
section **"Coming in a future release"** (`docs/copy/channels.json` → `sectionTitle`) and the
beta list includes grouping and filtering of the library.

Neither is worth a new build. Both are one edit in the ASC text field.

## App Privacy — nutrition label answers

For the coordinator to click into ASC → App Privacy. Every answer below was checked against
the **release** target's own sources, entitlements and usage strings, not assumed. The short
version: **nothing is collected, because there is no server to collect it to** — but Apple's
definition of "collect" covers data transmitted off the device even transiently, so the
honest answers are not all "no".

**Top-level questions**

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **Yes** — see the one row below. Answering "No" would be wrong the moment a coordinate reaches Apple's geocoder. |
| Is any data used to track you (as Apple defines tracking)? | **No.** No ATT prompt, no IDFA, no advertising, no data broker, no linking to third-party data. |

**Data types — Data Not Linked to You**

The row is *Not Linked*: the app has no account, no user id, no device identifier it stores
or transmits, and nothing that could tie a session to a person.

| Data type | Collected | Purpose | Linked to identity | Used for tracking | Why |
| --- | --- | --- | --- | --- | --- |
| **Location → Precise Location** | Yes | App Functionality | **No** | **No** | The coordinates are already inside the file the user imports. They leave the device in only two ways: map imagery is fetched from Apple Maps for the area being displayed, and one rounded coordinate per new sailing spot goes to Apple's geocoder for a place name. The app holds no location permission and never turns on the phone's GPS. |

**Health & Fitness is NOT declared, and must not be.** It was in the 2 September draft of
this file, and it followed from a HealthKit path the release channel does not build: the
App Store target has no HealthKit entitlement, no `NSHealthShareUsageDescription`, no
`NSHealthUpdateUsageDescription` and no Import → Apple Health screen. Declaring a data type
the binary cannot reach is a false statement on the nutrition label. It becomes true, and
gets declared, on the day Apple Health graduates out of the beta (docs/channels.md).

**Data types — explicitly NOT collected**

Answer "No" to every one of these: Contact Info, Health & Fitness, Contacts, User Content,
Search History, Browsing History, Identifiers, Purchases, Financial Info, Usage Data,
Diagnostics, Sensitive Info, Other Data.

Two of those deserve a note, because a careful reader will wonder:

* **User Content** — the user types session titles, captions, gear and spot names, and can
  pick photos and music for a replay clip. None of it is *collected*: it is written to the
  local database and never transmitted. Apple's definition turns on transmission off the
  device, so the answer is No.
* **Usage Data / Diagnostics** — there is no analytics SDK and no crash reporter in the app.
  The usage counters are a **beta** feature and never leave the phone except inside a mail
  the rider composes and edits himself. (The `umami` counter mentioned in the privacy policy
  is on the **website only** and is not part of the app. Do not declare it here.) Apple's own
  crash reporting, which the user opts into at the OS level, is not the developer's
  declaration to make.

**Permissions the release actually asks for**, which is the list the review notes give and
the shortest check on everything above: **Photos**, add-only, only when saving a recorded
replay clip; **Notifications**, only if the rider switches on the background check for new
intervals.icu activities. No Health, no Bluetooth, no Location.

**Privacy policy URL for this section:** `https://cleanjibe.org/privacy/`

The app links that page too, since build 60: Settings → About → Privacy, and the help topic
*What leaves your phone*. docs/channels.md makes privacy-page coverage one of the four rules
a feature meets before it moves up a channel, and until then the page described the app's
behaviour to everyone except the rider holding it.

---

## Screenshots

`ios/store/screenshots-1.0/` — eight 6.9-inch iPhone screenshots at 1320 × 2868, unframed,
in submission order, plus one alternate. See the README in that directory for what each
one shows and the exact command that produced it. Apple accepts the 6.9-inch set alone and
scales it down for every smaller iPhone, so no second size is needed.

Every screenshot is of the **release** build. A screenshot of a door the release lacks is the
same broken promise as a sentence about one.

## Still to be produced

Things the App Store submission needs that are **not** in this repo:

* **What's New text for 1.0** — not written, because a first public release has no "what's
  new". ASC does not require it for a first version; if the field is offered, the
  Promotional Text above is the right thing to adapt.
* **Export compliance** — the app uses only HTTPS via the system frameworks, which is the
  standard exemption. Expect to answer: uses encryption **Yes**, exempt **Yes** (only
  standard encryption within the OS).
* **Content Rights** — the app contains no third-party content. The bundled example session
  is the developer's own.
* **`PrivacyInfo.xcprivacy`** — the app target does not currently ship a privacy manifest.
  Not blocking (no signature-required SDK is used), but worth adding before submission: it
  should declare `NSPrivacyTracking: false`, an empty collected-data array, and a
  required-reason entry for `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`). Filed
  here rather than fixed, because it is a build change and this was a metadata task.
