# The Connect IQ store listings

**Archival, not a draft.** This file is the source of truth for what the two Connect IQ
listings say *today* — transcribed verbatim from the live store (app on 2 September 2026 at
0.9.4, field on 1 September at 0.9.5), because until now the only copy of this text lived in the Connect IQ developer
console and nowhere in git. Edit it when the store is edited, in the same commit; do not
rewrite it here and leave the store behind.

Rewrite drafts are a separate thing and are not in this file.

Both apps: developer **JanRL** (`7d829c3a-3343-46f5-b946-4556e4579f53`), support
`info@cleanjibe.org`, website `https://github.com/JanLahmann/WingFoil`, free,
open beta, English only.

---

## Watch app — `CleanJibe Wingfoil Tracker (Beta)`

* Store page: <https://apps.garmin.com/apps/e77867b5-e972-4eb2-be1b-90077cfac806>
* Type: device app · Version **0.9.13** on the store, **42** products (uploaded 17 Sep 2026, 21:25, Internal 21; 0.9.12 the same day; 0.9.11 on 15 Sep; web/tools/make_devices.py reads this line, keep its shape) · first submitted 2026-08-12, 0.9.4 released 2026-09-01
* Permissions: Fit, SensorLogging, Communications, Positioning, FitContributor, Sensor
* Devices (`garmin/manifest-beta.xml`, identical to the release and dev manifests; the count and
  the family grouping are generated into `docs/copy/garmin-devices.json`): 42 products at 0.9.11 —
  fenix 8 / 7 / 5 Plus families, epix 2 / 2 Pro, Forerunner 255 / 265 / 570 / 955 / 965 / 970,
  MARQ 2, Enduro 2 / 3, D2 Mach 1 / 2, Descent Mk3, Venu 2 / 3, vívoactive 5 / 6, Instinct 3
  AMOLED (and the tactix / quatix twins those product ids cover)
* Open beta since 0.9.4: no unlock key. The invite lock (ADR-012) is compiled out of every
  channel now; the invite UUID `28942317…` is simply the public listing's UUID.

Transcribed from the live store on 2026-09-02. The earlier "TODO (pending edit)" items (the
`WingFoil - Invite Beta` breadcrumb and the old GitHub Pages URL) no longer exist in the live
text — the whole description was rewritten for the open beta.

### Description (live text)

**One line ahead of the store:** the `NEW TO IT?` paragraph pointing at cleanjibe.org/start
is written here first and goes into the Connect IQ form by hand at the next upload. It is the
one deviation from this file's rule, and it is deliberate — the page it names is live now, and
a listing that had it and a file that did not would be the wrong way round to get caught.
Delete this note the day the store text matches.

```
CleanJibe tells you what your wingfoil session actually did: how much of it you spent on the foil, how long each flight lasted, your speed records, and — for every turn — whether you flew through it, touched down, or fell in.

OPEN BETA, FREE. Install and ride — no key, no account. It's a beta: tell us what's wrong and what's missing at cleanjibe.org/invite, or use Contact Developer on this page. The detection thresholds are still being tuned and may change between versions; they are published, with the reasoning, at github.com/JanLahmann/WingFoil.

NEW TO IT? cleanjibe.org/start walks you through a 20-minute test on land — record a few minutes, get it onto your phone, see what you should see — and says exactly where to send what you find.

ON THE WATER
- Live foil state: it knows when the board is up on the foil, and counts every flight and touchdown while you ride.
- Every turn scored as you make it — flew through, touched down, or fell in — with your dry streak and your tack/jibe tally on screen.
- Speed records live on the wrist: best 2 s and best 10 s, with a PB alert.
- The watch works out the wind direction by itself after a few minutes of riding (a ~ marks the estimate; the wind menu always overrides it).
- Pump strokes and takeoff attempts, counted from the wrist accelerometer. Optional raw accelerometer logging for deep phone analysis is off by default — it makes the activity file about 20x larger and the transfer after saving takes several minutes.
- Seven configurable pages: speed, session, records, turns, map with breadcrumb, on-foil timeline, clock. A full multi-page summary after you save.
- Records as a Windsurf activity with per-flight laps, so your sessions stop showing up in Garmin Connect as a walk. 1 s GNSS, multiband where the watch supports it. Auto-pause.

AFTERWARDS, FREE, IN ANY BROWSER
Open cleanjibe.org and drop the .fit file in. The same analysis engine runs locally in your browser — nothing is uploaded and there is no account — and gives you the track, every flight, every turn with its verdict, speed records, wind axis, and a share card you can post. Keep a library there and it builds your all-time records and season trends. It works on an Android phone just as well, and it also reads sessions recorded with Garmin's own Windsurf profile or a GPX, so you can try it before you ever install anything.

An iPhone app with the full analysis — maps, turn forensics, replay with commentary and music, records, trends and library backup — is in open TestFlight beta: testflight.apple.com/join/nygqGGcn
```

### What's New (live text)

**0.9.13 uploaded 17 September 2026, 21:25** (public listing, live at once, Internal 21). **The live field holds two paragraphs since the 0.9.12 upload**: the long per-version history that stood here until 0.9.11 was replaced by a single 0.9.12 paragraph at that upload (this file recorded the old block until 0.9.13; the history lives in "Version history" below). Text as submitted:

```
0.9.13: fenix 5 Plus, 5S Plus and 5X Plus: the clock no longer sits on the speed, PAUSED is a word again, captions and SAVED clear their numbers. Thanks to Leo for the report.

0.9.12: Discard works again. In 0.9.11 the question "Discard session?" could leave the app stuck until the watch restarted. It is a two-line menu now: Keep or Discard. Everything from 0.9.11 stays: every buzz also paints, the fenix 5 Plus family, "Reset pages to defaults", the Turns page header flew · touch · fell, START records · BACK saves on the start page, NOT SAVED when the file was not written.
```

---

## Data field — `CleanJibe Wingfoil Field (Beta)` — DORMANT since 2026-09-04

**The field is parked (ADR-020).** Jan never used it, nobody has asked for it, and every hour on
it is an hour not on the app. The code under `garmin/field/` stays in the tree and still builds,
but it gets no new features, no releases and no listing work unless riders ask for it. The
store's only off-switch is *Remove* (there is no unpublish), and that is Jan's click — until it
happens the listing below is live at 0.9.6 with the text as transcribed. cleanjibe.org no longer
links to it. Everything after this note is history, kept because a re-listing would need it.

Title since 2026-09-02 (was `CleanJibe Field (Beta)`): "Wingfoil" belongs in both public titles
because store search shows the two side by side and the tiny DATA FIELD / DEVICE APP label is
easy to miss; "Field" stays because in the Connect IQ phone app the two would otherwise be
told apart by that label alone.

* Store page: <https://apps.garmin.com/apps/8dad33d4-e367-45a6-a4bb-9647fd6b5402>
* Type: data field · Version **0.9.5** · first submitted 2026-08-13, 0.9.5 published 2026-09-01
* Permissions: FitContributor
* Devices (`garmin/field/manifest-invite.xml`): fenix 8 (43 mm, 47 mm), fenix 8 Solar
  (47 mm, 51 mm), fenix 8 Pro (47 mm), fenix 7 / 7S / 7X, fenix 7 Pro / 7 Pro (no WiFi) /
  7S Pro / 7X Pro / 7X Pro (no WiFi)

### Description (live text)

```
Wingfoil metrics as a DATA FIELD inside a native Garmin activity profile — open beta, free, no key and no account.

OUR RECOMMENDATION: if your watch can run the full CleanJibe app (search "CleanJibe" in this store), use that instead — it records the session itself, with live speed records, auto wind estimation, a map page, pump and takeoff metrics, and a multi-page summary. This data field is the right choice only if you specifically want to keep recording with Garmin's NATIVE activity profile — for example for Garmin's own windsurf features or a profile you have customized.

What the field shows, live in your activity screens: foil state, foil time and percentage, flight count and flight timer, the last turn's outcome and score, and the tack/jibe tally. Layouts adapt to the cell you give it, from a single field up to full screen. Everything it computes is also written into the FIT file as developer fields, so the session can be analysed properly afterwards. Garmin owns the recording, the sport code, the laps and the GPS — this field only adds the wingfoil numbers on top. One limit: Connect IQ forbids a data field from touching the accelerometer, so pumping and takeoff metrics live in the CleanJibe app only.

AFTERWARDS, FREE, IN ANY BROWSER: open cleanjibe.org and drop the .fit in — the full analysis (every flight, every turn's verdict, speed records, wind axis, share card) runs locally in your browser, nothing uploaded, no account. Works on Android phones too.

It's a beta — tell us what's wrong and what's missing at github.com/JanLahmann/WingFoil/issues or info@cleanjibe.org.
```

The richer "Layouts adapt to the cell" paragraph (full-screen app-Main face, alternating
summary pages, the configurable-cell metric list) is currently only in the 0.9.5 What's New
below — fold it into the description on the next details edit if it feels missing.

Note for form edits: Garmin's edit form rejects `<` and `>` anywhere in Description/What's
New — write settings breadcrumbs with `→`.

### What's New (live text)

**0.9.6 was uploaded and approved on 3 September 2026** — live on the private listing (0.9.6, Internal 3) and the public one (0.9.6, Internal 7).

```
0.9.6: the clean jibe comes to the data field — a jibe you flew all the way through and carried your speed out of. A star, the count and clean jibes per hour now sit beside the outcome tally on the full-screen cell, get a row of their own on the paused summary, and are two more choices for any smaller cell (Garmin Connect → CleanJibe Field → Settings); the count goes into the FIT too, so it is there in Garmin Connect and on cleanjibe.org afterwards. The rate shows "--" for the first minute: one clean jibe forty seconds in is not ninety an hour.

0.9.5: the full-screen cell now shows the app's main page — giant speed, the colour ladder, tally and streak, all labeled — and you can choose what smaller cells display (Garmin Connect → CleanJibe Field → Settings). Pause the activity and the field shows your session summary. A word of honesty: the field is newer and less tested than the CleanJibe app — if you use it, your feedback is doubly welcome (github.com/JanLahmann/WingFoil/issues or info@cleanjibe.org). Where your watch supports it, we still recommend the full CleanJibe app.

0.9.3: the field is now called CleanJibe Field (same field, new name — cleanjibe.org). No functional changes; version now tracks the CleanJibe app family.

0.1.0: first invite-beta release. Data field companion to the watch app - live foil state, foil time and percentage, flights, turn outcomes and tack/jibe tally, all written to the FIT as developer fields. fenix 8, fenix 7, Enduro 2 and tactix 7/8.
```

---

## The two developer-only listings (`… - private`)

Not store listings in any public sense, but they live on the same dashboard and cost a day
of confusion once, so they are written down here.

* `CleanJibe - private` (until 2026-09-02 `WingFoil (private dev)`) —
  <https://apps.garmin.com/apps/8f4efc35-ad13-46b9-ae9d-f01f444fe05f>,
  bound to the **developer-beta** UUID `953f7547-c152-42c2-8d33-69fb59ad0bf6`
  (`garmin/manifest-dev.xml`, built with `monkey-dev.jungle`; named manifest-beta until 0.9.11). Version **0.9.4** since
  2026-09-02; before that 0.9.2 (2026-08-07 … 08-31).
* `CleanJibe Field - private` (until 2026-09-02 `WingFoil Field (private dev)`) —
  <https://apps.garmin.com/apps/da0c6cb5-502b-4623-81ed-54ae40a3bf84>,
  bound to `7e614501-d311-49c6-a68b-992b946e3d21` (`garmin/field/manifest-beta.xml`).
  Version **0.9.5** since 2026-09-02; before that 0.1.0 from 2026-08-12.

What these listings are, and what the dashboard will not tell you:

1. **"Beta App" listings never leave `Status: Pending`.** That is not a review queue — the
   listing's own banner says it: *only you will be able to download and test the app; to
   publish, upload again with another appID.* Nobody reviews them, nobody else can install
   them, and Pending is their permanent, healthy state (confirmed on the CIQ forum,
   2026-09-02). Do not wait for it to clear and do not ask Garmin about it.
2. **They take the dev-beta UUIDs only.** "The app ID within the manifest file deviates" is
   an accurate error: a RELEASE package (`b1ef484c…`) or an INVITE package (`28942317…`)
   uploaded here is refused because the listing was created from a `manifest-beta.xml`
   build. Export with `garmin/tools/package.sh` (the `-dev` package, from `monkey-dev.jungle`; and
   the dormant field's `garmin/field/monkey-beta.jungle`) — those are the only packages that fit.
3. **Their job** is an over-the-air channel to Jan's own watch for the unlocked,
   full-device-list build, nothing more. The public CleanJibe listings above carry the
   invite UUIDs; the release UUID `b1ef484c…` is reserved for the eventual non-beta public
   listing and has no store listing yet.

Their descriptions were rewritten 2026-09-02 to say what they are (developer-only builds of
the two public listings, full device list, no lock) rather than "Private beta of WingFoil";
support e-mail there is `info@cleanjibe.org` since 2026-09-02, like the public ones. Both carry `brand/cover-500-private.png` as cover — the current mark with the red PRIVATE
ribbon, regenerated 2026-09-02 (the old file still had the pre-September mark).

On the wrist the developer-only builds are called **Dev CleanJibe** / **Dev CleanJibe Field**
(`AppNameDev` in strings.xml since 0.9.11, `AppNameBeta` before) so they can be told from the public
"CleanJibe Beta" in a truncated watch list; their store version strings carry a `-dev` suffix
(`0.9.8-dev` app, Internal 20, uploaded 2026-09-07; `0.9.6-dev` field, dormant) so the two
channels never share a version string.

Naming, since 0.9.11 (docs/channels.md, "The watch"): `garmin/tools/package.sh` writes
`CleanJibe-release-<v>.iq` (b1ef484c), `CleanJibe-beta-<v>.iq` (28942317, the open beta) and
`CleanJibe-dev-<v>-devN.iq` (953f7547, the private listing). Older files in `garmin/bin/`: the
`*-beta-*.iq` up to 0.9.10 are the invite/beta UUID, the `*-devbeta-*.iq` the private one.
Listing titles to set in the store: **CleanJibe Wingfoil Watch App** (release, when opened) and
**CleanJibe Wingfoil Watch App Beta** (the existing public listing, renamed from "CleanJibe
Wingfoil Tracker (Beta)"); the names on the watch are CleanJibe / CleanJibe Beta / CleanJibe Dev.

The two listings are told apart on the wrist by their mark since 14 September 2026
(docs/channels.md, "Telling the channels apart"): the invite build's launcher icon and
splash wear a red BETA label, the dev-beta build's are mirrored (wing upper right), the
public build's are the mark as drawn. `monkey-beta.jungle` appends `resources-beta/`,
`monkey-dev.jungle` appends `resources-dev/` — since 0.9.11 the jungles are named after the
streams too.

---

## Version history

What the store shipped, recovered from this repo's git log — the store keeps only the
"What's New" text above, which does not go back past 0.9.0 for the app or 0.1.0 for the
field. Dates are the commit dates; a store release usually follows by a day.

### Watch app

| Version | Date | Commit | What it was |
|---|---|---|---|
| 0.9.3 | 2026-08-31 | `16568d5` | Pump strokes counted only inside real pumping bursts, so the totals match the phone. Renamed to CleanJibe. |
| 0.9.2 | 2026-08-31 | `2b3bc66` | The map page becomes the app's own drawing (works while paused, on every watch); all text full white, bigger numbers. |
| 0.9.1 | 2026-08-30 | `b891e08` | The fenix 8 crash: the map page is pushed, never switched to. Not separately listed in the store's What's New. |
| 0.9.14-dev3 | 2026-09-19 | — | **The sender keeps trying.** The field test of dev2: page 0 failed while the phone was out of reach, and at save the phone took it but no acknowledgement came back; nothing reopened the retries. Now: a pacer every 20 s while pages wait, the retry budget reopens at save, at app start, on the connected edge and on a settings change; a transmit that answers neither way is dropped after 15 s; a recording without a fix is not sent at all. Results page logs "stuck" too. |
| 0.9.14-dev2 | 2026-09-19 | — | **The direct transfer** (private listing only): the recording crosses to the phone in 8 KB pages, one in flight, acknowledged page by page (docs/transfer-format.md; the phone side is the iPhone dev build 80). Uploaded 19 Sep to the private listing (Internal 33). Gated by the same "send to phone" switch as the card. The probe loses its 16 KB item and sends its three pages as a chain — both crashed the app on 19 Sep. The probe's Results page logs each page landed ("cjr 4/13 ok", "cjr whole"). |
| 0.9.14-dev1 | 2026-09-19 | — | **The link probe** (private listing only): a hidden item under Wind from that sends 1, 4, 8 or 16 KB, or three 8 KB pages back to back, to the phone and logs the time to onComplete — the first experiment of docs/direct-transfer.md (issue #14). Nothing else changed; 0.9.14 is not uploaded to the public listing. Uploaded 19 Sep to the private listing (Internal 32). |
| 0.9.13 | 2026-09-17 | — | **The fenix 5 Plus family's rows stop overprinting.** A store user on a fenix 5X Plus (Leo, 17 Sep): "the time is placed nearly over the speed". Verified in the simulator on all 17 screens: the clock on the main giant's unit, PAUSED drawn as six empty boxes, the RECORDS captions on their numbers, SAVED on the verdict's 56 %. One cause: every band was stacked on "ink = 3/4 of the line", true where a number line carries leading (fenix 8: 153 of 210 px) and false on the fenix 5 Plus family's Chronos number fonts (ascent = line, no leading). Ink is the firmware's ascent now, floored at the old 3/4 so no other glass moves; a word never walks the number ladder; the main giant's unit/caption block owns the band when it is the taller box; the pair band keeps the grid's gutter. Uploaded 17 Sep 21:25 to the public beta listing (Internal 21) and as 0.9.13-dev1 to the private one. |
| 0.9.12 | 2026-09-17 | — | **Discard no longer traps the rider.** 0.9.11 asked "Discard session?" with the firmware's Confirmation dialog; answering it left the app stuck until a watch restart (reports from a fenix 5 Plus and Jan's fenix 8, 16/17 Sep): the firmware pops the confirmation after onResponse, so our pop took the confirmation, the switch replaced the menu with the start page, and the firmware's pop then removed the start page, leaving a recording view over a session that no longer existed. The question is a two-item menu now (Keep / Discard), the shape the wind menu uses. Uploaded 17 Sep to the public beta listing and as 0.9.12-dev1 to the private one. |
| 0.9.11 | 2026-09-15 | — | **fenix 5 Plus / 5S Plus / 5X Plus** join the device list: minApiLevel down from 5.0.0 to 3.3.3 (every newer API was already behind a `has` check; two TrackDraw methods lost parameters for the 3.x runtime's limit of nine), 25 Hz accelerometer into the pump detector's own 25 Hz grid, layout suite run on fenix5plus. The plain fenix 5/5S (128 KB) and 5X stay out. Every buzz also paints (Jan, 15 Sep): a 1.5 s full-glass flash with glyph and word for a resolved turn (FLEW / TOUCH / FELL in the ladder's inks), a clean jibe (star, clean ink), a dry-streak mark (5, then every ten) and a new longest flight; a 0.7 s ring for a pumped takeoff; then a 20 s afterglow line at the top of every page naming the turn (JIBE · flew). One switch, Show alerts on screen. Also: **Reset pages to defaults**, a settings switch that writes the seven shipped pages back and turns itself off (0.9.11-dev2). 0.9.11-dev3 (uploaded to the private listing 15 Sep 14:30): the fenix 5 Plus family and the small-ladder pair band. 0.9.11-dev4 (uploaded to the private listing 15 Sep 18:20, the audit's watch findings): the Turns header says flew · touch · fell (it said tack / jibe over the outcome ladder); the Main tally carries the words flew / touch / fell after its counts where the row has room, dropped first when it has not; the start page says START records · BACK saves and the paused banner PAUSED · BACK saves where they fit; the summary says NOT SAVED in red when the FIT was not written; Discard asks once. Dev first; the beta listing on 15 Sep 18:35 for Jan's fenix 5 Plus friend, after Jan's fenix 8 ran dev4 (a reboot after the install was needed). |
| 0.9.10 | 2026-09-13 | — | Uploaded to the private listing as 0.9.10-dev (Internal 22) and, with the splash and the larger mark, 0.9.10-dev2 (Internal 23) on 13 Sep for Jan's device test; the public listing waits for that test. The logo, more visibly: a splash page with the mark and the wordmark on the first launch after an install or update (1.5 s, any key skips it), and a larger mark on the start page (56 px on a 454 px glass, 44 px on the 360 px Venu 2S where 50 ran off). Nine more watches: Venu 2 / 2S / 2 Plus / 3 / 3S, vivoactive 5 / 6, Instinct 3 AMOLED 45 / 50 mm (all 768 KB, CIQ ≥ 5.0; the Instinct 2 family and Instinct 3 Solar have 96–128 KB and cannot run the app; the rectangular Venu X1 waits for a rectangular layout). Two layout findings on the way in, both fixed: the hero fitter rounded an odd ink height down and put the giant half a pixel over the fit radius on the Venu 3's fonts; the 360 px Venu 2S takes the icon54 mark cut. The phone-rendered ground under the breadcrumb (docs/watch-map-snapshot.md, GitHub #4): the iPhone app sends a 120×120 water/land/road mask of the rider's two most-ridden spots over the companion link; the live map page and the post-save Track page draw it under the trail, framed on the spot's 3 km box. No firmware map view involved. The 0.9.9 "Map after save" switch stays for firmware retests. Private listing first, for Jan's device test. 0.9.10-dev3 (uploaded to the private listing 14 Sep): the splash lockup gets a third line, cleanjibe.org in grey under the wordmark — where to find us, not only who we are (Jan); the round-glass fit test covers the new line on fenix 8 and Venu 2S. |
| 0.9.9 | 2026-09-09 | — | Also: "Map after save (experimental)", off by default — **tested 13 Sep on a fenix 8 (SW 23.31): the app dies when the page opens; leave it off, remove in the next release** — START on the summary's Track page opens the firmware's MapTrackView over the saved track, the first trial of the native map outside a recording (GitHub #4). The quiet tail (engine 0.17.0): a clean candidate is held for 10 s past the sweep and withdrawn on a 1 s loss of the foil or a dunked wrist; `EVENT_CLEAN_SETTLED` carries the answer and the buzz. Corrected the docs: the watch never had the phone's pump rung. |
| 0.9.8 | 2026-09-07 | — | Engine 0.14.0: peak floor 18°/s so carved jibes are detected (the 12 s sweep was measured and rejected: +6 jibes, −26 clean). Uploaded the same day as 0.9.7 (public Internal 16, private 0.9.8-dev Internal 20). |
| 0.9.7 | 2026-09-07 | `347669a` | The 90° classification floor for tacks and jibes (engine 0.13.0), and the companion card's foil % on timer time. Uploaded to both listings. |
| 0.9.6 | 2026-09-05 | `459ae1d` | A clean jibe has to fly through: the star, the clean count and CPH drop jibes that touched down or fell in after the sweep (engine 0.12.0 on the phone and the web, same day). Uploaded to both listings; public Internal 14 pending review. |
| 0.9.5 | 2026-09-03 | — | The clean jibe on the wrist: star, count, CPH, its own three-tick buzz. Public Internal 13, approved 3 Sep. |
| 0.9.4 | 2026-09-01 | — | Open beta, no unlock key; 17 more watches; the CleanJibe mark on the start screen. |
| 0.9.0 | 2026-08-30 | `e2cadfe` | The watch works the wind axis out for itself and classifies tacks and jibes live. |
| 0.8.2 | 2026-08-30 | `3ccec57` `b60769b` `8390d1b` | The foil min/km table and the seventh page; the owner's screen-review round. |
| 0.8.1 | 2026-08-30 | `6619d4f` | Summary fixes the store had already swallowed 0.8.0 without. |
| 0.8.0 | 2026-08-29 | `5678a2f` | Streaks that count the swims, honest wind absence, merged attempts, the big-text watch UI. |
| — | 2026-08-13 | `5c9299f` | Takeoff HR-cost metric and the watch half of the companion link. |
| — | 2026-08-12 | `b380582` | fenix 7 family support (13 devices) and the MIP layout fixes. |
| — | 2026-08-11 | `cc64066` | The `WingFoilCore` barrel split out, and the big-value layout. |
| — | 2026-08-07 | `b8bae71` | First cut: the fenix 8 watch app, phase-1 feature set. |

### Data field

| Version | Date | Commit | What it was |
|---|---|---|---|
| 0.9.5 | 2026-09-01 | this release | The full-screen cell became the app's main page (labelled), a session summary took over while the timer is stopped, and the smaller cells' rows became settings. First field build whose manifests carry a `version` attribute at all. |
| 0.9.4 | 2026-09-01 | `8d014dc` | The chord-placement fix (no cell clips at the bezel any more) and the fenix 7 / Tier A product list on all three channels. |
| 0.9.3 | 2026-08-31 | `442ffbe` | Renamed to CleanJibe Field; the version now tracks the app family. No functional change. |
| 0.1.0 | 2026-08-11 | `cc64066` | First invite-beta release, alongside the `WingFoilCore` barrel it shares with the watch app. |

The field's What's New makes the same "Enduro 2 and tactix 7/8" claim as the watch app's
description, and it is true for the same reason (`fenix7x` and `fenix847mm` are those
watches). The field's **release** manifest was the one with a real gap: it declared only the
five fenix 8 products, so a fenix 7 could install the invite field but not the public one.
0.9.4 puts the fenix 7 family and all seventeen Tier A products on all three field channels,
matching the watch app.

## Store assets

`garmin/store/` also holds `cover-500.png` (the 500 px store cover) and `screen-speed.png`.
The rest of the screenshots are generated — see `garmin/screenshots/`.
