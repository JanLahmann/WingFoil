# Watch map snapshot — the phone-rendered ground under the breadcrumb

**Status:** contract for device app 0.9.10 and iOS build 39+. GitHub #4.

## Why

The firmware's own map view (`WatchUi.MapTrackView`) kills the app on the fenix 8 — three
ways during a recording (docs/watch-ui-review.md §12.1) and, tested 13 Sep 2026 on SW 23.31,
also on a page pushed *after* the session was saved. So the watch never gets a Garmin map.
What it can get is a **picture the phone made**: a coarse land/water/road mask of the rider's
spot, a few kilobytes, pushed over the companion link once and drawn under the breadcrumb on
the live map page and the post-save Track page. The phone knows the spots (the library's
clusters), MapKit draws them, and the watch only blits.

## The message (phone → watch)

One `Communications` message, a dictionary with two-character keys like the rest of
`PhoneLink`. Every value is an integer, a short string or a byte array; no floats.

| key | type | meaning |
|---|---|---|
| `mv` | Number | schema, **1**. The watch drops any other value. |
| `mi` | Number | spot id: a stable 31-bit hash of the spot's cluster key, so a re-send of the same spot replaces rather than duplicates |
| `mn` | String | spot name, ≤ 24 characters, for the caption; may be empty |
| `la` | Number | south edge, latitude × 100 000, rounded |
| `lo` | Number | west edge, longitude × 100 000 |
| `lh` | Number | north edge, latitude × 100 000 |
| `lx` | Number | east edge, longitude × 100 000 |
| `mw` | Number | grid width in cells, **120** |
| `mh` | Number | grid height in cells, **120** |
| `mp` | ByteArray | the mask, run-length encoded (below) |

**The box** is the spot's cluster centre ± 1 500 m in both axes — a 3 km square on the ground
(the east/west span in degrees is divided by cos(latitude), so the square stays square). A
session that leaves the box is drawn clipped to it; the box is not meant to contain every
ride, it is meant to show the shore.

**The mask.** `mw × mh` cells, row-major, **north row first**, west cell first. Each cell is a
class: `0` water, `1` land, `2` road or built-up, `3` reserved (drawn as land). Encoded as
runs: one byte per run, `(class << 6) | (length − 1)`, length 1…64, runs never cross a row
boundary. The decoder walks rows and asserts that every row sums to `mw`; a mask that does not
is dropped whole. A 120 × 120 grid of a shore map runs 1–3 KB; the theoretical maximum is
14 400 bytes, which the phone never sends (it refuses anything over 8 000 bytes and sends a
coarser 60 × 60 grid instead — the watch reads `mw`/`mh` and does not assume 120).

## What the phone sends, and when

- The **two most-ridden spots** in the library (by session count), rendered with
  `MKMapSnapshotter` at 360 × 360 points, muted standard style, no points of interest, then
  classified per pixel and majority-downsampled 3 × 3 into the grid (360 = 3 × 120 = 6 × 60,
  so both downsamples are whole-pixel blocks and nothing is ever resampled). Classification
  is in HSL, because the map's palette is a set of *tints* — the same blue at four
  lightnesses for lake, sea, river and the antialiased edge between them — and a hue band
  survives a tint where three RGB ranges do not. A pixel is **water** when its hue is
  **185°–210°**, its saturation is **≥ 0.30** and its lightness is **0.35–0.95**; **road**
  when it is not water and either near-white (**lightness ≥ 0.925, saturation ≤ 0.45**) or
  the map's road yellow (**hue 30°–65°, saturation ≥ 0.45, lightness ≥ 0.85**); everything
  else is **land**. Every number is a gap in the measured histogram rather than a guess:
  Apple's water is 196° to within a degree across both fixtures, its lightest land green is
  0.910 against a road's 0.937, and the water band stops at 210° because the blue road
  shields (the `SS 240` lozenge over Torbole) sit at 213–216° with a saturation and a
  lightness indistinguishable from the lake's — without that ceiling every shield punches a
  three-cell lake into a hillside. A tie in the majority vote goes to the **lower** class,
  which is deterministic and errs towards the water. The thresholds are tuned on
  Nago-Torbole and Fehmarn in a kit test that asserts the lake is water and the Via Linfano
  is road, against two committed 360 × 360 PNGs under
  `ios/WingFoilKit/Tests/Fixtures/watchmap-*.png`. Those two boxes encode to **1 027** and
  **702** bytes, which is where the "1–3 KB" above comes from.
- Sent when the companion link is ready and the spot's mask hash differs from the one last
  acknowledged for that watch (`watchMap.ack.<device uuid>.<spot id>` in UserDefaults, written
  only after Garmin's own `.success`, so a failed push is retried rather than written off);
  re-checked at every app launch and after every import. In front of that check sits a cheap
  one, because the honest one costs two map renders to reach: a fingerprint of *which watch,
  which two spots, at which centres to the metre* (`watchMap.lastAuto`). Same fingerprint,
  nothing happens and MapKit is never woken — so the automatic pass is free on every launch
  after the first, and a re-cluster that nudges a centroid by a metre is correctly a new box.
  The device UUID and not the friendly name, so renaming a watch in Garmin Connect does not
  re-push everything it already has.
- A manual **"Send map to watch"** row under Settings → Garmin watch with the spot names and
  the last send result, for the rider who wants to see it happen. It ignores both gates: the
  point of pressing it is to watch it happen.
- The iOS side keeps rendering pure: `WatchMapMask` in the kit (classification of a bitmap,
  downsampling, RLE encode/decode, the hash) with tests; MapKit and ConnectIQ only in the app.

## What the watch does

- `PhoneLink.applyMessage` recognises `mv` and hands the dictionary to `MapSnapshot.store`,
  which validates (schema, box sane, grid ≤ 120, every row sums to `mw`) and writes it to
  `Application.Storage` under one of **two slots**; a third spot evicts the older slot. The
  message is never held in memory beyond the copy.
- At draw time `MapSnapshot.forPosition(lat, lon)` returns the slot whose box contains the
  point, or null. With a snapshot, the map page and the summary Track page **frame the
  snapshot's box** instead of auto-fitting the track: the box is scaled into the inscribed
  square exactly as `TrackDraw` scales a track today, the mask is drawn once into a
  `BufferedBitmap` with a 3-colour palette (water near-black navy, land dark grey, road mid
  grey — inks from `Ink`, never white, so the teal breadcrumb and the white marker stay the
  brightest things on the glass), the bitmap is blitted each frame, and the breadcrumb is
  drawn over it with the same projection, clipped to the square. Without a snapshot nothing
  changes: the pages draw exactly as 0.9.9 does.
- The bitmap is built lazily on first use and dropped when the slot changes. Memory: 120 × 120
  cells scaled to a ≤ 330 px square at 2 bits per pixel is under 30 KB; the fr255's 524 KB
  budget is the floor this was checked against.
- The caption under the map gains the spot name when one is known.

## Test surface

- Kit: encode/decode round trip, row-sum rejection, the classifier on two fixture snapshots
  (checked-in PNGs of the two spots), the hash, the 60 × 60 fallback.
- Watch: `MapSnapshot.store` accepts a good mask and rejects a bad row sum, a bad schema and
  an oversized grid; `forPosition` picks the right slot; the drawing path's framing arithmetic
  (box → square) in the layout suite, at all four glasses.
- Device: Jan's fenix 8, Torbole. The whole point is that nothing here touches a firmware map
  view, so the app cannot die the way #4 died.
