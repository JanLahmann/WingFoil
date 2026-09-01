# The Connect IQ store listings

**Archival, not a draft.** This file is the source of truth for what the two Connect IQ
listings say *today* — transcribed verbatim from the live store on 1 September 2026, at
0.9.3, because until now the only copy of this text lived in the Connect IQ developer
console and nowhere in git. Edit it when the store is edited, in the same commit; do not
rewrite it here and leave the store behind.

Rewrite drafts are a separate thing and are not in this file. Two lines in each listing are
already known to be wrong and are marked `TODO (pending edit)` inline below — they are
transcribed *as they stand*, wrong, because that is what this file is for.

Both apps: developer **JanRL** (`7d829c3a-3343-46f5-b946-4556e4579f53`), support
`jan@lahmann-online.de`, website `https://github.com/JanLahmann/WingFoil`, free,
invite-only beta, English only.

---

## Watch app — `CleanJibe Wingfoil Tracker - Invite Beta`

* Store page: <https://apps.garmin.com/apps/e77867b5-e972-4eb2-be1b-90077cfac806>
* Type: device app · Version **0.9.3** · first submitted 2026-08-12, current version released 2026-08-31
* Permissions: Fit, SensorLogging, Communications, Positioning, FitContributor, Sensor
* Devices (`garmin/manifest-invite.xml`): fenix 8 (43 mm, 47 mm), fenix 8 Solar (47 mm,
  51 mm), fenix 8 Pro (47 mm), fenix 7 / 7S / 7X, fenix 7 Pro / 7 Pro (no WiFi) / 7S Pro /
  7X Pro / 7X Pro (no WiFi)

### Description (live text)

```
Wingfoil tracking for fenix 8, fenix 7, Enduro 2 and tactix 7/8 - invite-only beta. Records sessions as Windsurf sport with live flight detection (tunable thresholds), per-flight laps, speed records (2s/10s live), turn detection with tack/jibe classification and outcome markers, pump-stroke and takeoff-attempt counting, configurable data screens (speed, session, records, turns, map with track, on-foil timeline, clock), auto-pause, PB alerts, GNSS at 1s recording (multiband where the watch supports it), and accelerometer logging for detailed pump analysis on the phone.

THIS BETA IS INVITE-ONLY. On first start the watch shows an 8-character request code. Send that code to the developer (Contact Developer on this page) and you will receive your personal unlock key. Enter the key in Garmin Connect under Connect IQ, WingFoil - Invite Beta, Settings, "Unlock key". The app unlocks immediately and permanently on your watch. Without a key the app only shows the lock screen - please request a key instead of leaving a review about it.

New in 0.9.0: the watch now works out the wind direction by itself after a few minutes of riding (a ~ marks the estimate; the wind menu always overrides) and then classifies tacks, jibes and port/starboard entries live. Redesigned screens from a rider's review: best-10s as the main number, turn outcomes and your no-fall streak at a glance, a foil min/km table, a map page with breadcrumb, and a full multi-page summary after saving. Raw accelerometer logging is now OFF by default in this beta so transfers stay fast - turn it on in settings if you want deep pump analysis on the phone.

Analyze your sessions in any browser, free: https://janlahmann.github.io/WingFoil - the same analysis engine running locally on your device, nothing uploaded, with a session library, records and trends. Works on Android phones too. An iPhone companion app with the full analysis - maps, turn forensics, records and trends - is in TestFlight beta; contact the developer for an invite.
```

**TODO (pending edit), two lines above:**

1. `Connect IQ, WingFoil - Invite Beta, Settings, "Unlock key"` — the app was renamed in
   0.9.3 and appears in Garmin Connect as **CleanJibe - Invite Beta**. A new tester follows
   this line, finds no such entry, and cannot enter the key they were just sent.
2. `https://janlahmann.github.io/WingFoil` — the analyzer moved to **https://cleanjibe.org**
   (`Branding.siteURL`, pinned in `PresentationTests`). The old Pages URL still resolves,
   but it is not the address on the share cards, in the app, or on the site itself.

Also stale, less costly: the description still leads with "New in 0.9.0" three versions on.

The opening line's "Enduro 2 and tactix 7/8" was filed here as a false claim and is **not**
one — checked against the SDK, not the manifest. Garmin has no `enduro2`, `tactix7` or
`tactix8` product id: those watches share part numbers with ones the manifests already
declare. `fenix7x`'s own `compiler.json` calls itself *"fēnix 7X / tactix 7 / quatix 7X Solar /
Enduro 2"*, and `fenix847mm` is *"fēnix 8 47/51mm / tactix 8 47/51mm / quatix 8"*. Both are in
every invite manifest, so both watches can install the beta today. (0.9.4 adds `epix2pro51mm`,
which is also tactix 7 – AMOLED Edition, and `epix2`, which is also quatix 7 Sapphire.) What
the listing text should gain instead is the rest of the 0.9.4 device list — see ADR-014.

### What's New (live text)

```
0.9.3: the app is now called CleanJibe (same app, new name — cleanjibe.org). Pump strokes are now counted only in real pumping bursts, so totals drop to realistic numbers and match the phone analysis.

0.9.2: bigger and brighter - all text full white, larger numbers on nearly every page, the foil page's numbers in a larger table, and the map page is drawn by the app itself (teal where you flew, grey where you did not) so it works on every watch and while paused.

0.9.0: the watch works out the wind direction by itself after a few minutes of riding (~ marks the estimate, the wind menu always overrides) and classifies tacks, jibes and port/starboard entries live.

Note: Garmin keeps your stored page settings on update - existing installs can pick the new layouts in Garmin Connect settings or reinstall.
```

---

## Data field — `CleanJibe Field - Invite Beta`

* Store page: <https://apps.garmin.com/apps/8dad33d4-e367-45a6-a4bb-9647fd6b5402>
* Type: data field · Version **0.9.5** · first submitted 2026-08-13, current version released 2026-08-31
  (0.9.4 and 0.9.5 are prepared here; the upload is the coordinator's)
* Permissions: FitContributor
* Devices (`garmin/field/manifest-invite.xml`): fenix 8 (43 mm, 47 mm), fenix 8 Solar
  (47 mm, 51 mm), fenix 8 Pro (47 mm), fenix 7 / 7S / 7X, fenix 7 Pro / 7 Pro (no WiFi) /
  7S Pro / 7X Pro / 7X Pro (no WiFi)

### Description (live text)

```
Wingfoil metrics as a DATA FIELD, for riders who want to keep recording with a native Garmin activity profile - invite-only beta.

Add it to any activity profile (Windsurf is the one wingfoilers usually use) and the field shows live foil state, foil time and percentage, flight count and flight timer, the last turn's outcome and score, and the tack/jibe tally. Everything it computes is also written into the FIT file as developer fields, so the session can be analysed properly afterwards. Garmin owns the recording, the sport code, the laps and the GPS - this field only adds the wingfoil numbers on top.

It shares its detection core with the WingFoil watch app: the same flight detection with tunable thresholds, the same turn detection with tack/jibe classification and flew / touchdown / fell-in outcomes. What it cannot do is pumping and takeoff analysis - Connect IQ forbids a data field from touching the accelerometer, so those metrics live in the watch app only.

Layouts adapt to the cell you give it. Give it the whole screen and it draws the CleanJibe app's own main page: foil percentage, a giant speed, every counted turn as a coloured dot, the flew/touchdown/swim tally and your dry run - each with a small word beside it saying what it is. Pause or stop the activity and the same cell shows your session summary, two pages that alternate: foil share, flights, foil time against total, longest flight and distance, then the turn count, the tack/jibe split, the outcomes and your best speeds. Smaller cells stay compact, and you choose what they show: one metric for a 3 or 4 field cell, two for a 2 field one, out of speed, foil percentage, flights, flight timer, foil time, longest flight, distance, timer, heart rate, best 2s and 10s, turns, last turn, tacks/jibes, outcomes, dry run and the clock (Garmin Connect > CleanJibe Field > Settings).

A word of honesty: the field is newer and less tested than the CleanJibe app. If you use it, your feedback is doubly welcome (github.com/JanLahmann/WingFoil/issues or info@cleanjibe.org). Where your watch supports it, we still recommend the full CleanJibe app.

THIS BETA IS INVITE-ONLY. On the first activity the field shows an 8-character request code instead of metrics. Send that code to the developer (Contact Developer on this page) and you will receive your personal unlock key. Enter it in Garmin Connect under Connect IQ, WingFoil Field - Invite Beta, Settings, "Unlock key" - it takes effect immediately, mid-activity, and permanently on that watch. Without a key the field records nothing at all - please request a key instead of leaving a review about the lock.

Beta: metrics are under active tuning and thresholds may change between versions.

Analyze your sessions in any browser, free: https://janlahmann.github.io/WingFoil - the same analysis engine running locally on your device, nothing uploaded, with a session library, records and trends. Works on Android phones too.
```

**TODO (pending edit), two lines above:**

1. `Connect IQ, WingFoil Field - Invite Beta, Settings, "Unlock key"` — the field is now
   **CleanJibe Field - Invite Beta** in Garmin Connect. Same dead end as the watch app's
   unlock line.
2. `It shares its detection core with the WingFoil watch app` — that app is now **CleanJibe
   Wingfoil Tracker**; there is nothing in the store called WingFoil for a reader to go and
   find.

Also stale: the same `https://janlahmann.github.io/WingFoil` analyzer URL in the last
paragraph, which should be `https://cleanjibe.org`.

### What's New (live text)

```
0.9.5: the full-screen cell now shows the app's main page — giant speed, the colour ladder, tally and streak — and you can choose what smaller cells display (Garmin Connect > CleanJibe Field > Settings). Pause the activity and the field shows your session summary. A word of honesty: the field is newer and less tested than the CleanJibe app — if you use it, your feedback is doubly welcome (github.com/JanLahmann/WingFoil/issues or info@cleanjibe.org). Where your watch supports it, we still recommend the full CleanJibe app.

0.9.3: the field is now called CleanJibe Field (same field, new name — cleanjibe.org). No functional changes; version now tracks the CleanJibe app family.

0.1.0: first invite-beta release. Data field companion to the watch app - live foil state, foil time and percentage, flights, turn outcomes and tack/jibe tally, all written to the FIT as developer fields. fenix 8, fenix 7, Enduro 2 and tactix 7/8.
```

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
