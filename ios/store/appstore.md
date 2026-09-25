# App Store metadata — CleanJibe for iPhone

**The 1.0.1 listing, drafted for Jan's sign-off (26 September 2026).** ASC app
`6800401377`, bundle `de.lahmann.wingfoil`, version **1.0.1**. The subtitle, promotional
text, description, keywords and What's New blocks below are the **draft** in the team voice
of `docs/voice.md`, written against the release column of `docs/channels.md`. They are not
in App Store Connect yet. The 1.0.0 text they replace, which is what ASC last held, is in git
at `2c12c1c`, this file. 1.0.0 was pulled from review on 21 September and never went on sale,
so 1.0.1 is the first version the public sees. The app name, URLs, age rating, review notes
and privacy answers are unchanged from build 60, 15 September 2026.

The day Jan pastes the draft into ASC, this paragraph goes back to "a record of the live
listing", and `docs/copy/phrases.json` → `appStoreSubtitle` flips to the new subtitle in the
same commit.

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
Jibes, flights, speed records
```

Apple indexes name + subtitle + keywords as one bag, so the subtitle spends its words on
terms the name does not carry. **Jibes** replaced *turns* in the 1.0.1 draft: the name says
*CleanJibe* as one word, which the store's search does not split, so until now nothing in
the bag said *jibe* on its own — the word the app is named after and the one a rider types.
*Turns* is the app's umbrella word and nobody searches for it. *Flights* and *speed records*
stay: they are the product's vocabulary (docs/copy/glossary.json), the same words the rider
meets on the session page. A heading-like fragment is allowed here (docs/voice.md, rule 5).
Live 1.0.0 subtitle: `Flights, turns, speed records`.

## Promotional text

170-character limit. **153 used.** Editable without shipping a build — this is the
field to change when there is news, so keep it newsworthy rather than descriptive.

```
Your WingFoil session, measured. Did you fly through that jibe? CleanJibe gives every turn its verdict, and your sessions stay on your phone. It is free.
```

It opens with the tagline, `WelcomeGuide.headline` and `Branding.tagline` ("Your WingFoil
session, measured.", Jan, 23 September 2026), which is deliberate: the App Store card and the
app's first screen say the same five words. `docs/copy/phrases.json` → `headline` pins them.
The tagline is the one fragment the voice allows. The old one, "Every flight, every jibe,
every swim.", is retired everywhere. Then the promise's question, and two plain sentences.

## Description

4000-character limit. **3829 used.**

```
Did you fly through that jibe? CleanJibe reads your session off the watch. It tells you your time on the foil, every flight, your speed records, and a verdict on every turn. Flew through, touchdown, or fell in.

YOUR SESSION ON ONE PAGE

Open a session and the whole afternoon is there. Your track sits on the map with every flight, every turn and every takeoff marked. Tap a mark to see the numbers behind it.

Every turn has a page of its own. You see your speed through the turn and where the foil came down. The page also says why the verdict came out the way it did.

Clean jibes get a star. Clean means you flew through, held your speed, and stayed dry for 10 seconds after. Your clean jibes per hour sits beside your dry streak. Tacks get their own count.

Your nine speed records are drawn on the track and on the speed chart. They are best 2 s, best 10 s, 5 × 10 s, 100 m, 250 m and 500 m. Then come 1 NM, alpha 500 and best hour. Speeds read in knots or km/h, your choice.

Ride with the CleanJibe watch app on a Garmin and you also get your pump strokes and takeoff attempts.

Watch the session again as a replay, with commentary as it plays. Save a short clip with your own music and post it. The share card shows off the sessions worth showing. It carries your track and your numbers, with the map behind them if you like.

YOUR SEASON

Records and Trends read every session you have ridden. Your all-time bests sit in one table, and you can narrow it to one spot or one piece of gear. Trends draw your foil time, your longest flight and your jibes per hour across the months.

Send a session to a friend. It opens on their phone as your session and stays out of their own records.

HOW YOUR SESSIONS GET IN

Connect intervals.icu once in Settings, and every session arrives by itself. Garmin has no open API, so intervals.icu is the bridge. It is free.

You can also open a FIT file from Files, Mail or AirDrop, or share it to CleanJibe. A Garmin export ZIP brings in your whole history at once.

Strava works too. Pick a session from your feed and it comes in. Strava keeps the track but not the watch's speed measurement. Falls are harder to tell from touchdowns, and the speed records count as uncertified. Strava lets a new app connect a limited number of riders.

No session of your own yet? An example session from Lake Garda is built in. You can try every page before you connect anything.

WHICH WATCH

You get the most from the free CleanJibe watch app for Garmin. It is in open beta on the Connect IQ store. It records your wrist's movement, and that is where the pump strokes and takeoffs come from.

Any other recording with the watch's own speed works as well. Garmin's own Windsurf activity gives you everything except the pumping. A track with positions only still gives you flights, turns and uncertified speed records.

No iPhone at hand? The same analysis runs free in any browser at cleanjibe.org.

HOW IT WORKS

The watch records the session and your phone does the analysis. Every threshold behind a verdict is published, and the whole engine is open source at github.com/JanLahmann/WingFoil. If a jibe got the wrong verdict, you can read why and tell us.

YOUR SESSIONS STAY ON YOUR PHONE

There is no account and no CleanJibe server. Your sessions are never uploaded. There is no advertising, no analytics and no tracking.

The app never asks for your location. Every coordinate it shows was already in your file. It talks to intervals.icu and Strava only if you connect them, each with your own login. Apple draws the map and looks up the name of each new spot from one rounded coordinate. The full policy is at cleanjibe.org/privacy.

TELL US WHAT YOU SAW

We are wingfoilers too, and we read every mail. Menu → Support & ideas opens a mail to us with your app details already in it. Or write to info@cleanjibe.org.
```

The opening sentence is the product's one promise, and it is the same sentence the homepage,
the Connect IQ listing and the library's empty state say — `docs/copy/phrases.json` →
`promise`, pinned to `WelcomeGuide.promise` by `CopyContractTests`. The store's voice puts
its own paragraph around it; the sentence itself does not get a second wording.

**The order is the voice's rule 2: the rider first, the mechanics after.** The first four
sections are about the rider's session and season. *How your sessions get in*, *Which watch*
and *How it works* are for the interested rider: what comes from the watch and what from the
phone, and how it fits with Garmin, intervals.icu and Strava. Privacy and the way to reach
us close it. Every sentence is register 1, one thought, at most 20 words, no dash, no
semicolon, no parenthesis; `docs/copy/check_voice.py` reads this block. The section heads
are in capitals because the store field has no formatting of its own.

**Only release doors.** Everything named is in the release column of docs/channels.md: the
session page and its four tabs, turn pages, clean jibes, the nine GP3S records, units, pump
strokes and takeoffs for class a, replay and clips with music, the share card, Records and
Trends with the spot and gear menus, sending a session to a friend, intervals.icu, FIT from
Files, Mail, AirDrop and the share sheet, the Garmin export ZIP, Strava, the example
session, the feedback mail. Nothing from the beta or dev rows, and
`check_release_copy.py` holds that. *Windsurf* appears once, as Garmin's own activity
profile, the recording source the checker exempts by name.

**The Strava sentence** is `phrases.json` → `strava`, verbatim, with the Strava pair from
docs/voice.md's import example before it. **The Connect IQ watch app is named as a beta**,
because its public listing is one (docs/channels.md, "The watch — the same three streams").

## What's New in 1.0.1

4000-character limit. **1423 used.** Register 1, one line per change, release doors only.

```
This is the first CleanJibe on the App Store. Riders in the beta rode it all summer, and their sessions shaped it.

YOUR TURNS AND FALLS
A jibe you never got going again after counts as a fall, not a touchdown.
A touchdown only counts when you slow down right after coming off the foil.
Falls are read from the dunk itself. A watch that resets its height after a swim no longer turns your afternoon into falls.
Sessions recorded with Garmin's own activity show the full distance, as Garmin Connect does.
Tacks have their own count beside the jibes, on the session page and on the share card.
Clean jibes have their own tile with the star.

YOUR PAGES
Takeoffs and flight endings share one Flights tab.
Swipe left or right for the next or previous session.
Settings → Session list picks the three numbers each row shows.
Settings → Units puts every speed in knots or km/h, on the charts and on the card too.
Settings → Speed records decides whether records from a track without the watch's speed count.
Trends draw your jibes per hour, your turns per hour and your best 2 s.
The map offers Map or Satellite, and your track reads clearly on both.
VoiceOver reads every number with its word. Large text no longer breaks the list.

TELL US
The feedback mail has a list to tick. Tell us what you want most.
Menu → Join the beta shows what we are testing next.
Settings → About → Licences lists the open-source parts we build on.
```

**ASC may not offer this field.** 1.0.0 never went on sale, so 1.0.1 is the app's first
public version, and App Store Connect does not ask a first version for What's New. If the
field is offered, this is the text. It is written from `docs/copy/whats-new.json`, betas 93
to 111, keeping only the lines whose feature is in the release column: grouping, the rider
swipe and *Send to the developer* are beta and left out. The opening line says why a first
release has a list at all: the beta riders' summer is what it lists.

## Keywords

100-character limit, comma-separated, **no spaces after commas** (a space costs a character
and buys nothing). **99 used, 15 terms.**

```
wing,foil,gybe,tack,hydrofoil,windsurf,kitefoil,foiling,knots,gps,downwind,pump,watersport,fit,surf
```

Reasoning, since this is the field that is hardest to second-guess later:

* **Nothing here repeats the subtitle.** Apple indexes name + subtitle + keywords as one
  bag, so `jibe`, `flights`, `speed` and `records` are covered and would be wasted slots.
  The name is another matter in the 1.0.1 draft: *CleanJibe* and *Wingfoil* are single
  words, and the store is not known to split them, so `foil` is a keyword of its own now
  (it was assumed covered by *Wingfoil* until 26 September 2026), and *jibe* moved into the
  subtitle for the same reason.
* **`gps`, `pump` and `tack`** are what a rider types looking for a speed or a
  foiling-technique tool: GPS speedsurfing records, pump strokes on the takeoff, tacks
  counted apart from jibes. `session` left to make room; it matched every sport there is.
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

**1.0.1: `ios/store/screenshots/1.0.1/`, six 6.9-inch shots at 1320 × 2868, not yet taken.**
`shoot.sh` in that directory makes them in one run from the **release** scheme, in its own
simulator, which it deletes afterwards. It was written on 26 September 2026 at night, when
the Mac's screen was locked, and a locked screen hangs every `simctl launch`. The script
refuses to start while the screen is locked. Run it from the repo root on an unlocked Mac:
`ios/store/screenshots/1.0.1/shoot.sh`, about eight minutes.

| # | file | what it shows | hooks |
|---|---|---|---|
| 1 | `01-welcome.png` | the welcome screen, the tagline under the wordmark | `UI_WELCOME=1` |
| 2 | `02-session.png` | the session page: the track, the key numbers | `UI_OPEN_SESSION=latest` |
| 3 | `03-turns.png` | the Turns tab: every verdict, clean jibes, the dry streak | `+ UI_OPEN_TURNS=1` |
| 4 | `04-turn.png` | one turn's page, the speed through the turn and the why-line | `+ UI_OPEN_TURN=3` |
| 5 | `05-records.png` | the Records tab across the fixture corpus | `UI_TAB=records` |
| 6 | `06-share-card.png` | the share card with the map behind the track | `UI_SHEET=share UI_MAP=1 UI_STATS=complete` |

The library is the scrubbed fixture corpus plus the bundled example
(`UI_RESET=1 UI_IMPORT_FIXTURES=1 UI_LOAD_EXAMPLE=1`, once). Look at shot 4 before uploading:
turn 3 of the latest session should be one a rider wants to see, and another index is one
edit in the script. Apple accepts the 6.9-inch set alone and scales it down for every
smaller iPhone.

The 1.0 set in `ios/store/screenshots-1.0/` is from build 15 and shows words the app has
since changed, *swims per hour* and *clean-jibe percentage* among them. Do not upload it
again.

Every screenshot is of the **release** build. A screenshot of a door the release lacks is the
same broken promise as a sentence about one.

## Still to be produced

Things the App Store submission needs that are **not** in this repo:

* **What's New** is drafted above, for the case ASC offers the field to a first public
  version.
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
