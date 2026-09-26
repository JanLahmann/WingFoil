# The Connect IQ store listings

**Archival, not a draft.** This file is the source of truth for what the two Connect IQ
listings say *today* — transcribed verbatim from the live store (app on 2 September 2026 at
0.9.4, field on 1 September at 0.9.5), because until now the only copy of this text lived in the Connect IQ developer
console and nowhere in git. Edit it when the store is edited, in the same commit; do not
rewrite it here and leave the store behind.

Rewrite drafts are a separate thing, with one exception written down where it sits: the
watch app's description carries the 26 September 2026 draft for Jan's sign-off.

Both apps: developer **JanRL** (`7d829c3a-3343-46f5-b946-4556e4579f53`), support
`info@cleanjibe.org`, website `https://github.com/JanLahmann/WingFoil`, free,
open beta, English only.

---

## Watch app — `CleanJibe Wingfoil Tracker (Beta)`

* Store page: <https://apps.garmin.com/apps/e77867b5-e972-4eb2-be1b-90077cfac806>
* Type: device app · Version **0.9.19** on the store, **42** products (uploaded 23 Sep 2026, Internal 26; 0.9.18 on 22 Sep, Internal 25; 0.9.17 on 21 Sep, Internal 24; 0.9.16 the same day, Internal 23; 0.9.15 on 20 Sep, Internal 22; 0.9.13 on 17 Sep, Internal 21; 0.9.12 the same day; 0.9.11 on 15 Sep; web/tools/make_devices.py reads this line, keep its shape) · first submitted 2026-08-12, 0.9.4 released 2026-09-01
* Permissions: Fit, SensorLogging, Communications, Positioning, FitContributor, Sensor
* Devices (`garmin/manifest-beta.xml`, identical to the release and dev manifests; the count and
  the family grouping are generated into `docs/copy/garmin-devices.json`): 42 products at 0.9.11,
  unchanged through 0.9.19 —
  fenix 8 / 7 / 5 Plus families, epix 2 / 2 Pro, Forerunner 255 / 265 / 570 / 955 / 965 / 970,
  MARQ 2, Enduro 2 / 3, D2 Mach 1 / 2, Descent Mk3, Venu 2 / 3, vívoactive 5 / 6, Instinct 3
  AMOLED — plus **D2 Mach 1 Pro**, which was missing from this list: `garmin/manifest.xml`'s
  own comment says `epix2pro51mm` answers for it as well as for tactix 7 – AMOLED Edition; the
  tactix 7 (plain) and quatix 7X Solar twins ride on `fenix7x`'s id and quatix 7 Sapphire on
  `epix2`'s — none of the four carries a product id of its own, which is what "the tactix /
  quatix twins those product ids cover" was already saying, just one device short.
* Minimum firmware: one floor for the whole app, `minApiLevel="3.3.3"` in `garmin/manifest.xml`
  — Connect IQ 3.3.3 or newer, which Garmin Connect Mobile installs automatically, so this only
  bites a watch nobody has updated in years. The oldest family on the list, fenix 5 Plus /
  5S Plus / 5X Plus, got Connect IQ 3.3.3 in firmware 19.10 (2020); every fenix 8 has shipped
  with newer firmware than that from day one.
* Battery: **no measured figure exists yet.** Garmin's own multiband-GPS spec puts a fenix 8
  at roughly 30 hours in that mode (`docs/plan.md`), which is where a two-hour session's
  percentage would come from if this were Garmin's own recording — it isn't; CleanJibe adds
  its own accelerometer work and companion-link traffic on top, so that number is not this
  app's number. The test, once, on a representative watch: charge to 100%, start a normal
  CleanJibe recording with GPS (multiband where the watch has it) for a continuous 2 hours —
  no pauses, ridden as normal, phone connected as usual — then read the battery percentage
  remaining and report the drop. A fenix 8 (AMOLED) bounds the worst case; a fenix 5 Plus
  (MIP) the best, if a tester has one. Until that number exists, the listing says nothing
  about battery.
* Open beta since 0.9.4: no unlock key. The invite lock (ADR-012) is compiled out of every
  channel now; the invite UUID `28942317…` is simply the public listing's UUID.

Transcribed from the live store on 2026-09-02. The earlier "TODO (pending edit)" items (the
`WingFoil - Invite Beta` breadcrumb and the old GitHub Pages URL) no longer exist in the live
text — the whole description was rewritten for the open beta.

### Description (live text)

**Draft ahead of the store, 26 September 2026, for Jan's sign-off.** The block below is
the rewrite in the team voice of `docs/voice.md`, and it is *not* on the store yet. It goes
into the Connect IQ form by hand at the next upload, and this note goes the day it does.
The text it replaces, which the store shows today, is in git at `2c12c1c`, this file.

What changed and why:

* **Rider first, mechanics after** (voice rule 2): what the watch tells you on the water and
  on its pages comes first. How it records, the browser and the iPhone app come after.
* **It says honestly that this is the beta.** The public listing is the beta stream
  (docs/channels.md, "The watch — the same three streams"). A release listing, *CleanJibe
  Wingfoil Watch App*, opens only when the iPhone app is on the App Store.
* **The iPhone paragraph** says the Analyzer is on its way to the App Store and points at
  TestFlight until then. The day 1.0.1 is on sale, the last two sentences become one: *Find
  it on the App Store.*
* **Nothing from the dev stream**: no shore map from the phone, no direct transfer, no page
  editor. The eight pages, the seven show/hide switches and the large-text set are what
  0.9.19 ships.
* Every sentence is register 1, at most 20 words, with no dash, semicolon or parenthesis.
  `docs/copy/check_voice.py` reads this block.
* **2831 characters.** The form rejects `<` and `>`, and there are none.

```
Did you fly through that jibe? CleanJibe on your Garmin tells you while you ride. It knows when you are up on the foil, counts every flight, and gives every turn its verdict. Flew through, touchdown, or fell in.

THIS IS THE BETA

This listing is the CleanJibe beta. It is free and open to anyone, with no key and no account. New versions come here first, so a threshold can still move between them. Tell us what looks wrong at cleanjibe.org/invite, or with Contact Developer on this page.

NEW TO IT?

cleanjibe.org/start walks you through a 20-minute test on land. Record a few minutes, bring the file onto your phone, and see what you should see. The page also says where to send what you find.

ON THE WATER

The watch knows when your board is up on the foil. It counts every flight and every touchdown while you ride.

Every turn gets its verdict as you make it: clean, flew through, touchdown or fell in. A buzz and a flash on the glass tell you at once.

Your tacks and jibes are counted apart, each with how many you flew through. Your dry streak shows how many turns in a row you stayed dry.

Your best 2 s and best 10 s show live, and the watch buzzes on a new personal best.

After a few minutes of riding, the watch works out the wind direction by itself. A ~ marks the estimate, and the wind menu always overrides it.

Your pump strokes and takeoff attempts come from your wrist's movement.

YOUR PAGES

Eight pages show your speed, your session, records, turns, and tacks and jibes. Then come the map with your trail, your time on the foil and the clock. Switches in the app's settings hide the pages you never read. Large text swaps them for five big screens, one number each. After you save, a full summary waits for you.

HOW IT RECORDS

The watch records a Windsurf activity with a lap for every flight. Your session no longer shows up in Garmin Connect as a walk. GPS records every second, multiband where your watch has it, and auto-pause is built in.

Raw accelerometer logging is off by default. Switch it on only for deep analysis on the phone. It makes the file about 20 times larger, and the transfer after saving takes minutes.

AFTERWARDS, IN ANY BROWSER

Open cleanjibe.org and drop in the FIT file. The same analysis runs right in your browser, free, with no upload and no account. You get the track, every flight and every turn with its verdict. Your speed records, the wind axis and a share card are there too. Keep a library there and it builds your all-time records and season trends. It works on an Android phone too, and it also reads Garmin's own Windsurf activity and GPX files.

ON AN IPHONE

CleanJibe Wingfoil Analyzer gives you maps, turn pages, replay, records and trends. It is on its way to the App Store. Until then, its beta is open on TestFlight at testflight.apple.com/join/nygqGGcn.
```

### What's New (live text)

**0.9.19 uploaded 23 September 2026** (public listing, pending approval, Internal 26). The live field holds three paragraphs (0.9.19, 0.9.18, 0.9.17 — the 0.9.18 paragraph is the release-notes entry's lines joined, then the two below). Text of 0.9.17 as submitted on 21 September:

```
0.9.17: Tacks and jibes, counted apart. A Tacks and jibes page after Turns: each count, with how many of them flew through. In the large-text set too, one screen each. And the dunk read right: a watch that settles at a new height after a swim no longer reads the rest of the session as falls.

0.9.16: Large text. Settings → Data screens → Large text gives five screens with one big number and its word: speed, foil share, turns, time, best 2 s. The page editor leaves the store build; the standard screens stay as they were. After a save, the flights page is the same foil table you saw while riding. The live verdict is called Speed kept now, the word the phone uses for the same number.

0.9.15: Eleven traps closed. A map slot from an older build no longer throws every frame, a heading value out of range no longer stalls the watch, settings from Garmin Connect are clamped to their ranges, a null in an accelerometer batch is skipped, a thirty-hour session keeps its track. A run that never reached its end is counted and told to the phone.
```

### Listing images

Read against the 0.9.19 UI (`Read`, frame by frame — no simulator run, no new art):

- `garmin/store/cover-500.png` (2026-08-12, the 500 px store cover) is the brand mark only, no
  on-watch UI, so no layout change touches it. **Keep**, live on the store today.
- `garmin/store/cover-500-beta.png` (added 26 Sep 2026): this listing *is* the beta stream, so
  its cover should say so the way the app and watch icons already do — the same red-strip
  BETA mark, cut from `brand/icon-tile-beta-1024.png` (`brand/tools/make_channel_marks.py`)
  resized to 500×500, no new art. **Not uploaded by this pass** — swap it in for
  `cover-500.png` at the next cover edit, and update this note the day it does.
- `brand/store-shots-09/` (committed 2026-09-01, `c4fd9f7`, "store screenshots for the 0.9.4
  listing") is the *only* on-device screenshot set in git — nothing newer was ever checked in;
  the layout-review family sheets (docs/testing.md, "the short set") land in a scratch
  `<outdir>` each round and are never committed. Checked one by one:
  - `01-main-454.png` — **stale, do not use.** No clean-jibe star (shipped 0.9.6); it shows a
    tally a 0.9.19 rider will never see.
  - `02-turns-454.png` — **stale, do not use.** It's the pre-0.9.18 Turns page: a "68% flew ·
    P29/S22" share row and the wind bearing spelled out ("~NNE") as the header, both removed
    in 0.9.18's redesign (this file's 0.9.18 row; `docs/algorithms/turns.md`). A page nobody
    running 0.9.19 will ever see.
  - `03-foil-454.png` — usable with one wording caveat: it still says "tot", which 0.9.18
    renamed to "total" when it dropped the flight count from the same row. Cosmetic only.
    **Use.**
  - `04-records-454.png` — untouched by 0.9.16–0.9.18. **Use.**
  - `05-sum-takeoffs-454.png` — already the two-row form 0.9.18's fix asserts ("… to foil" /
    "+N bpm" on separate lines). **Use.**
  - `06-sum-verdict-454.png` — a different number (session foil-time share, not turn success),
    untouched by the "Speed kept" rename. **Use.**
  - `07-start-454.png` — the start page's copy hasn't moved. **Use.**
  All seven are 454×454 (`fenix847mm`, the widest glass and Jan's own watch, per
  docs/testing.md) — the size the store slots have taken since the 0.9.4 upload, so the four
  kept here (03, 04, 05, 06, 07) need no resize.
- **Owed, not done here:** a real capture (`garmin/screenshots/tools/capture.sh <device>
  <outdir>` then `sheet.py`, at minimum the short set on `fenix847mm`) to replace 01-main and
  02-turns before the next screenshot upload — 0.9.16–0.9.18 moved the layout engine itself
  (row stack, ink bands), which is what the full 29-family round is owed for anyway
  (docs/testing.md). Out of scope for this pass: no simulator run, no new art.

### Next watch build

- **Port the phone's early-touch rule (engine 0.25.0, ADR-035).** The watch currently calls
  any sub-floor sample anywhere in a flight end's 30 s window a touchdown; the phone only
  counts one landing within `turnOutcomeLookahead` (12 s) of the exit, so a slog that brushes
  the floor between 12 s and 30 s reads as a glide-out on the phone and a broken flew-through
  streak on the wrist (`docs/algorithms/turns.md`, "Not ported yet"). The port is one
  condition in `TurnDetector._flightEndTick`: set `_endTouched` only while `_clockS -
  _endStartS <= LOOKAHEAD_S`. Not done here — a line for the next watch build, not code.

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
| 0.9.19 | 2026-09-22 | Internal 26 | **The watch says what the phone says about a turn.** A fall the turn caused is the turn's fall on the wrist too (ADR-032): a rider who mushes out of a jibe and never gets going again is followed for 30 s instead of 12, so the stop he coasts to is that jibe's `fell in` and not a `touchdown` the phone later contradicts — on the 2026-08-07 golden five of 32 turns flip and the wrist's ladder becomes the phone's, 11 flew / 8 touched / 13 fell. Recovery still closes the window where it always did, the straight-line flight-end window follows the same clock, and the fall is booked once. No page changed: the pages already print the phone's four (★clean · flew · touched · fell) since 0.9.18, and *Speed kept* is now only the name of FIT field 34's Garmin Connect row, which is what that number is. Uploaded 23 September 2026 (public listing, pending approval). |
| 0.9.19-dev2 | 2026-09-23 | Internal 41 | **The 0.9.19 wrist, on the dev stream.** The public 0.9.19 plus the dev transfer (wrist stream, packed pages); the retired invite lock is gone. Uploaded 23 September 2026 (private listing). |
| 0.9.18 | 2026-09-21 | Internal 25 | **Jan's layout review of the fenix 8 pages.** Every page read off a numbered sheet and answered one at a time: the Turns page is a legend, one wide ladder row on the equator (clean · flew · touch · fell) and three narrow rows under it — CPH and the "% flew" share are gone and the wind bearing is a mark; Tacks & jibes is two of those rows with its words above and below them; the large-text set is five screens, giant first and word last, and the giant leaves the bitmap ladder where the watch has a vector face; the clock page drops the word "timer" and both numbers grow; Story puts "turns" under its dots; Map's distance is a number again; the foil table says "total" and drops the flight count; and after a save the records and turns pages are their live twins. Two principles behind all of it: on a round glass the widest line belongs on the equator, and numbers get larger while words get smaller. **Plus seven show/hide switches**, one per data screen, in every stream — the large-text and after-save sets follow them, because they are the same pages — and **the tack/jibe numbers rebuilt**: an opposed pair of reaches has a wind axis now (the engine's 0.23.0 bisector), and every turn is re-typed when that axis changes, so the rows on the Tacks & jibes page add up and a jibe ridden before the estimator spoke still gets its star. Uploaded 22 September 2026 (public listing, pending approval). |
| 0.9.18-dev1 | 2026-09-22 | Internal 40 | **The wrist stream, and the page the fenix 5 Plus family can carry.** The direct transfer gains stream 1 — the 25 Hz wrist magnitudes, inside the windows the watch flagged, held to a fixed byte budget and sent after the recording has crossed whole (docs/transfer-format.md §2b, ADR-031); the phone files it beside the session and re-derives, so the pump and takeoff numbers a direct session could not have start reading. Pages below Connect IQ 6.0.0 now pack four payload bytes per 32-bit Number, which takes an 8 KB page from 40 KB of wire to 10 — untested on hardware until a 5 Plus runs the probe, whose Results page now names the mode and the milliseconds. The progress line says `wrist 2/8` after `phone 4/13`, and the buzz waits for the last stream. Private listing only; the public 0.9.18 is unchanged. Uploaded 22 September 2026 (private listing). |
| 0.9.17 | 2026-09-21 | — | **A Tacks & jibes page.** A page after Turns with each count and how many of that kind flew through, live and after the save, plus two more screens in the large-text set. Jan, from a tester practising tacks. Not uploaded. Uploaded 21 Sep to the public listing (Internal 24), with the settle release for a re-anchoring barometer. |
| 0.9.17-dev8 | 2026-09-21 | — | The same, on the private listing, with the direct transfer. Pair with iPhone dev build 96. Uploaded 21 Sep (Internal 39). |
| 0.9.16 | 2026-09-21 | — | **Large text, and the page editor leaves the store build.** A second page set of five pages, one big number and its word each (speed, foil share, turns, time, best 2 s), chosen under Settings → Data screens; the page editor is `(:dev)` only from here; after a save the flights page is the live foil table, not a second layout of the same numbers; a phone line on the summary while the direct transfer's pages cross; the live verdict says Speed kept, the phone's word for the same number. 29 family sheets photographed and read clean on 21 Sep (docs/testing.md), then uploaded the same day to the public listing (Internal 23). |
| 0.9.16-dev7 | 2026-09-21 | — | The same, on the private listing, with the direct transfer. Pair with iPhone dev build 94. Uploaded 21 Sep (Internal 38). |
| 0.9.15 | 2026-09-20 | — | **Eleven traps closed, and a crash breadcrumb.** The first fuzz of the watch app (docs/testing.md): a heading of a billion radians looped the watchdog to death, a map slot written by an older build threw on every frame, a negative slot index and a 20 KB spot name reached Storage, a null inside an accelerometer batch crashed the pump detector, a thirty-hour session overflowed the track stride, settings from Garmin Connect were never clamped. Every fix is a guard, because a division by zero and an index past the end cannot be caught on this runtime. A run that never reaches its end is counted and the count rides the card to the phone (`cx`). No layout change, so no new family sheet. Uploaded 20 Sep to the public listing (Internal 22). |
| 0.9.15-dev6 | 2026-09-20 | — | The same, on the private listing, with the direct transfer. Uploaded 20 Sep (Internal 37). |
| 0.9.14-dev5 | 2026-09-19 | — | **The stream carries the clock.** Schema 2: a 20-byte header with the watch's UTC offset in minutes, because the first direct session (16:52) landed at 15:52 — the phone had only the longitude to guess by, which is the solar offset and an hour out under summer time. Pair with iPhone dev build 87, which reads both schemas. Uploaded 19 Sep to the private listing (Internal 36). |
| 0.9.14-dev4 | 2026-09-19 | — | **The ack is read in its flat shape.** The field test of dev3: every page reached the phone ("page 1 of 3 again", three times) and every acknowledgement stayed on the phone, because Garmin's phone SDK does not carry a nested array. The phone sends three keys now and a comma-joined need list; the watch reads both shapes. Results page logs an ack it refuses ("cjr ack sid?"). Pair with iPhone dev build 85. Uploaded 19 Sep to the private listing (Internal 35). |
| 0.9.14-dev3 | 2026-09-19 | — | **The sender keeps trying.** The field test of dev2: page 0 failed while the phone was out of reach, and at save the phone took it but no acknowledgement came back; nothing reopened the retries. Now: a pacer every 20 s while pages wait, the retry budget reopens at save, at app start, on the connected edge and on a settings change; a transmit that answers neither way is dropped after 15 s; a recording without a fix is not sent at all. Results page logs "stuck" too. Uploaded 19 Sep to the private listing (Internal 34). |
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

`garmin/store/` also holds `cover-500.png` (the 500 px store cover, live today), `cover-500-beta.png`
(the same mark with the beta app icon's red-strip label, cut 26 Sep 2026 for the next cover
edit — see "Listing images" above) and `screen-speed.png`.
The rest of the screenshots are generated — see `garmin/screenshots/`.
