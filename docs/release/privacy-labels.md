# App Store Connect — App Privacy answers (1.0.1)

Draft answers for the "App Privacy" questionnaire, ready for Jan to click in. Written against
the tree behind release build 1.0.1 / beta 1.1.x, from the same audit that fixed
`web/privacy/index.html` (see that page's "What leaves your phone" for the rider-facing
version of every fact below — this file is the same facts, in Apple's own categories).

**One app record, two builds.** Release and beta (`de.lahmann.wingfoil`) share one App Store
Connect app, so one privacy label has to describe both — the release build's doors *and* the
beta doors, even though a release-channel rider never compiles the beta code that opens some
of them. Every row below says which channel it comes from. The dev channel
(`de.lahmann.wingfoil.dev`) is a separate app record and gets its own short section at the
end.

**Method.** Apple's own definition: "collect" means data leaves the device *and* is kept
somewhere readable for longer than it takes to answer the request — yours or a third
party's. Data that never leaves the device is not collected, full stop. Data that leaves the
device only to be handed straight to Apple's own frameworks (MapKit, `CLGeocoder`,
MetricKit), in a request-response round trip nothing of ours retains, is Apple's collection
to disclose, not ours. That rule does almost all of the work below: CleanJibe runs no server,
so the honest answer for most rows is **Not Collected**. Every row still gets its evidence —
the file and the sentence on the privacy page it backs — so the "no" is checkable, not
assumed. **Tracking is No on every row** — the app has no advertising, no data broker, no
cross-app identifier, and has never shown the App Tracking Transparency prompt because it has
nothing to ask that prompt for.

Data types the app has no relationship to at all, so they carry no row: Contacts, Sensitive
Info, Financial Info, Purchases, Browsing History, Search History, Surroundings, Body, Audio
Data, Gameplay Content, Emails or Text Messages (the app *opens* a mail compose sheet; it does
not read or send mail itself — see the Identifiers/Diagnostics rows for what ends up
typed into one).

## The data type table

| Data type | Collected? | Linked to you? | Used to track? | Channel | Why |
|---|---|---|---|---|---|
| **Location — Coarse** | **Not Collected** | — | No | release + beta | A rounded spot centre (~110 m) goes to Apple's geocoder to name a spot, and a rounded box goes to MapKit to draw a map or a watch coastline. Both are real-time requests to Apple's own frameworks; nothing is retained by CleanJibe past the answer, and Apple's own collection is Apple's to disclose, not ours (`ios/WingFoilKit/Sources/WingFoilKit/Persistence/SpotNaming.swift`, `ios/WingFoil/Features/Share/ShareCardMap.swift`, `ios/WingFoil/Companion/WatchMapSender.swift`). **Flag for Jan**: this is the one row App Review most often asks a second question about, because the app also shows a system location prompt (beta/dev only, When In Use) — see the Location permission note below the table. |
| **Location — Precise** | Not Collected | — | No | — | Never requested or read at that precision; the one location read (beta/dev, "Where I am now") is used exactly like the coarse row above and never stored with a session. |
| **Health & Fitness — Fitness** | Not Collected | — | No | beta only | `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription` exist only in the beta/dev target. A workout's route and heart rate are read from, or written to, Apple Health entirely on-device; nothing is ever transmitted (`ios/WingFoil/Features/Settings/SettingsView.swift` healthSection; privacy page, "Health — both directions"). Release has no HealthKit entitlement at all. |
| **Identifiers — User ID / Device ID** | Not Collected | — | No | release + beta | No account, no installation identifier of ours anywhere. The feedback mail *prints* the phone model, iOS version and locale into a mail the rider composes and sends himself, through his own Mail account — that is the rider handing Jan a fact by email, not the app transmitting it to a server CleanJibe or a partner operates, so it falls outside Apple's definition of collection. **Flag for Jan**: this is a judgment call rather than a hard rule; if you would rather declare it, the honest label is "Diagnostics — Other Diagnostic Data, Not Linked to You, App Functionality," never Identifiers (`ios/WingFoil/Features/Feedback/FeedbackMail.swift`). |
| **Diagnostics — Crash Data** | Not Collected | — | No | release + beta | No crash SDK, no server. Two things exist and neither is "collected" under Apple's rule: (1) TestFlight's own crash collection is Apple's infrastructure, running only under beta/dev distribution, ending the day a build leaves TestFlight (privacy page, "TestFlight — crash reports"); (2) `MXMetricManager` diagnostics are kept in a file inside the app's own container and only ever leave the phone if the rider composes and sends a feedback mail — the same voluntary-email argument as the Identifiers row above (`ios/WingFoil/App/CrashDiagnostics.swift`). **Flag for Jan**: same judgment call as above; if in doubt, declaring "Diagnostics — Crash Data, Not Linked to You, App Functionality" is the conservative answer and is never wrong to pick. |
| **Usage Data — Product Interaction** | Not Collected | — | No | release + beta | No analytics SDK in the app (the website's umami counter is a separate product, `web/`, and is already disclosed on the privacy page's "website" half — it does not touch the app). **Since 17 Oct 2026 every channel counts feature use on the phone** (`App/Usage.swift`, one mail one sheet) and the counts leave it only inside a feedback mail the rider writes, reads and sends, the same voluntary-email argument as the Identifiers row. **Flag for Jan**: if in doubt, "Usage Data — Product Interaction, Not Linked to You, App Functionality / Analytics" is the conservative answer. |
| **User Content — Photos or Videos** | Not Collected | — | No | release + beta | Save-to-Photos is add-only (the app cannot read the library back); a photo picked to splice into a clip arrives from the system picker already selected, is composited on-device, and nothing is uploaded (`ios/WingFoil/Features/SessionDetail/ReplayCinemaView.swift`; privacy page, "Photos — add only"). |
| **User Content — Other User Content** | Not Collected | — | No | release + beta | The session library (tracks, names, captions) lives in the app's own SQLite file and file archive and is never transmitted, except: (a) to Strava/intervals.icu, under the rows below, which are the rider's own accounts; (b) attached to a mail the rider composes and sends himself ("Send this session to us", beta). Same voluntary-email reasoning as the Identifiers row. |
| **Health & Fitness / Fitness, via Strava** | Not Collected | — | No | release | Connecting Strava reads the rider's *own* Strava activities — track, heart rate, elevation, clock — down to the phone, for analysis there. Nothing is sent *to* Strava beyond the OAuth handshake and the read requests themselves (privacy page, "Strava"). Apple's own guidance treats a read-only pull through the user's own third-party account, with nothing retained by a server of ours, the same as the intervals.icu row: not a collection this app makes. |
| **Identifiers — via intervals.icu** | Not Collected | — | No | release + beta | The rider's own API key, typed in by the rider, sent only as the Authorization header on requests *to* intervals.icu — never collected by CleanJibe, and CleanJibe never writes to that account (privacy page, "intervals.icu"). |

## Permissions the questionnaire's own follow-up asks about

Apple's App Privacy flow asks a short follow-up for any usage-description key in the binary,
independent of the "collected" table above (a permission can be real and the answer still be
Not Collected, when nothing is retained past the on-device use):

- **Location When In Use** (beta/dev only) — one fix, on request, for the watch map. Say so;
  do not let the follow-up default to a broader description than `NSLocationWhenInUseUsageDescription`'s own text.
- **Bluetooth** (beta/dev only) — the Garmin Connect Mobile handoff: since 17 Oct 2026 the
  beta receives the session summary and the recording itself (the direct transfer, ADR-027)
  from the CleanJibe watch app, both onto the rider's own phone and analysed there. No pairing
  of our own, no network, no server — so the "collected" table above does not move (the
  recording is the rider's own content, on-device before and after, like an imported FIT).
- **Health** (beta only) — both directions, both opt-in, both on-device only.
- **Photo Library Additions** (release + beta) — add-only, never read.

## Flags for Jan (the judgment calls, gathered)

1. Location — Coarse: recommended **Not Collected**, but this is the row a reviewer is most
   likely to query given the location prompt exists in beta/dev. Keep this file's evidence
   trail handy if App Review asks.
2. The two "voluntary email" rows (Identifiers, Diagnostics — Crash Data): recommended **Not
   Collected**, on the reasoning that a rider composing and sending his own mail is not the
   app transmitting to a server. If you would rather declare defensively, "Not Linked to You /
   App Functionality" is the safe fallback for both — never "Not Collected" *and* "Linked to
   You" at once, and never Identifiers for the device facts (they are diagnostic, not an
   identifier scheme).

## The dev app record (`de.lahmann.wingfoil.dev`) — a shorter, separate label

Everything above, plus the dev-only doors: the wind direction and the watch map sent back
over the Garmin link (the summary and the recording coming in are the beta's since 17 Oct
2026, under the Bluetooth line above — still no network) and iCloud Drive library sync (ADR-026), which is the rider's own iCloud container, not
a CleanJibe server — same "Apple framework, on-device before and after" reasoning as the
Location row, so **Not Collected** there too. This record needs its own copy of the
questionnaire in App Store Connect; nothing above transfers automatically between the two
apps.

**Ask CleanJibe (dev 15 Oct 2026, beta from build 136 on 17 Oct)** is the first door that sends rider-typed content to a
server: the question, the app's version and units, and from a session its numbers (no
positions), to the assistant Worker on Cloudflare and on to Anthropic, kept 30 days
(docs/channels.md, "Ask CleanJibe"); an idea the rider shares there is kept a year for the team, with the date, channel and version and no key id — the same User Content row covers it. Proposed answers for the dev record: **User Content —
Other User Content: Collected, Not Linked to You, App Functionality** (the question); **Other
Data — session numbers: Collected, Not Linked to You, App Functionality**; no tracking. The
App Attest key id identifies an install, not a person, and is not used across apps. **Flag for
Jan**: Ask is in the beta now, which shares the main record; its label needs the same rows
before the App Store release.
