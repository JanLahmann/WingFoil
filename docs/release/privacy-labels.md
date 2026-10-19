# App Store Connect — App Privacy answers (1.0.1)

**Jan's decisions, 19 October 2026** — the three judgment calls, settled:

1. **The label describes the App Store (release) build only.** TestFlight builds need no
   label and carry their own privacy manifest (`ios/WingFoil/Privacy/Beta/`). Beta and dev
   doors — Ask CleanJibe, the umami counts, Apple Health, the Garmin link over Bluetooth,
   the "Where I am now" location prompt — are not on it, and each is added the day it moves
   into the release (docs/channels.md, the fourth rule).
2. **Location: Precise Location, Collected, Not Linked to You, App Functionality.** The spot
   name lookup rounds to three decimals (~110 m), which Apple counts as precise.
3. **The feedback mail is not declared**, under Apple's optional-disclosure exception: it is
   rare, optional, not part of the app's main job, and the rider sees every word in the mail
   compose sheet and sends it himself, from his own account.

`ios/store/appstore.md` → "App Privacy — nutrition label answers" is the click-through for
ASC; this file is the evidence behind it. The two say the same thing; edit them together.

**Method.** Apple's definition: "collect" means data leaves the device and is kept somewhere
readable for longer than it takes to answer the request. CleanJibe runs no server, so data
that stays on the phone, and data the rider moves between his own accounts, is not
collected. **Tracking is No everywhere**: no advertising, no IDFA, no data broker, no ATT
prompt.

## Top-level answers

| Question | Answer |
|---|---|
| Do you or your third-party partners collect data from this app? | **Yes** — Location, the one row below. |
| Is any data used to track you? | **No.** |

## Data Not Linked to You

| Data type | Purpose | Why |
|---|---|---|
| **Location → Precise Location** | App Functionality | The coordinates come from the files the rider imports; the release asks for no location permission and never turns on GPS. They leave the phone twice, both to Apple: MapKit fetches the map for the area on screen (`ios/WingFoil/Features/Share/ShareCardMap.swift`), and one coordinate rounded to three decimals per new spot goes to Apple's geocoder for a place name (`ios/WingFoilKit/Sources/WingFoilKit/Persistence/SpotNaming.swift`, `roundedForLookup`). |

Nothing goes under **Data Linked to You**.

## Not collected — answer No

Contact Info, Health & Fitness, Financial Info, Contacts, User Content, Browsing History,
Search History, Identifiers, Purchases, Usage Data, Diagnostics, Sensitive Info, Other Data.

The ones a reviewer may ask about:

| Data type | Why it is No |
|---|---|
| **Contact Info, Diagnostics, Identifiers** — the feedback mail | *Send feedback* opens a mail to info@cleanjibe.org with the phone model, iOS version, locale, the on-phone usage counts and, if there is one, a MetricKit crash summary (`ios/WingFoil/Features/Feedback/FeedbackMail.swift`, `ios/WingFoil/App/CrashDiagnostics.swift`). The rider reads it and sends it himself; that reply carries his address. Optional disclosure (decision 3). If App Review insists, the answer is **Contact Info → Email Address, Linked, App Functionality** plus **Diagnostics → Other Diagnostic Data, Not Linked, App Functionality**. |
| **Usage Data** | The usage counts stay on the phone except inside that mail. The release target compiles no umami sender and ships an empty manifest (`ios/WingFoil/Privacy/Release/PrivacyInfo.xcprivacy`, held by `tools/check_release.py`). |
| **Health & Fitness** | No HealthKit entitlement and no Health usage string in the release. The heart rate inside an imported FIT, Strava or intervals.icu activity is analysed on the phone and never sent anywhere. |
| **User Content** | Titles, captions, gear and spot names, and replay clips live in the app's own database. Saving to Photos is add-only. Nothing is uploaded. |
| **Identifiers** — Strava and intervals.icu | The rider's own accounts: the app reads his activities down to the phone. The intervals.icu key, which he types in, is sent only to intervals.icu. CleanJibe writes nothing to either. |
| **Crash Data** | No crash SDK. Apple's own crash reports, which the rider opts into in iOS settings, are Apple's disclosure. |

## Permissions in the release binary

**Photos** (add-only, when saving a replay clip) and **Notifications** (only if the rider
switches on the background check for new intervals.icu activities). No Location, Health or
Bluetooth.

## When a beta door moves to the release

Its rows join this label in the same change (docs/channels.md). Prepared answers:

- **umami counts**: Usage Data → Product Interaction, Not Linked, Analytics; switch the
  release to the beta manifest (`ios/store/appstore.md` has the steps).
- **Ask CleanJibe**: User Content → Other User Content (the question) and Other Data (the
  session's numbers), Not Linked, App Functionality. It is kept 30 days by the assistant
  Worker (Cloudflare, Anthropic); an idea is kept a year.
- **"Where I am now"** (Location When In Use): Precise Location is already declared. Add the
  permission and check that its usage string matches.
- **Apple Health, the Garmin link over Bluetooth**: on the phone only, nothing to add.

## The dev app record (`de.lahmann.wingfoil.dev`)

The dev app never goes to the App Store, so its record needs no label as long as it stays on
TestFlight.
