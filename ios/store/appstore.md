# App Store metadata — CleanJibe for iPhone

Source of truth for the **public App Store** listing. ASC app `6800401377`, bundle
`de.lahmann.wingfoil`. Edit here first, then push the same text to App Store Connect so the
two never drift — the same rule `testflight.md` follows for the beta fields.

`testflight.md` remains the source of truth for the *TestFlight* fields (beta app
description, What to Test, beta review contact). The two files do not overlap: nothing in
here is a TestFlight field, and nothing there is an App Store field.

Status: **prepared, not submitted.** Nothing in this file has been entered into ASC yet.
Written against 0.13.0 build 15, the current TestFlight build.

Locale: **en-US only.** No other localization is planned for 1.0.

---

## App name

30-character limit. **26 used.**

```
CleanJibe Wingfoil Tracker
```

The same name the Connect IQ watch app carries, minus the beta suffix, so a rider who finds
one store listing recognizes the other. "Wingfoil" and "Tracker" are both indexed for
search, which is why the bare brand is not enough on its own.

## Subtitle

30-character limit. **27 used.**

```
Foil time, jibes, GPS speed
```

Chosen over the two candidates parked in `testflight.md` (`Wingfoil sessions, measured`,
`Foil time, flights, jibes`) on one argument: Apple indexes the subtitle for search, and
those two spend their words on terms the app name already carries. This one adds four that
it does not — *foil*, *jibes*, *GPS*, *speed* — and still says what the app is. Keep the
alternates on file; if the listing is ever rewritten to lead with tone rather than search,
`Wingfoil sessions, measured` is the one to use.

## Promotional text

170-character limit. **137 used.** Editable without shipping a build — this is the field to
change when there is news, so keep it newsworthy rather than descriptive.

```
Out of beta. Every flight, every jibe, every swim from your Garmin session - analysed on your phone, nothing uploaded, no account needed.
```

## Description

4000-character limit. **3482 used.** Leads with what it does, says the beta graduation
plainly rather than hiding it, then the three pieces, then the privacy story.

```
CleanJibe turns a wingfoil session into the numbers you actually argue about at the beach: how much of it you spent up on the foil, how long each flight lasted, your speed records, and - for every single turn - whether you flew through it, touched down, or fell in.

It reads the .fit file your Garmin recorded and re-analyses the whole thing on your phone. Nothing is uploaded, because there is nowhere to upload it to.

WHAT YOU GET

- Foil time and every flight: when the board was really flying, how long the longest one lasted, and how much of the session you spent off the water.
- A verdict on every turn: flew through, touched down, or fell in - with your no-fall streak, your clean-jibe percentage, and the port/starboard split that tells you which side you are quietly avoiding.
- Speed records that mean something: best 2 s, best 10 s, 5 x 10 s, 100 m, 250 m, 500 m, 1 NM and Alpha 500, drawn on the track and on the speed chart so you can see where they happened.
- The full track on a map, with the flown stretches, the pumping, the takeoffs and every turn marked - tap any of them to see what the numbers behind it were.
- A replay you can scrub through, with commentary as it plays, and which you can record as a video with your own soundtrack to post.
- A share card for the sessions worth showing: your track, your numbers, and an optional map behind it.
- All-time records and season trends across everything you have ridden, filtered by spot and by gear.
- The gear you were on, session by session, so you can tell the board from the rider.

HOW SESSIONS GET IN

Sessions arrive on their own if you sync your Garmin to intervals.icu - paste your own key once in Settings and that is the last time you think about it. Or open a .fit or .gpx file straight from Files, Mail or a message: your own, or one a friend sent you, which is kept out of your own records.

An example session is bundled. You can see the entire app - map, verdicts, replay, share card, records - before importing anything or connecting anything.

WORKS WITH YOUR GARMIN, OR WITHOUT ONE

CleanJibe reads sessions recorded with the free CleanJibe Connect IQ watch app and with Garmin's own Windsurf profile. Pump strokes and takeoff effort need the CleanJibe watch app, because only it records the wrist accelerometer; everything else works from either.

No Garmin at all? The same analysis engine runs free in any browser at cleanjibe.org - which is also the Android answer, because it is a web page and not an app.

ABOUT PRIVACY, PLAINLY

There is no account and no login. There is no CleanJibe server, so your sessions are not uploaded, not analysed remotely and not stored anywhere but your own phone. There is no advertising and no tracking of any kind - no analytics, no crash reporter, no third-party SDK collecting anything. The app never asks for your location; every coordinate it shows was already inside a file you imported. The only server it ever contacts is intervals.icu, with your own key, to download your own activities - and only if you set that up. Full policy: cleanjibe.org/privacy

OUT OF BETA

CleanJibe spent its beta being argued with by riders who checked its verdicts against what actually happened on the water, and the detection thresholds moved because of it. Those thresholds are published - the whole engine is open source at github.com/JanLahmann/WingFoil - so if you think a jibe was scored wrong, you can read exactly why it was scored that way, and say so.
```

## Keywords

100-character limit, comma-separated, **no spaces after commas** (a space costs a character
and buys nothing). **98 used, 15 terms.**

```
wing,wind,gybe,tack,hydrofoil,windsurf,kitefoil,garmin,knots,watersport,downwind,sup,surf,fit,sail
```

Reasoning, since this is the field that is hardest to second-guess later:

* **Nothing here repeats the name or the subtitle.** Apple indexes name + subtitle +
  keywords as one bag, so `wingfoil`, `foil`, `jibe`, `speed`, `gps`, `tracker` and
  `cleanjibe` are all already covered and would be wasted slots.
* **`wing` earns its place twice over.** Apple combines keywords into phrases, so `wing` +
  the subtitle's `foil` covers *"wing foil"* as two words — which is how a large part of the
  sport spells it, and which the one-word app name misses.
* **`gybe` is the British spelling** of the thing this app is named after. Leaving it out
  would lose every UK and Australian search.
* **`fit`** is there for *".fit file"*, which is what a Garmin owner types when they are
  looking for something to open one with. It will draw some irrelevant fitness traffic;
  that is an acceptable price for the searches it does catch.
* **`sup`, `surf`, `downwind`, `kitefoil`, `hydrofoil`** are the adjacent sports whose
  riders record the same kind of session and are served by the same analysis.
* Not included, deliberately: competitor and brand names (against Apple guidelines),
  `foiling` (`foil` in the subtitle should stem to it), and plurals (Apple handles them).

## URLs and category

| ASC field | Value |
| --- | --- |
| Support URL | `https://cleanjibe.org` |
| Marketing URL | `https://cleanjibe.org` |
| Privacy Policy URL | `https://cleanjibe.org/privacy/` |
| Primary category | **Sports** |
| Secondary category | **Health & Fitness** |
| Price | Free, no in-app purchases |
| Copyright | `2026 Jan-Rainer Lahmann` |

Secondary category note: Health & Fitness is the honest second home — the app writes
workouts to the Health app and shows session-level effort — and it does not commit us to
anything, since the app declares no required-reason API beyond `UserDefaults` and uses
HealthKit write-only. Navigation and Utilities were considered and rejected: nobody looking
for a wingfoil app browses either.

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

## Review notes for Apple

Paste into the "Notes" field of App Review Information.

```
CleanJibe analyses wingfoil (and windsurf) sessions recorded by a GPS sports watch. It reads a .fit or .gpx activity file and works out, on the device, how much of the session was spent flying on the hydrofoil, how long each flight lasted, the rider's speed records, and whether each turn was completed cleanly or ended in a fall.

NO ACCOUNT AND NO LOGIN. There is nothing to sign up for and no demo credentials are needed. There is no server component of any kind.

HOW TO REVIEW WITHOUT ANY HARDWARE. A complete real session is bundled in the app, so every feature can be exercised on a simulator or a plain iPhone with no watch and no files:

1. Launch the app. The welcome screen offers "Try the example session" - tap it. (If the welcome screen has already been dismissed, the same button is on the empty Sessions tab, and the session is also listed under Help.)
2. The session opens on the Map / Speed view: the track, the speed chart, the replay scrubber, foil time and the speed-record table.
3. The Turns tab shows the per-turn verdicts and the drill-in for each turn. Takeoffs and Effort are the other two tabs.
4. Tap the share icon (top right) for the share card composer - shape, stat preset and an optional map background.
5. "Record replay" on the Map / Speed view opens the full-screen replay. Note that screen recording produces an empty file in the Simulator; on a real device it writes a video.
6. The Records and Trends tabs are populated once more than one session is present; with only the bundled example they are empty by design, because the example is deliberately excluded from personal records.

The bundled example is one of the developer's own sessions, stripped of all identifying data (watch serial, user profile, paired accessories) before shipping.

INTERVALS.ICU IS OPTIONAL. Settings offers a field for an intervals.icu API key. intervals.icu is an independent third-party training-analysis service; the key is the reviewer's or user's own, obtained from their own intervals.icu account, and it is used only to DOWNLOAD that user's own activity files. It is stored in the iOS Keychain. The app uploads nothing to it. Reviewing this path is not necessary - the feature is inert without a key, and the bundled example covers everything else.

PERMISSIONS. Health (write-only, off by default, for exporting a session as a workout), Photos (add-only, only when saving a recorded replay video), Bluetooth (to receive a session summary from a Garmin watch via the Garmin Connect app), and Notifications (only if the user enables the optional background check for new activities). The app never requests location: all GPS shown comes from inside the imported files.

WATCH APP. An Apple Watch target is present in the bundle. It is not being announced or marketed in this release and is not featured in any screenshot or copy. It ships two small surfaces of its own, also unannounced: a watch-face complication (circular, corner and rectangular) whose only action is to start a recording, and two Siri phrases that do the same thing hands-free ("Start a CleanJibe session", "Stop my CleanJibe session"). Both are launchers. Neither displays any analysis result, because the watch computes none - all analysis happens on the iPhone after the recording is transferred. Reviewing them needs a paired Apple Watch and is not necessary to review the app.

Questions: info@cleanjibe.org
```

## App Privacy — nutrition label answers

For the coordinator to click into ASC → App Privacy. Every answer below was checked against
the source, not assumed. The short version: **nothing is collected, because there is no
server to collect it to** — but Apple's definition of "collect" covers data transmitted off
the device even transiently, so the honest answers are not all "no".

**Top-level questions**

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **Yes** — see the two rows below. Answering "No" would be wrong the moment a coordinate reaches Apple's geocoder. |
| Is any data used to track you (as Apple defines tracking)? | **No.** No ATT prompt, no IDFA, no advertising, no data broker, no linking to third-party data. |

**Data types — Data Not Linked to You**

Both rows are *Not Linked*: the app has no account, no user id, no device identifier it
stores or transmits, and nothing that could tie a session to a person.

| Data type | Collected | Purpose | Linked to identity | Used for tracking | Why |
| --- | --- | --- | --- | --- | --- |
| **Location → Precise Location** | Yes | App Functionality | **No** | **No** | The coordinates are already inside the file the user imports. They leave the device in only two ways: map imagery is fetched from Apple Maps for the area being displayed, and one rounded coordinate per new sailing spot goes to Apple's geocoder for a place name. The app holds no location permission and never turns on the phone's GPS. |
| **Health & Fitness → Fitness** | Yes | App Functionality | **No** | **No** | Session metrics, and heart rate where the imported file carries it. Written to Apple Health only if the user turns workout export on. Never transmitted anywhere by us. |

**Data types — explicitly NOT collected**

Answer "No" to every one of these: Contact Info, Contacts, User Content, Search History,
Browsing History, Identifiers, Purchases, Financial Info, Usage Data, Diagnostics,
Sensitive Info, Other Data.

Two of those deserve a note, because a careful reader will wonder:

* **User Content** — the user types session titles, captions, gear and spot names, and can
  pick photos and music for a replay clip. None of it is *collected*: it is written to the
  local database and never transmitted. Apple's definition turns on transmission off the
  device, so the answer is No.
* **Usage Data / Diagnostics** — there is no analytics SDK and no crash reporter in the app.
  (The `umami` counter mentioned in the privacy policy is on the **website only** and is not
  part of the app. Do not declare it here.) Apple's own crash reporting, which the user
  opts into at the OS level, is not the developer's declaration to make.

**Privacy policy URL for this section:** `https://cleanjibe.org/privacy/`

---

## Screenshots

`ios/store/screenshots-1.0/` — eight 6.9-inch iPhone screenshots at 1320 × 2868, unframed,
in submission order, plus one alternate. See the README in that directory for what each
one shows and the exact command that produced it. Apple accepts the 6.9-inch set alone and
scales it down for every smaller iPhone, so no second size is needed.

## Still to be produced

Things the App Store submission needs that are **not** in this repo:

* **What's New text for 1.0** — not written, because a first public release has no "what's
  new". ASC does not require it for a first version; if the field is offered, the
  Promotional Text above is the right thing to adapt.
* **App Review contact** — name, phone and email, entered directly in ASC (`testflight.md`
  records the beta contact as Jan-Rainer Lahmann / `jan@lahmann-online.de`).
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
