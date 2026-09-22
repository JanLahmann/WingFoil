# Analytics — what is counted, where, and what it can never answer

Jan, 19 September 2026: *"review the umami instrumentation. should we adjust / extend it?
Can we also analyse the iOS app?"* This file is the answer to both. It is the event map for
cleanjibe.org, the rule every event name and every event property obeys, and the decision on
the iPhone app at the end.

One counter, one place: **umami**, cloud-hosted at `cloud.umami.is`, cookie-free, pinned to
`cleanjibe.org` by `data-domains` so a local server and every preview stay silent. The
script is `defer`, third-party, and deliberately **not** in `sw.js`'s precache — an offline
page renders whole without it. Nothing in the product depends on it and nothing waits for
it.

## The rule for event properties

**No personal data reaches an event. Ever.** Not a file name, not a coordinate, not a spot
name, not a session title, not a date, not a number off a ride. What may travel is a
**count**, a **format**, a **source class**, a **page or tab name**, a **card shape**, a
**reason word** — each of them a fixed word out of a closed set the code names at the call
site, or an integer.

This is a mechanism and not a promise. `web/js/track.js` is the single door to umami: it
no-ops when `window.umami` is absent, never throws, caps every string property at 32
characters, drops every value that is not a string, a finite number or a boolean, and stops
at six properties. A caller that hands it an object sends nothing; a caller that hands it a
file name sends a truncated one rather than a leak. The one block that cannot import it —
the inline install banner in `web/app/index.html`, which must listen before the module
graph has loaded — writes the same guard out longhand and says so.

The privacy page carries the disclosure in one sentence, in the voice
(`web/privacy/index.html`, *umami — anonymous, cookie-free page counts*): *"It also counts
named actions like a card made, with only a format, a count or a tab name."* The footer's
line on every page is unchanged, because it already covered this: *"Anonymous, cookie-free
usage stats and feature counts by umami."*

## The rule for event names

Kebab-case. `<surface>-<object>-<verb>` wherever the extra word earns its place. One name
per thing across every page, so the umami dashboard reads as one product rather than as
seven files.

| prefix | surface |
|---|---|
| no prefix | a door that means the same thing on every page: `github`, `footer-feedback-mail` |
| `app-cta-`, `beta-cta-`, `example-` | the doors into the three destinations, wherever they appear |
| `home-`, `start-`, `help-`, `invite-`, `whatsnew-` | a door that only that page has |
| `app-way-` | one of the six recording classes in the analyzer's ways-in card |
| `app-<object>-<verb>` | an action **inside** the browser app, fired from JavaScript |

### The renames of 19 September 2026

Four JS events predate the scheme and were renamed with this change. The umami dashboard
has a break on that date; the old names keep their history and stop growing.

| was | is | why |
|---|---|---|
| `analyze-file` | `app-file-analyzed` | verb last, and it now carries `format` and `source` |
| `example-run` | `app-file-analyzed` with `source: "example"`, plus `app-example-loaded` | the press and the finished report are two different questions |
| `fit-saved-to-library` | `app-session-saved` | rider vocabulary, and "fit" was the wrong noun once a GPX could be saved |
| `card-created` | `app-card-made` | the lexicon's verb, and it now carries the composer's three choices |

## The four funnels

Every event below belongs to exactly one of these, and that is the column that decides
whether it is worth having at all.

1. **Land** — a stranger arrives and finds out what this is. Pageviews on `/`, `/start/`,
   `/help/`, `/invite/`, plus the doors between them.
2. **Open the app** — the visitor reaches `/app/`. `app-cta-*`, `example-cta`, the
   pageview on `/app/`.
3. **First session** — the app does its job once. `app-example-loaded` →
   `app-file-analyzed` → `app-session-saved`, with `app-way-*` saying which recording class
   the visitor thinks he has.
4. **Share / beta / TestFlight** — the visitor becomes a rider who brings others.
   `app-card-made`, `beta-cta-*`, `invite-testflight`, `invite-garmin-store`,
   `app-install-*`.

---

## `/` — the project homepage (15 declarative events)

| event | where it fires | the question it answers | funnel |
|---|---|---|---|
| `app-cta-hero` | the hero's *Open the app* | does the picture sell the app or the beta | 2 |
| `app-cta-nav` | the topbar's *Open the app*, on all seven pages | is the sticky bar the way in, or the hero | 2 |
| `app-cta-panel` | the analyzer piece's foot | does a reader who read the three pieces still go in | 2 |
| `example-cta` | *See a real session* | do strangers want a demo before a drop | 2 |
| `example-card-note` | *Make one from your own session* under the hero card | does the card itself sell the app | 4 |
| `beta-cta-hero`, `beta-cta-nav`, `beta-cta-coming`, `beta-coming-button` | the four beta doors | which of the four is worth keeping | 4 |
| `beta-garmin`, `beta-testflight` | the beta door inside a piece | which piece makes people want the beta | 4 |
| `home-classes`, `watches-piece` | *Which watch* | how many readers do not know whether their watch works | 1 |
| `github` | the topbar and footer link | is the open repo a door anyone uses | 1 |
| `footer-feedback-mail` | `info@cleanjibe.org` in the footer | does the last line of a page get used | 1 |

## `/start/` (10), `/help/` (5), `/invite/` (10)

The shared five — `app-cta-nav`, `beta-cta-nav`, `github`, `footer-feedback-mail` and the
nav's own pair — are on every page and are read per page in umami rather than renamed per
page. Each page's own doors:

| page | events | the question |
|---|---|---|
| `/start/` | `start-invite`, `start-watches`, `start-garmin-store`, `start-android-app`, `start-feedback-github`, `start-feedback-mail` | which route a reader takes out of the guide, and whether the Connect IQ listing is reached from here |
| `/help/` | `help-start` | does the help catalogue send anyone back to getting started |
| `/invite/` | `invite-start`, `invite-testflight`, `invite-garmin-store`, `invite-feedback-github`, `invite-feedback-mail`, `whatsnew-garmin-store` | the TestFlight and Connect IQ joins, which are funnel 4's only real conversions |

`/privacy/` and `/impressum/` carry the five shared ones and nothing of their own: they are
read once, before a decision, and a counter on a legal page answers no product question.

## `/app/` — the browser app, declarative (13)

| event | where it fires | the question | funnel |
|---|---|---|---|
| `app-way-garmin`, `app-way-apple-watch`, `app-way-apple-workout`, `app-way-fit`, `app-way-strava` | the five recording-class rows of the ways-in card | **which watch a visitor actually has.** Three of the five say "on the iPhone app", so a run of presses on those is riders the browser cannot serve | 3 |
| `app-way-garmin-settings` | *Open Settings* inside the Garmin row | how many take the intervals.icu route rather than a file | 3 |
| `app-session-help` | *Help* from the session page | is a reading of the report a reading of the glossary too | 3 |
| `app-help-numbers` | *How it works* from the session page | same question, one link further out | 3 |
| `app-privacy` | *Privacy* in Settings | does anybody check | 1 |
| the shared five | nav, footer, GitHub | as above | 1, 2, 4 |

## `/app/` — the browser app, from JavaScript (23)

Every one of these goes through `track()` in `web/js/track.js`.

| event | properties | where it fires | the question | funnel |
|---|---|---|---|---|
| `app-file-analyzed` | `format` (`fit`/`gpx`/`tcx`/`zip`), `source` (`drop`/`picker`/`example`/`shared`/`icu`) | `js/app.js`, after a successful analysis | **the one number this site is for.** How many sessions the engine finished, and which way in and which format they came through | 3 |
| `app-file-rejected` | `source` | `js/app.js`, the extension guard | are riders arriving with a format CleanJibe does not take | 3 |
| `app-example-loaded` | — | `js/app.js`, the example press | the gap to `app-file-analyzed` is the 12 MB runtime download people wait out or do not | 3 |
| `app-session-saved` | `replaced` | `js/app.js`, after the write | does a visitor keep a session or only look at it | 3 |
| `app-session-opened` | `from` (`library`/`record`/`trend`) | `js/app.js` `openStored` | which list people re-open a session from | 3 |
| `app-tab-switched` | `tab` (the four) | `js/appshell.js`, the tab press only | are Records, Trends and Gear ever reached | 3 |
| `app-menu-row-opened` | `row` (the five) | `js/appshell.js`, the app menu | which of the phone's five menu rows earns its place in the browser | 3 |
| `app-card-made` | `how` (`download`/`share`), `kind` (`session`/`period`), `shape`, `preset`, `map` | `js/sharecard.js`, after the PNG exists | **the growth channel.** Which shape and which preset a card is actually made in, and whether the map background is on | 4 |
| `app-icu-sync-started` | — | `js/icu.js`, *List recent activities* | how many riders try the bridge at all | 3 |
| `app-icu-sync-finished` | `activities` (the watersport count) | `js/icu.js`, after the list | does the bridge ever work from a browser | 3 |
| `app-icu-sync-failed` | `reason` (`blocked`/`key`/`http`) | `js/icu.js` | `blocked` is the expected CORS wall; a rise in `key` is a wording problem in Settings | 3 |
| `app-install-shown` | `platform` (`chrome`/`ios`) | the inline banner and `js/install.js` | the denominator the accept rate needs | 4 |
| `app-install-accepted` | `platform` (`chrome`/`browser-menu`) | the inline banner's `userChoice` and `appinstalled` | do people install the PWA | 4 |
| `app-shared-file-taken` | — | `js/app.js`, `?shared=1` | **does Android's share target work.** The POST never reaches a server, so this is the only evidence it exists | 3 |
| `app-backup-exported` | `sessions` | `js/library.js` *Download all* | how big a library people keep in a browser | 3 |
| `app-backup-restored` | `added`, `skipped`, `failed` | `js/backup.js` after the run | a `failed` above zero is an archive this engine could not read | 3 |
| `app-deleted-restored` | `outcome` | `js/deleted.js` | is the tombstone worth its storage | 3 |
| `app-range-chosen` | `range` (a preset id) | `js/daterange.js` | which window riders read their trends in | 3 |
| `app-range-custom-used` | `days` | `js/daterange.js`, *Done* | were the presets not enough, and by how much | 3 |
| `app-map-ground-set` | `ground` (`map`/`plain`) | `js/trackmap.js` | the one control that starts a request to somebody else's server | 3 |
| `app-map-opened-full` | — | `js/trackmap.js` | does the full-screen door earn its code | 3 |
| `app-turn-page-opened` | `kind` (`turn`/`end`) | `js/turnpage.js`, the row press | is the turn page read, or only the table | 3 |
| `app-spot-renamed` | — | `js/spots.js` | do riders name their spots. The typed name never leaves the browser | 3 |

## What umami cannot answer, and why

Name these before reading any number off the dashboard.

- **How many riders.** There is no identifier that survives a visit, by design, so every
  count is of *visits* and not of people. A rider who analyses on Monday and again on
  Friday is two.
- **A funnel with steps joined up.** Cookie-free means no session stitching worth trusting:
  `app-example-loaded` and `app-file-analyzed` can be compared as totals, never followed
  person by person.
- **Anything a content blocker stops.** The script is third-party, `defer` and on a
  well-known host. A meaningful share of visits — plausibly the privacy-minded share this
  product attracts — is simply not counted. **Every number here is a lower bound.** Never
  quote one as a total.
- **Anything offline.** The installed PWA works with no network; those sessions reach
  nobody. The rider who most proves the product works is the one the counter never sees.
- **Anything about the session.** No duration, no speed, no spot, no date, no verdict. That
  is the rule above, and it is not a gap to be closed later.
- **Why somebody left.** No scroll depth, no dwell time, no heatmap, no recording. If a
  page needs that question answered, it needs `docs/review-checklist.md` run over it
  instead.
- **The iPhone app.** Nothing in `ios/` calls umami and nothing will. See below.

---

## The iPhone app — a decision for Jan

**The promise stands.** `web/privacy/index.html`: *"The app contains no analytics, no crash
reporter, no third-party tracking code."* `ios/store/appstore.md`, in the App Store
description and again in the privacy answers: *"there is no analytics SDK and no crash
reporter in the app."* An SDK in the app would break a sentence riders were shown, on the
store page they decided from. **Recommendation: keep the promise, and use (a) and (b),
which need no code and break nothing.**

### (a) The beta's opt-in usage report — already built, already shipping

`ios/WingFoilKit/.../Presentation/UsageCounters.swift` counts seventeen features on one
phone: `appOpen`, five import routes (`importIcu`, `importFile`, `importStrava`,
`importHealth`, `importShareSheet`, `importZip`), `sessionOpened`, `turnPage`, `shareCard`,
`clipExported`, `videoExported`, `backupMade`, `backupRestored`, `settingsOpened`,
`feedbackMail`, `stravaConnected` — a count and a last-used date each, plus up to twenty
deduplicated failure sentences. It lives in that phone's `UserDefaults`, it is `#if BETA`
only, and the only way a number leaves is a mail the rider opens, reads and sends from his
own account with every line editable first (`UsageReportMail`, Settings → Beta → *Send
usage report*, and the card the library offers every fifth session).

**How its counters could become a funnel.** The seventeen features already map onto the web
events above almost one for one: `importFile`/`importIcu`/`importShareSheet` are
`app-file-analyzed`'s `source`; `sessionOpened` is `app-session-opened`; `turnPage` is
`app-turn-page-opened`; `shareCard` is `app-card-made`; `backupMade`/`backupRestored` are
the backup pair. What is missing is the denominator and the arithmetic, and both are cheap:

1. Print `appOpen` and the day count that is already kept beside it, so every other line can
   be read as a rate rather than as a total.
2. Print the three ratios the funnels above need, computed on the phone and shown to the
   rider before he sends them: sessions imported per app open, turn pages per session
   opened, share cards per session opened.
3. Keep the mail as it is otherwise. The moment a counter is uploaded rather than mailed,
   it is telemetry with a longer path, and the sentence in the store text is false.

The cost of (a) is that the sample is the beta and the send is voluntary, so it answers
*"is this door ever opened by anybody"* and never *"by what share of riders"*.

### (b) App Store Connect's built-in analytics — use this first

Apple already measures installs, first-time downloads, re-downloads, sessions, active
devices, retention by day and by cohort, crash counts, and the funnel from product page
view to download, broken out by territory, source type and device. **No code, no SDK, no
change to the app, and nothing to disclose** — the opt-in is the rider's, on Apple's side,
under Settings → Privacy → Analytics & Improvements, and the data reaches the developer
already aggregated and anonymised. It is the only source that can answer the store-page
questions at all: how many people see the listing, how many of those download, and how many
open the app again a week later.

This is the first thing to turn to, because it is already collecting and has been since the
first build. It cannot answer anything *inside* the app — no screens, no imports, no turn
pages — which is exactly the half (a) covers.

### (c) MetricKit crash digests — already in the feedback mail

`ios/WingFoil/App/CrashDiagnostics.swift` subscribes to `MXMetricManager` in **every**
channel, the App Store one included, reduces each payload to four fields through the kit's
`CrashLog`, and keeps the last ten in Application Support. iOS collects them itself, on
device, a day or so later, with no SDK in between; they sit in the app's own container until
a rider opens a feedback mail and reads the block before tapping Send. *Start over* wipes
them. This is not an option to adopt — it is already there — and it is the reason the
"no crash reporter" sentence is true rather than a technicality: nothing is sent by that
type.

App Store Connect's crash counts (b) are the aggregate view of the same failures, so (b) and
(c) answer *how often* and *what exactly* without either one becoming a reporter.

### (d) One session, sent by the rider, from the Share page — beta

Share → **Send this session to the developer** (21 September 2026, docs/channels.md, beta).
It is **rider-initiated and per session**: nothing runs in the background, nothing is
sampled, and no session leaves a phone that a rider did not open, write a note on, read the
whole mail of and press Send for. There is no CleanJibe endpoint to receive one; the mail is
`MFMailComposeViewController`'s and it sends from the rider's own account.

What rides with it is said on the screen before the decision is taken, in the rider's own
words (`SessionAnalysisMail.consent`): *"The file holds your track, your heart rate and your
times. It is used only to improve the detection. It is never published."* That is the
**archived original, unscrubbed** — unlike the copy the share sheet sends to a friend,
which `FitShareFilter` strips of the watch serial, the rider profile and the paired-accessory
name. The difference is deliberate and is the reason the consent sentence names the three
things the file holds: the developer fields and the laps a scrub removes are the half most
likely to explain a wrong number, and a rider who is asking for a number to be chased is
told exactly what he is handing over.

Under it, behind the rule every prefilled mail carries, is the same block (c) prints —
build, channel, engine, phone, library, this session's source class and its headline numbers
— and the same permission: *delete any line you would rather not send.* The browser's
version of the door does the same thing with `navigator.share` or a download plus a
`mailto:`, and uploads nothing either.

The privacy page names it under what leaves the device.

### What is not recommended

A self-hosted umami, a Sentry, a TelemetryDeck or any opt-in SDK inside the iPhone app. Each
would work, each would be honestly disclosable, and every one of them costs the sentence in
the store description that a privacy-first product is bought on. The two free sources above
answer the questions that actually change what gets built next.
