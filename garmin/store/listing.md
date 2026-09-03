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
* Type: device app · Version **0.9.4** (Internal 12) · first submitted 2026-08-12, 0.9.4 released 2026-09-01
* Permissions: Fit, SensorLogging, Communications, Positioning, FitContributor, Sensor
* Devices (`garmin/manifest-invite.xml`): the full Tier A list — fenix 8 family, fenix 7
  family, epix 2 / 2 Pro, Forerunner 255 / 265 / 955 / 965 / 970 / 570, MARQ 2, Enduro 2 / 3,
  D2 Mach 1 / 2, Descent Mk3 43 mm (and the tactix / quatix twins those product ids cover)
* Open beta since 0.9.4: no unlock key. The invite lock (ADR-012) is compiled out of every
  channel now; the invite UUID `28942317…` is simply the public listing's UUID.

Transcribed from the live store on 2026-09-02. The earlier "TODO (pending edit)" items (the
`WingFoil - Invite Beta` breadcrumb and the old GitHub Pages URL) no longer exist in the live
text — the whole description was rewritten for the open beta.

### Description (live text)

```
CleanJibe tells you what your wingfoil session actually did: how much of it you spent on the foil, how long each flight lasted, your speed records, and — for every turn — whether you flew through it, touched down, or fell in.

OPEN BETA, FREE. Install and ride — no key, no account. It's a beta: tell us what's wrong and what's missing at cleanjibe.org/invite, or use Contact Developer on this page. The detection thresholds are still being tuned and may change between versions; they are published, with the reasoning, at github.com/JanLahmann/WingFoil.

ON THE WATER
- Live foil state: it knows when the board is up on the foil, and counts every flight and touchdown while you ride.
- Every turn scored as you make it — flew through, touched down, or fell in — with your no-fall streak and your tack/jibe tally on screen.
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

**0.9.5 was uploaded and approved on 3 September 2026** (listing shows 0.9.5, Internal 13); everything under it is the store's own text as transcribed on
2 September 2026.

```
0.9.5: the clean jibe is now on your wrist. The Turns page and the post-save summary carry a star, the number of clean jibes you have landed, and your CPH — clean jibes per hour — and a clean jibe now gets its own rising three-tick buzz instead of the plain fly-through tick, so you can tell one from the other without looking. If you would rather have the old buzz back, turn it off under Garmin Connect → CleanJibe → Settings.

0.9.4: THE BETA IS NOW OPEN — no unlock key needed. Install and ride. Also new: 17 more watches supported (epix 2 family, Forerunner 955/965/970/255/265/570, MARQ 2, Enduro 3, D2 Mach, Descent Mk3), the CleanJibe mark on the start screen, "clean jibe" labels for turns you fly through carrying your speed, and the accelerometer-logging setting now explains its transfer cost (off by default).

0.9.3: the app is now called CleanJibe (same app, new name — cleanjibe.org). Pump strokes are counted only in real pumping bursts, so totals drop to realistic numbers and match the phone and browser analysis.

0.9.2: bigger and brighter - all text full white, larger numbers on nearly every page, and the map page drawn by the app itself so it works on every watch and while paused.

0.9.0: the watch works out the wind direction by itself after a few minutes of riding (~ marks the estimate, the wind menu always overrides) and classifies tacks, jibes and port/starboard entries live.

Garmin keeps your stored page settings across updates — existing installs can pick new layouts in Garmin Connect settings or reinstall.
```

---

## Data field — `CleanJibe Wingfoil Field (Beta)`

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
  (`garmin/manifest-beta.xml`, built with `monkey-beta.jungle`). Version **0.9.4** since
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
   build. Export with `monkeyc -e -r -f monkey-beta.jungle …` (and the field's
   `garmin/field/monkey-beta.jungle`) — those are the only packages that fit.
3. **Their job** is an over-the-air channel to Jan's own watch for the unlocked,
   full-device-list build, nothing more. The public CleanJibe listings above carry the
   invite UUIDs; the release UUID `b1ef484c…` is reserved for the eventual non-beta public
   listing and has no store listing yet.

Their descriptions were rewritten 2026-09-02 to say what they are (developer-only builds of
the two public listings, full device list, no lock) rather than "Private beta of WingFoil";
support e-mail there is `info@cleanjibe.org` since 2026-09-02, like the public ones. Both carry `brand/cover-500-private.png` as cover — the current mark with the red PRIVATE
ribbon, regenerated 2026-09-02 (the old file still had the pre-September mark).

On the wrist the developer-only builds are called **Dev CleanJibe** / **Dev CleanJibe Field**
(`AppNameBeta` in the two strings.xml, since 2026-09-03) so they can be told from the public
"CleanJibe Beta" in a truncated watch list; their store version strings carry a `-dev` suffix
(`0.9.5-dev`, `0.9.6-dev`) because the manifests did not move.

Naming trap in `garmin/bin/`: files called `*-beta-*.iq` from 0.9.4 on (`CleanJibe-beta-0.9.4.iq`,
`CleanJibeField-beta-0.9.x.iq`) carry the **invite** UUID, not the dev-beta one — "beta" there
meant the "Invite Beta" listing. The dev-beta exports are the `*-devbeta-*.iq` files.

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
