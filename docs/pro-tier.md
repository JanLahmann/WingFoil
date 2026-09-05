# CleanJibe Pro — the paid-tier proposal

**Status: proposal, not a decision.** This is the "pricing decision" that `plan.md` parks under
Phase 6, worked out far enough to argue with. Nothing in here is built, no price is set, and
the App Store metadata still says *Free, no in-app purchases* (`ios/store/appstore.md`). When
Jan decides, the decision becomes an ADR in `decisions.md` and this file becomes its design
notes.

The shortlist below is the ten capabilities Jan picked (5 September 2026) out of a longer
brainstorm. Each one is written up against the code that exists today: what a rider gets, what
it builds on, how it would work, what could go wrong, which tier it belongs to and roughly what
it costs to build.

---

## 1. What can be sold, and what cannot

Four facts about the product decide the shape of any paid tier.

1. **The analysis is already free three times over.** The same engine runs in the iPhone app,
   at cleanjibe.org in the browser (`web/README.md`: "there is no third implementation"), and
   approximated live on the watch. Gating flights, verdicts or GP3S records on the phone would
   fail on contact, because the web page does them for nothing. **The paid layer has to be
   things a zero-server web page cannot do**: sensors, background sync, the rider's own
   cloud, video, PDF generation, integrations that need a token.
2. **The engine is Apache-2.0.** A paywall compiled into the open-source app can be compiled
   out by anyone who clones the repo. What survives is convenience, service and the trademarked
   store builds that nearly every rider will actually install (the CleanJibe name and mark are
   not licensed — see the README). **Sell the service, not the code**, and accept that a
   determined rider can build a free Pro for themself. That rider was never going to pay.
3. **The privacy pitch is the differentiator.** Every listing leads with *no account, no
   server, nothing uploaded, no analytics*. A paid feature that needs a CleanJibe server would
   cost more in trust than it earns. Every capability below is therefore **either local or
   goes to a service the rider already uses with their own credentials** (iCloud, Strava,
   intervals.icu). None adds a CleanJibe backend.
4. **Connect IQ has no in-app purchase.** Paid CIQ apps use an unlock code (trial first, then
   a key bought on a web shop) or a third-party licensing service. ADR-012's `LockGate` is
   exactly that mechanism, and the ADR itself rates it a "please don't" gate because the
   pepper ships in the `.prg`. That is fine for a watch face priced at a few euros. It is not
   a reason to lock the watch app, which is the acquisition funnel.

### The tiers

| Tier | Where | What it holds | Pays how |
|---|---|---|---|
| **Free** | CIQ app · iPhone · web · Apple Watch launcher | Everything shipped today. Record, import, the full analysis, records, trends, replay, share card, library backup. This never shrinks. | — |
| **Pro** | iPhone (+ Apple Watch, Mac/iPad later) | Capabilities 1–8 below | StoreKit 2 subscription, with a lifetime non-consumable beside it — this niche buys once when it can |
| **School** | iPhone | Everything in Pro, plus capability 10: unlimited riders, coach views, session packages | A second StoreKit subscription group, priced per school not per seat, because a school's phones are shared |
| **Watch face** | Garmin | Capability 9, its own CIQ listing | Trial + unlock code (`LockGate`), sold from cleanjibe.org |

Price anchors from `plan.md` §1 (competitors, 2026): JMG Wind-Kite Pro $18 once ·
Foil Sessions $20/yr · WindsportTracker $27/yr · FoilMotion $30/yr · Waterspeed $30–60/yr ·
Surfr ≈ €55/yr. A Pro subscription in the **€20–30/yr** band with a **€49–59 lifetime** sits in
the middle of that list and under the two apps that run servers.

### What the web gets

The rule that keeps the web honest: **a Pro capability reaches cleanjibe.org only when it is
free there too, or not at all.** The web has no purchase path and no account, so it cannot
gate. Of the ten, the polar diagram and the skill rating are engine and digest work and
therefore land on the web free as the "try before you install" surface — that is the funnel
doing its job, and a rider who wants them on the phone still pays for the phone. The other
eight are phone-only by nature (sensors, iCloud, video, PDF, OAuth tokens, a second store
listing) and never reach the browser. This is written down so nobody has to re-argue it per
feature.

---

## 2. The ten capabilities

Effort is a gut estimate against this codebase, not a promise: **S** = days, **M** = one to
two weeks, **L** = several weeks. "Builds on" names the code that already does most of the
work.

### 2.1 Rich exports — **Pro · S**

**What the rider gets.** Any session, or the whole library, out as a spreadsheet: one row per
session with the digest fields (date, spot, gear, duration, distance, foil time and share,
flights, longest flight, every GP3S record, the outcome tally, clean jibes, CPH, WPH, streaks,
takeoff attempts and successes, source class). Per session, a **per-second CSV** of the cleaned
track — timestamp, lat, lon, speed, foil state, flight index, pump cadence, turn marker, heart
rate — and a **GPX with CleanJibe extensions** carrying the same columns, for riders who
analyse in their own tools. A **Shortcuts action** ("Export last session as CSV") so the export
can be automated into a Numbers sheet or a folder.

**Builds on.** The analysis document and the web's `digest()` (`web/lab_bundle/library.py`),
which already define the session-level column set; `LibraryBackup` for the bulk zip shape;
`FitShareFilter` for what must never leave the phone (watch serial, user profile). The web
already offers per-session `.json` and `.fit` downloads and a zip of everything — those stay
free there.

**Sketch.** A `SessionExport` module in `WingFoilKit` with three writers (`csvRows`, `trackCsv`,
`gpx`) over the analysis document, unit-tested against the goldens so a column can never say a
different number from the app. A `LibraryExport` that streams rows rather than holding the
library in memory. Export lands in the share sheet; the Shortcuts action is an `AppIntent`
beside the two that already exist for the watch (ADR-018). Column names are the presentation
contract's keys, so `docs/presentation.md` is the CSV header's documentation.

**Open questions.** Whether the per-second CSV should carry the *raw* accelerometer stream for
class-(a) sessions (20× the size — off by default, one toggle). Whether the web gets CSV too;
the rule in §1 says either free there or not there, and CSV is cheap enough that "free there"
is the honest answer, which makes the phone's paid part the bulk export, the GPX extensions and
Shortcuts.

### 2.2 iCloud library sync — **Pro · M**

**What the rider gets.** Two devices, one library. Import on the phone, open on the iPad; buy a
new iPhone and the library is simply there, with every title, note, gear assignment, rider
attribution and deletion intact. Nothing goes to CleanJibe; it goes to the rider's own iCloud
Drive.

**Builds on.** ADR-006 already names *iCloud Drive folder sync, not CloudKit* as the later
path. ADR-015 already forbids restoring by file copy and routes everything through
`SessionIngestor` with its ±60 s dedupe rule. `SessionTombstones` already record deliberate
deletions. `LibraryBackup`'s zip layout (`Sessions/<uuid>/original.fit`) is already the on-disk
shape a synced folder wants.

**Sketch.** A ubiquity container (`iCloud.de.lahmann.wingfoil`) holding
`Sessions/<uuid>/original.fit|.gpx|.cjw` plus a small `meta.json` per session with the
rider-authored fields (title, note, rider, gear combo, spot name override) each stamped with a
modification time, and a `tombstones.json`. Each device runs an `NSMetadataQuery` on the
container and feeds new files into the ingest path exactly as a restore does; metadata merges
**last-writer-wins per field**, tombstones win over rows. The analysis cache is **not** synced —
each device re-derives, which is the same cost the first import paid (`LibraryRestore`'s
comment says so). The web library stays device-local; a Mac sees the same folder through
Files, which is the Mac app's future import path for free.

**Open questions.** iCloud Drive can take minutes to propagate a 6 MB FIT on a beach; the UI
needs a "syncing" state, not a spinner. Conflict files (`original 2.fit`) must be ignored by
name. The App Groups gap in ADR-011 does not apply (a ubiquity container is its own
entitlement), but it is another entitlement the manual App Store profile has to carry.

### 2.3 Gear tagging from the wrist — **Pro (phone side) · M**

**What the rider gets.** Pick the wing, board and foil on the watch before pressing Start, from
the list the phone already knows, and hold a button mid-session to mark "changed wing". The
session arrives on the phone already tagged; the gear rollups and the per-gear polar (§2.4) are
right without a second thought.

**Builds on.** The companion link (ADR-013, `PhoneLink.mc`, `CompanionLink` in the kit) already
carries a card watch→phone and a wind push phone→watch. The `gear` and `session_gear` tables
and `GearKind` (`wing`, `board`, `foil`) exist. The wind menu on the watch (BACK → Session →
Wind) is the UI pattern to copy. The session developer-field table in `docs/fit-schema.md` has
room for one more `uint32`.

**Sketch.** Phone→watch: a `gearList` message — up to eight names per kind, each ≤ 12 chars,
plus a list version — stored in `Storage` (app state, not a GCM setting). Watch: BACK → Session
→ Gear, three pickers, remembered across sessions; the chosen indices go into a new session
dev field `gear_pack` (`uint32`: `listVersion << 24 | wing << 16 | board << 8 | foil`, 0 =
unset) and into the summary card as `gw`/`gb`/`gf`, so even the provisional row is tagged.
Mid-session change: a lap-message dev field or a `turn_marker`-style record value, resolved
on the phone as a second combo from that timestamp. Phone: on import, `gear_pack` + the list
version it sent resolve to `gearId`s; a stale version falls back to asking. **Fallback without
the iOS app:** three free-text GCM settings (`gearWing`, `gearBoard`, `gearFoil`) written as
the strings themselves — that is the free version, and it matches by name on import.

**Open questions.** Which side of the paywall the watch feature lives on. The recommendation is
**the watch side is free and generic** (the pickers and the field ship in the CIQ app for
everyone, because the CIQ app is never locked) and **the phone's list push and auto-resolution
are Pro**. A free rider types names in GCM; a Pro rider taps. The BLE hop is still unverified on
hardware (ADR-013's honest last paragraph) — this feature inherits that.

### 2.4 Your polar diagram — **Pro on the phone, free on the web · M (lab first)**

**What the rider gets.** A half-polar of boat speed against angle to the wind: how fast you go
at 50° upwind, at 90°, at 140° deep downwind; your best upwind angle and best VMG; the same
plot per wing and per foil across the season. No wingfoil app draws this. It is the picture
that tells a rider "your 5 m wing points ten degrees higher than the 4 m" and "you never sail
deeper than 150°".

**Builds on.** `wind.py` already derives course over ground per record and the wind axis
(the direction the wind blows *from*, with the 180° ambiguity resolved by the turn-type prior);
`flight.py` already knows which records are on foil; the GP3S code already computes best-N-second
windows. The engine→golden→Swift→web pipeline (ADR-001) is how it reaches every surface at once.

**Sketch.** Lab: `polar.py` — for each on-foil record with speed ≥ 2 m/s, true wind angle
`TWA = fold180(COG − windFrom)`; 18 bins of 10°; per bin the **best 10 s mean speed** whose
window lies wholly inside the bin, with a minimum of 20 s of samples per bin or the bin is
null. Output `summary.polar` (18 values, cm/s, plus `bestUpwindTwa`, `bestVmgUpwind`,
`bestVmgDownwind`) into the golden; `ENGINE_VERSION` bump. Swift and the web render the
half-polar from the same 18 numbers. **Aggregation** across sessions is a max per bin over the
filtered set (spot, gear, period), computed from digests exactly as trends are today, so the
per-gear overlay is a library query, not an engine pass. Session detail gets the plot as a
section; Trends gets the aggregated one with a gear picker.

**Open questions.** Without wind *strength* this is speed-by-angle, not a true polar normalised
to wind speed — the section header must say so, and the wind-enrichment idea from the longer
list is what would fix it later. A session with no wind axis has no polar (null, like the
turn geometry rule). Watch: no live polar — the wrist has no room and the axis is an estimate
there (`wind_dir_auto`).

### 2.5 Auto-highlight reel — **Pro · M**

**What the rider gets.** One tap makes a 30–45 s clip: title card, the longest flight, the
fastest 10 s, the cleanest jibe, the closing numbers, over the rider's own music. Nothing to
scrub, nothing to pick. It is the share card that moves.

**Builds on.** `ReplayCinemaView` + `ReplayRecorder` (ReplayKit screen capture, deliberately the
only renderer), `ReplayTitleCardView` and the outro card (`ReplayClipCards`), `ReplayMusic`,
`ReplayFraming` (9:16, 1:1, 16:9). Every pick is already in the analysis document: `flights`
(longest), the record windows (`best10s` start/end), `turns` with `score` and the clean flag.

**Sketch.** A `HighlightPlan` in the kit: an ordered list of `[segment]`, each `(start, end,
caption)` with 5 s of lead-in and lead-out, chosen by fixed rules — longest flight, best 10 s
window, the clean jibe with the highest score, and, when a session has one, the last jibe of the
longest dry streak. The cinema view learns to play a plan: jump the playhead to each segment,
show a one-line caption card between them ("Longest flight · 2:14 · 780 m"), then the outro.
ReplayKit captures the whole thing in one take, exactly as it captures a manual replay today,
so the reel is verifiable only on a device (the simulator writes zero bytes — known). The plan
is unit-tested against the goldens; the pixels are tested on a phone.

**Open questions.** Music licensing is already handled by the rule that a clip carries the
rider's own library tracks only (presentation contract "A clip can carry the rider's own
music"). A session with no clean jibe gets a three-segment reel, not a fake one. Whether the
free tier keeps the *manual* replay recording — yes: it shipped free and nothing shipped free is
taken back.

### 2.6 Skill rating and progression curve — **Pro on the phone, free on the web · M (lab first)**

**What the rider gets.** One number, 0–100, that moves when the riding improves, and a curve of
it across seasons. Under it, the rung it is standing on and the one above ("you fly through
six jibes in ten; the next level is eight, and your port side is what's holding it"), lifted
from the turn ladder that already writes coach-style sentences.

**Builds on.** The digest fields that trends read (`jibesSuccessful`, `cleanJibeRate`,
`foilPct`, `wetPerHour`, `longestDryStreak`, the takeoff pack for class (a)); the coaching
ladder in `docs/presentation.md` "Turn detail"; the port/starboard split.

**Sketch.** Lab, as a digest-level function so the web and the phone compute the identical
number: per session, five components scored 0–100 against **fixed, published anchors** (not
against the rider's own history, or the number would drift as the rider improves) — clean-jibe
rate (needs ≥ 5 jibes), foil share, swims per hour inverted, longest dry streak, takeoff success
(class (a) only; the weight redistributes when absent). Weighted sum, then an **EWMA over the
last eight sessions** so one bad day dents rather than resets. Anchors live in
`docs/algorithms.md` beside every other threshold, with the reasoning. The curve is the EWMA
per session drawn on Trends; the "next rung" is the component furthest below the next anchor,
phrased through the existing ladder vocabulary.

**Open questions.** Conditions are not normalised — a 12-knot day and a 25-knot day score on
the same scale — and the doc must say so until wind data exists; a per-spot handicap is the
first refinement. Riders will game it; that is what a rating is for. Naming: it is *not*
called a score anywhere the turn `score` already lives, or the two collide.

### 2.7 Season yearbook — **Pro · M**

**What the rider gets.** At the end of the season (1 April → 31 March, `LibraryPeriods`), a
multi-page PDF: cover with the season's stacked track outlines; the aggregate block; every
record set that season and the afternoon it was set; the trips; the spots on one map; gear
hours; the three best sessions as full cards; the trend charts. Saved to Files, printed, or
sent to the family group chat. Entirely local.

**Builds on.** `PeriodsView` / `PeriodShareView` (the period card, stacked outlines,
`ImageRenderer` at 3×), `ShareCardView`, `RecordsView`, `SpotsView`, `GearView`, `TrendsView`.
Every page is a view that exists; the yearbook is a page order and a PDF context.

**Sketch.** `YearbookDocument` in the app: an array of SwiftUI pages sized A4/Letter, rendered
by `ImageRenderer.render(rasterizationScale:renderer:)` into one `CGContext` PDF. The stats on
every page come from the same `ShareCardStats` / aggregate-block pipeline the cards use, so the
yearbook cannot name a number the app does not. A "Yearbook" button on the season row in
Periods; a notification in the first week of April offering it. Later: a month and a trip
variant with the same pages, since a Garda week wants the same book.

**Open questions.** Map pages need MapKit snapshots, which is the one asynchronous step
(`MKMapSnapshotter`), and the one place the PDF could wait on the network — cache the snapshot
or fall back to the outline-only page. Typography and the print margin are a design pass, not
code; `brand/` and `design/tokens.json` own the answer.

### 2.8 Write-back to Strava and intervals.icu — **Pro · S (icu) + M (Strava)**

**What the rider gets.** After import, the activity on intervals.icu and Strava carries the
CleanJibe summary: "Foil 68% · 41 flights, longest 2:14 · 7 of 10 jibes clean · max 2 s 24.3 kn
· 5×10 s 21.9 kn", written into the description and, on intervals.icu, into custom fields the
rider can chart there. The two services the app already sits between finally learn what
CleanJibe knows.

**Builds on.** `IcuClient` (base URL, basic-auth with the personal key, activity list, original
FIT). The dedupe rule (start time ± 60 s) that already matches an intervals.icu activity to a
library row. The share card's stat block as the source of every number.

**Sketch.** intervals.icu: the same API key the rider pasted is a write key for their own
account; `PUT /api/v1/activity/{id}` with `description` (append a marked block, never
overwrite the rider's own text) and the custom-field values, after the rider has created the
fields once (a one-time setup card in the style of `IcuSetupGuide`). Idempotent: the block is
delimited so a re-analysis rewrites it in place. Strava: a registered API application, OAuth2
`activity:write` through `ASWebAuthenticationSession`, token in the Keychain beside the icu
key, activity matched by `start_date` within the same ±60 s, `PUT /api/v3/activities/{id}` with
the description block. Both are **opt-in toggles**, off by default, each with a "what gets
written" preview.

**Open questions.** Strava's API agreement is the risk ADR-003 already flagged: new
applications are limited to the developer's own athlete until Strava approves them, branding
rules apply ("Compatible with Strava"), and the agreement forbids some uses of Strava data —
writing a description of the rider's own activity is squarely permitted, but the approval step
is on the critical path and takes weeks. Ship intervals.icu first; it needs no approval and no
OAuth. The privacy label gains one honest line: with the toggle on, a summary of your session
is sent to a service you chose.

### 2.9 Garmin watch face — **its own product · M**

**What the rider gets.** A CleanJibe face: the time, and under it the season's foil hours, the
last session's clean jibes and max 2 s, and — if enabled — tomorrow's wind at the home spot.
The thing a rider looks at forty times a day carries the number they care about.

**Builds on.** `Brand.mc`, `Glyphs.mc`, `Ink.mc` and the design tokens for the look; the
`WingFoilCore` barrel for formatting; the CIQ app's session history (`SessionHistory.mc`) for
the numbers.

**Sketch.** A new CIQ **watch-face** project under `garmin/face/`, sharing the barrel like the
field does. Data path: the device app **publishes complications** (Connect IQ 4+ `Complications`
publisher API — the app's `minApiLevel 5.0.0` covers it) after every save: season foil hours,
last clean jibes, last max 2 s; the face **subscribes** to them, so no radio, no phone and no
storage sharing are involved, and the face works with the free app installed. Forecast: an
optional background service (`Toybox.Background`, watch faces since CIQ 3.2) fetching one small
JSON from Open-Meteo for a spot set in GCM — a separate product with its own listing text, so
the app's "contacts no weather service" line stays true. Payment: trial + unlock code through
`LockGate`, the code bought at cleanjibe.org — the standard CIQ pattern, and the one the
`please don't` caveat is proportionate to.

**Open questions.** The complications publisher path is the first spike: verify in the
simulator that a device app can publish and a face can read on fenix 7 and 8 before drawing a
pixel. If it cannot, the fallback is GCM settings the phone cannot write and the face degrades
to forecast plus branding, which is a weaker product. Watch faces are the most-sold CIQ
category and the most-copied; the mark is what protects this one.

### 2.10 Coach and school tier — **School · L**

**What the rider gets.** A coach's phone holds the sessions of every student, each under their
own name, each excluded from the coach's own records. Two sessions side by side — the same
student on Monday and Friday, or two students on the same afternoon. A note pinned to a turn
("you're looking at the wing, look at the exit") that the student sees in their own app. A
**session package** the student sends by AirDrop or a chat, and one the coach sends back with
the notes in it. On a school's shared Garmin, a rider picker at Start so the FIT lands under
the right name.

**Builds on.** Rider attribution exists (`RiderPromptView`, `LibraryStore.riders` as the
address book, foreign sessions kept out of Records and Trends); `FitShareFilter` already scrubs
identity from a shared file; the turn detail sheet is where an annotation would live; the
companion link and the wind menu pattern serve the rider picker; `gear_pack`'s neighbour in the
FIT is a `rider_index`.

**Sketch.** Phase A (phone, Pro needs none of this): riders become a table (`rider` with id,
name, colour) rather than a column of strings; a **Riders** tab listing each with their rating
curve (§2.6) and last session; a filter chip on Records and Trends; **compare** as a two-column
session detail with synced playheads. Phase B (packages): `.cjpkg` = the backup zip shape for
one session plus `notes.json` (turn-anchored, author, time); import through the ingest path
like everything else; the app registers the extension so a package opens from Messages. Phase C
(watch): a Riders list pushed like the gear list, a picker at Start, `rider_index` in the FIT;
the phone resolves it to a rider on import. Licensing: Pro allows **three** named riders beside
the owner (a family); School removes the cap and unlocks compare, notes and packages.

**Open questions.** Notes are the one place another person's words enter a rider's library —
they must be visibly authored and deletable. GDPR: a school holding students' sessions on a
coach's phone is the school's responsibility, not the app's, but the privacy page must say what
a package contains. Schools also want an Android answer; the web library is it for viewing, and
a package's FIT drops into cleanjibe.org today.

---

## 3. Sequencing

The order that gets a paid tier live soonest with the least risk, then deepens it.

| # | Capability | Why here |
|---|---|---|
| 1 | Rich exports | Smallest, no external dependency, proves StoreKit end to end |
| 2 | Write-back to intervals.icu | Small, the client exists, no approval needed; start Strava's application process in parallel |
| 3 | Polar diagram | Lab work that also improves the free web — the funnel gets better while Pro gets a headline feature |
| 4 | Auto-highlight reel | The most shareable Pro feature; every reel carries the mark |
| 5 | iCloud sync | The retention feature: a rider with two devices does not churn |
| 6 | Skill rating | Needs a few hundred sessions of real riders to set anchors honestly — collect while 1–5 ship |
| 7 | Gear tagging from the wrist | Waits on the BLE hop being verified on hardware (ADR-013) |
| 8 | Season yearbook | Ship for the season that ends 31 March 2027 |
| 9 | Garmin watch face | After the complications spike; independent of the phone track |
| 10 | Coach and school tier | Phase A can start any time after 6; B and C once a real school asks |

Two reasons to ship in this order rather than by size alone. Items 1–4 are all things that can
be demonstrated on the bundled example session, so App Review and a curious rider can see the
whole Pro tier without importing anything — the same argument `appstore.md` makes for the free
app. And items 3 and 6 are engine work that reaches the web free, which is the honest way to
show what Pro is before anyone pays for it.

## 4. What changes the day this is decided

- `ios/store/appstore.md`: *Price* becomes the subscription; the description gains a Pro
  paragraph that says what stays free first; the App Privacy answers gain the Strava and
  intervals.icu write-back line (with the toggle on, a summary of your session is sent to the
  service you chose). StoreKit itself adds nothing to the label — Apple processes the purchase.
- `docs/decisions.md`: an ADR for the tier split, one for the "either free on the web or not on
  the web" rule, and one for the watch face's complications path once the spike answers.
- `docs/plan.md` Phase 6: the pricing decision line points here.
- `docs/fit-schema.md`: `gear_pack` and `rider_index` get field ids when 2.3 and 2.10 start.
- `docs/algorithms.md`: the polar bins and the rating anchors, with reasoning, when 2.4 and 2.6
  start — the same place every other threshold lives.
- Nothing shipped free is taken back. This sentence is the one riders will quote.
