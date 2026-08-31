# Watch UI review — Fenix 8 47 mm (454 px)

A read of every on-watch screen against one question: *can a rider on a wing, one hand on
the boom, at arm's length, in spray and sun, read this in one second?*

Review only. No source file was changed.

---

## 0. How the numbers in this document were obtained

The coordinate maths in `RecordingView` is all expressed in `dc.getFontHeight()`, so
nothing can be checked without the device's real font metrics. I built a throwaway probe
app and ran it in the ConnectIQ 9.2 simulator on `fenix847mm` and `fenix843mm`, and it
printed the real line heights and text widths. Those are the numbers below. No screenshots —
the arithmetic is the substance, and the simulator's FIT replay is realtime-only anyway.

**Line heights (`dc.getFontHeight`), px**

| font | 454 (47 mm) | 416 (43 mm) |
|---|---:|---:|
| `FONT_XTINY` | 37 | 34 |
| `FONT_TINY` | 47 | 43 |
| `FONT_SMALL` | 53 | 50 |
| `FONT_MEDIUM` | 61 | 58 |
| `FONT_LARGE` | 71 | 67 |
| `FONT_NUMBER_MILD` | 113 | 103 |
| `FONT_NUMBER_MEDIUM` | 153 | 141 |
| `FONT_NUMBER_HOT` | 173 | 159 |
| `FONT_NUMBER_THAI_HOT` | 210 | 192 |

Useful widths on 454: `"99.9"` = 280 px in THAI_HOT, 229 in NUMBER_HOT, 151 in MILD;
`"199:59"` = 185 in LARGE, 158 in MEDIUM, 136 in SMALL; `"PAUSED"` = 169 in SMALL;
`"press to exit"` = 168 in XTINY.

**The readability floor.** Garmin line heights include leading; the actual digit height is
roughly 58 % of the line height. So against the ~28 px floor:

| font | ≈ digit height, 454 | verdict on the water |
|---|---:|---|
| THAI_HOT | ~122 | the hero number, correct |
| NUMBER_HOT | ~100 | fine |
| NUMBER_MILD | ~66 | fine |
| LARGE | ~41 | fine |
| MEDIUM | ~35 | fine |
| SMALL | ~31 | at the floor |
| TINY | ~27 | below |
| XTINY | ~21 | **below — labels only, never a value** |

That last line matters: everything the app draws in `FONT_XTINY` (every cell label, every
hero unit line, the three timeline band captions, the summary's exit hint) is not actually
readable at a glance. That is acceptable for a label you learn once and then recognise by
position — it is *not* acceptable anywhere XTINY ends up carrying a number, which happens
in exactly one place (finding 4.3).

**One correction to the brief.** The 416 px variant (`fenix843mm`) is *not* MIP — it is a
16-bit AMOLED, same as the 47 mm, just smaller. The real MIP variants are the two fenix 8
Solars (260 / 280 px) and the whole fenix 7 family (240 / 260 / 280 px), all **8 bits per
pixel**, i.e. a 64-colour palette and no true black. That changes what the MIP fixes are:
they are colour and contrast fixes at 240–280 px, not layout fixes at 416 px.

---

## 1. RecordingView — Records page (`LAYOUT_RECORDS`)

### 1.1 The bottom record number runs off the glass — HIGH
`garmin/source/ui/RecordingView.mc:441` and `:452-454`

This is the one page that draws a giant number **without going through `fitFont()`**. It
pins `FONT_NUMBER_HOT` and hopes.

Working the row maths at `:441` with the real metrics (454 px, `hHot` = 173, `hT` = 37):

```
y = cy + 12 - (2*173 + 2*37)/2 + 37/2 = 47.5      "best 2s"      label
y += (37+173)/2 = 152.5                            best-2s value  NUMBER_HOT
y += (173+37)/2 = 257.5                            "best 10s km/h" label
y += (37+173)/2 = 362.5                            best-10s value NUMBER_HOT
```

The bottom number is centred at y = 362.5 with 129 px of ink, so its ink runs 298 → 427.
The chord the round glass leaves for a box that deep is **206 px**. `"99.9"` in NUMBER_HOT
is **229 px**. It is 23 px too wide — about 11 px sliced off each end of the number, which
on a 3-digit-plus-decimal readout means the leading digit and the decimal both lose a slice.

On 416 it is worse: 211 px of number into a 181 px chord, **30 px over**.

The suite never catches this because there is no `recordsPageFitsRoundDisplay` test — the
only place `LAYOUT_RECORDS` appears in `tests/WingfoilTests.mc` is
`everyLayoutRendersHeadless:1363`, which asserts nothing about geometry, only that the draw
does not crash.

**Fix, in order of effort:**
1. Delete the `cy + 12` bias. That alone fixes it: the bottom row moves to y = 350.5 and the
   chord there is 247 px against the 229 px needed (416: 224 vs 211). The comment says the
   bias exists because "the top label otherwise clips the circle edge" — with the measured
   metrics the top label at y = 35.5 has a 231 px chord for ~100 px of text, so the bias is
   solving a problem that no longer exists.
2. Then route both numbers through `fitFont(dc, NUMBER_FONTS, 1, …, rowBudget(…))` like
   every other giant on every other page, so a future unit change or a 3-digit knots value
   steps down instead of clipping.
3. Add `recordsPageFitsRoundDisplay` next to the other five, asserting
   `cornerRadius(w, inkH, y, cy) <= fitRadius(dc)` for both rows.

### 1.2 Two NUMBER_HOT numbers do not fit a round watch — MEDIUM
`garmin/source/ui/RecordingView.mc:435-454`

Even fixed, the block is `2 × 173 + 2 × 37` = **420 px of a 454 px screen (93 %)**. There is
no headroom left for anything, which is why it needed a magic bias in the first place. And
neither number is *the* number: the page gives best-2s and best-10s equal visual weight, so
the rider's eye has nothing to land on.

**Fix:** make best-2s the hero (THAI_HOT, ~122 px digits) and best-10s a `FONT_LARGE`
sub-row underneath — which is exactly `drawHeroPage`'s existing shape. `LAYOUT_RECORDS`
could then be deleted entirely in favour of a HERO page with slots
`[M_BEST_2S, M_BEST_10S, M_SPEED]`, and the rider gets current speed alongside his records
for free.

---

## 2. RecordingView — Hero page (`LAYOUT_HERO`, default page 1)

Row centres on 454 for the shipped speed / flight-timer / HR page:
giant **142**, unit line **266**, sub-row 1 **320**, sub-row 2 **386**.
The giant fits THAI_HOT (280 px into a 310 px chord). Vertically this page is the best
thing in the app: 122 px digits for speed, ~41 px for the flight timer, ~35 px for HR. Good.

### 2.1 The giant number collides with the flight-state ring — MEDIUM (HIGH on 43 mm)
`garmin/source/ui/RecordingView.mc:218-220` (`fitRadius`), used at `:272`

`fitRadius()` returns `cx - 2` unconditionally. But a hero page has just painted a 10 px
ring at `cx - RING_INSET` (`:257`), i.e. occupying radii **215–225** on 454. The fitter is
blind to it and happily fills right up to 225.

Measured: the giant "99.9" ink box has its corner at radius **214.9** on 454 — 0.1 px inside
the ring's inner edge, a graze that only survives because digits are round at the corners.
On 416 the same corner lands at **198.3** against a ring inner edge of **196** — a genuine
2.3 px overlap: the top corners of the speed number are drawn over the state ring.

The same blindness affects the foil-% bezel arc (radii 216–222 on 454, 197–203 on 416).

**Fix:** give `fitRadius` the annulus it has to clear.

```
static function fitRadius(dc, ring, arc) {
    var r = dc.getWidth() / 2 - FIT_MARGIN;
    if (ring) { r = min(r, cx - RING_INSET - RING_PEN / 2 - FIT_MARGIN); }   // 210 on 454
    if (arc)  { r = min(r, cx - BEZEL_INSET - BEZEL_PEN - FIT_MARGIN); }     // 214 on 454
    return r;
}
```

and pass the page's ring/arc flags down from `onUpdate`. The existing layout tests already
assert against `fitRadius`, so they inherit the fix for free — which is the point.

### 2.2 Flight state is a ring colour and nothing else — MEDIUM
`garmin/source/ui/RecordingView.mc:253-258`, `garmin/source/ui/PageModel.mc:305-307`

Peripherally readable state is the right instinct, and the ring is the right mechanism. Two
problems with the execution:

- The off-foil ring is `COLOR_DK_GRAY` on black. On AMOLED at low brightness through
  polarised sunglasses this is very close to "no ring at all", so *off foil* and *ring not
  drawn* look the same. On an 8-bit MIP in sun it is worse (see §7.2).
- The ring is binary — flying / not-flying. The app tracks a third state the rider cares
  about, *pumping* (`PumpDetector`, `pump.attemptOpen()`), and never shows it. The moment a
  rider most wants peripheral feedback is during the pump, when he cannot look at the watch
  at all.

**Fix:** three ring states — flying = the phase teal (§6), pumping = a pulsing teal or the
effort indigo, off-foil = a *visible* mid-grey (`COLOR_LT_GRAY` at a thinner pen, or a
dotted arc) rather than dark grey. And consider making the whole ring thicker: 10 px of a
227 px radius is 4.4 % — a 14–16 px ring reads from the corner of the eye at arm's length
where 10 px does not.

---

## 3. RecordingView — Grid page (`LAYOUT_GRID4`, default page 2)

Row centres on 454: giant **99**, top cell label **174** / value **228**, bottom cell label
**282** / value **336**.

### 3.1 The bottom cells' worst case reaches into the foil-% arc — MEDIUM
`garmin/source/ui/RecordingView.mc:225-235` (`cellColumns`), `:365`, `:381`

`cellColumns` solves the chord so that the outermost ink corner of a cell sits *exactly* at
`fitRadius`. Measured worst-case corner radii:

| | 454 | 416 |
|---|---:|---:|
| top cell corner | 206.8 | 201.0 |
| bottom cell corner | **221.0** | **202.0** |
| foil-% arc inner edge | 216 | 197 |

So on the shipped page 2 (which *does* carry foil %, and therefore *does* draw the arc), a
bottom cell using its full width budget puts ink 5 px inside the arc. On 416 **both** rows
do. It does not bite for the shipped default content — `"199:59"` steps down to
`FONT_MEDIUM` and lands at radius 213.5 — but it bites for `M_TAKEOFFS` (`"99>99"` ≈ 166 px
fits `FONT_LARGE`), which is a metric the settings screen offers for exactly that slot.

**Fix:** the same `fitRadius` change as 2.1. Nothing else needs to move.

### 3.2 `GRID_BIAS = 20` is an absolute pixel on a proportional problem — LOW
`garmin/source/ui/RecordingView.mc:47`

20 px is 4.4 % of the height on 454, 4.8 % on 416, but **8.3 % on a 240 px fenix 7S** — the
narrow glass where the block can least afford to be shoved off centre. Make it
`dc.getHeight() * 20 / 454`, same treatment `Glyphs.size()` and `StartView.dotRadius()`
already get. Same argument for `CELL_DX_MAX = 105` (`:20`) — harmless today because the
chord binds first on every shipped variant, but it is a 454-authored number with no scaling.

### 3.3 The label row costs 37 px to say something you cannot read — LOW
`garmin/source/ui/RecordingView.mc:400-414`

Each cell spends `hT` = 37 px of vertical budget on an XTINY glyph + word, at ~21 px digit
height — below the readability floor. The glyph (17 px on 454, clamped 14–18 by
`Glyphs.size()`) is doing the real work. Given that, `showLabels` defaulting **on** is
probably the wrong default for the water: turning it off frees the value row's full width
and loses nothing a rider can read anyway. Worth an on-water A/B before changing the
default, but the measurement says the word is decorative.

---

## 4. RecordingView — Turns page (`LAYOUT_TURNS`)

Row centres on 454: header **78**, counts **183**, outcome **305**, tally **367**.
Geometry is sound — every row is fitted, and `turnsPageFitsRoundDisplay` covers it. Two
content problems.

### 4.1 The biggest number on the page is the least useful one — MEDIUM
`garmin/source/ui/RecordingView.mc:475-483`

The NUMBER_HOT slot holds the *count* of tacks and jibes. A count is a number you read once
an hour. Meanwhile the thing that changes every jibe — the outcome and its score — is
`FONT_LARGE` on row 2, and the session verdict (`"73 % ok"`) is the smallest thing on the
page. The hierarchy is inverted relative to what the rider actually glances for after a
jibe: *did that one count?*

**Fix:** promote. Giant = the last score with its outcome colour (`87%` in green / orange /
red — colour *and* number in one mark), row 2 = the tack/jibe split at `FONT_LARGE`, row 3 =
the tally as it is. The outcome symbol can then move to the giant's unit line or be dropped,
since the giant's own colour already carries the verdict.

### 4.2 The tally can degrade to unreadable exactly when it matters — MEDIUM
`garmin/source/ui/RecordingView.mc:596-604` (`tallyFont`), `:631-661`

`tallyFont` starts at `FONT_SMALL` and steps down. Worst case — three two-digit tallies,
two `" · "` separators, the 14 px gap and `"100% ok"` — measures ≈ 391 px against a 316 px
chord at that depth on 454. `FONT_TINY` is still ≈ 347. It lands on **`FONT_XTINY`**, i.e.
~21 px digits. So a long session with 30+ turns, which is precisely the session whose tally
you want to read, renders its tally below the readability floor.

**Fix:** stop the ladder at `FONT_SMALL` and drop content instead of size — either move
`"% ok"` onto its own row (the page has vertical room once 4.1 rebalances it), or draw the
tally as three coloured **dots with counts** rather than digits with `" · "` separators,
which costs ~120 px less and reads faster anyway.

### 4.3 `bestScorePct` is tracked and never shown — LOW
`TurnDetector.bestScorePct` exists (`barrel/WingFoilCore/source/TurnDetector.mc:97`) and no
screen draws it. It is the natural "session PB" for turns and belongs on the post-save
summary (§8).

---

## 5. The remaining recording screens

### 5.1 PAUSED banner: fixed y, and it punches a hole in the ring — MEDIUM
`garmin/source/ui/RecordingView.mc:123-127`

`dc.drawText(width/2, 18, FONT_SMALL, "PAUSED", TEXT_JUSTIFY_CENTER)` — no vertical
justification, so 18 is the **top** of the line box, and `setColor(YELLOW, BLACK)` means the
whole line box is painted opaque black behind the text.

That box is **x 142→312, y 18→71** on 454 (129→287, 18→68 on 416). I checked it against
every bezel decoration the app draws:

| decoration | radii (454) | overlapped by the banner box? |
|---|---|---|
| hero flight ring | 215–225 | **yes** |
| nested ring (foil-arc pages) | 208–214 | **yes** |
| foil-% bezel arc | 216–222 | **yes** |

So pausing erases a ~30° bite out of the top of whichever ring the page is showing —
including the start of the foil-% arc, which is the one place a sweep is read from. It also
means the banner's own position is the only absolute y-coordinate on any recording page.

**Fix:** draw the banner *inside* the rings, not across them. Centre it vertically at
`cy - hN/2 - hSmall` (i.e. tucked above the giant number, computed from font heights like
everything else), or better, drop the word entirely and pulse the ring amber — a paused
session is a *state*, and this app already believes states belong on the bezel.

### 5.2 The map page shows no state at all — MEDIUM
`garmin/source/ui/MapPageView.mc:86-108`, `garmin/source/ui/PageModel.mc` / `PageNav`

`MapPageView` extends `MapTrackView` and overrides no `onUpdate`. Consequences:
- **The PAUSED banner is invisible on the map page.** A rider who pauses, pages to the map,
  and rides on has no indication anywhere that he is not recording.
- No speed, no foil state, no flight timer. The page is a pure map.

**Fix:** `MapTrackView` cannot be drawn into, but it accepts overlays via `MapMarker`, and
the simplest honest fix is to refuse to page onto the map while paused, plus a
`WatchUi.showToast`-style confirmation. If markers are workable, a single speed marker
pinned at the current position would restore the number.

### 5.3 PbFlash kills itself when the rider pages — MEDIUM
`garmin/source/ui/RecordingView.mc:82-84` vs `garmin/source/ui/PbFlash.mc:19-20`

`PbFlash.mc` says, in its header comment: *"State lives in a module, not in RecordingView:
paging on and off the map swaps the whole View, and a celebration must not die because the
rider happened to be scrolling."*

`RecordingView.onHide()` then calls `PbFlash.stop()`. Paging to the map page swaps the view,
which fires `onHide`, which cancels the flash. The module-level state buys nothing, and the
stated design intent is defeated by the four lines above it.

**Fix:** drop `PbFlash.stop()` from `onHide` — the flash auto-clears at `FRAMES` anyway
(`PbFlash.tick:44-53`), which is what makes it safe to leave running. Keep the explicit
`stop()` calls in the save/discard path (`SessionController:315`, `:353`), which are the
ones that actually matter.

### 5.4 PbFlash geometry is unfitted, and it takes the whole screen — LOW
`garmin/source/ui/RecordingView.mc:166-180`

The flash draws `FONT_NUMBER_HOT` with no chord check. It happens to fit on every shipped
variant (the number sits near the equator where the chord is widest), but it is the same
unfitted-giant pattern as finding 1.1 and should go through `fitFont` on principle.

More interesting: for 700 ms the rider loses the live page entirely, at the exact moment he
is mid-speed-run and wants the live number. It is defensible — the number *shown* is the new
best-2s, which is within a whisker of current speed — but a ring-flash plus a colour swap on
the existing giant would keep the page and interrupt just as hard. Worth trying on the
water. 700 ms is the right duration; it is not sticky.

### 5.5 A global 5 s debounce silently drops the more informative alert — MEDIUM
`garmin/source/alerts/AlertManager.mc:10-21`

`_lastMs` is one module-level timestamp shared by every alert type. The vibe patterns are
carefully designed to be distinguishable (`:60-63`: "flew through = one crisp tick,
touchdown = two soft ticks, fell in = three hard ticks") — and then a PB buzz 4 s before the
jibe swallows the verdict entirely. Coming out of a fast jibe, a PB and a turn outcome
landing within 5 s of each other is not an edge case, it is the normal case.

**Fix:** debounce per channel, not globally — a small array indexed by alert type — and keep
a much shorter (~1 s) global floor so two buzzes never overlap into mush.

### 5.6 Timeline page has no number on it — LOW
`garmin/source/ui/RecordingView.mc:668-748`

Bands on 454: label 113, foil strip **132–176**, label 194, sparkline **213–309**, label 331,
dot row centre **352**. Nothing collides, the chord clipping is handled properly by
`bandHalfWidth`, and the three captions are XTINY. But the page contains **zero digits** —
no peak speed on the sparkline, no foil % on the strip, no turn count on the dots. It is a
shape, and shapes are a sit-down-with-a-coffee medium, not a one-second-glance medium.

It also leaves 95 px of dead space at the top and 96 px at the bottom.

**Fix:** put the number each band is about at the right-hand end of its own caption row —
`on foil 63 %`, `speed 24.1 max`, `turns 14`. It costs no vertical space (the caption row
already exists) and turns each band from decoration into a reading.

### 5.7 Clock page is fine
Rows 173 / 296 / 350. `"23:59"` needs 371 px in THAI_HOT against a 364 px chord, so it steps
down one rung to NUMBER_HOT (303 px) — the fitter works exactly as designed. No findings.

---

## 6. Colour: the watch does not speak the shared vocabulary

`docs/presentation.md:5` claims the contract covers "the watch's colour vocabulary".
`design/tokens.json` carries `hex` and `swiftUI` forms for every token — and **no Monkey C
form**, so the watch was never actually wired into the contract. It shows.

### 6.1 Green means two different things on the same screen — HIGH
`docs/presentation.md:44-45` is unambiguous: *"The outcome ladder is a verdict scale and
nothing else may borrow it: green = flew through · orange = touchdown · red = fell in ·
grey = course change."* And `:68`: *"Phase tints are one colour each, in both apps: flying =
teal, off foil = the secondary label grey."*

The watch uses `Graphics.COLOR_GREEN` for **both**:

| use | file:line | shared vocabulary says |
|---|---|---|
| flight-state ring, flying | `RecordingView.mc:255` | phase teal `#40c8e0` |
| foil-% bezel arc | `RecordingView.mc:143` | phase teal |
| flight-timer value while flying | `PageModel.mc:306` | phase teal |
| foil-fraction bars, Timeline | `RecordingView.mc:692` | phase teal |
| map breadcrumb while flying | `MapPageView.mc:133` | phase teal |
| turn outcome "flew" | `RecordingView.mc:521` | ladder green ✅ |
| turn tally "flew" count | `RecordingView.mc:645` | ladder green ✅ |
| "Saved!" | `SummaryView.mc:20` | neither |
| PB flash | `PbFlash.mc:66` | this is an *effort* event → orange `#ff9f0a` |

The Timeline page is where it actually breaks: the foil bars (phase) and the outcome dots
(verdict) are the same green, six rows apart, on one screen. Same on the map, where the
green track is phase but green is what the rider has been trained to read as "that jibe
worked".

Likewise `COLOR_RED` is the ladder's "fell in" *and* the heart-rate colour
(`PageModel.mc:309`) — so on a turns-adjacent page, red is simultaneously "you swam" and
"your pulse".

**Fix.** Both AMOLED variants are 16 bpp and `dc.setColor` takes a literal `0xRRGGBB`, so
the tokens can be used directly:

```
phase flying   0x40C8E0   (teal)     — ring, arc, foil bars, breadcrumb, flight timer
phase offFoil  0x97979D   (grey)     — the off-foil half of all of the above
ladder flew    0x0CA30C
ladder touch   0xFAB219
ladder fell    0xD03B3B
effort window  0xFF9F0A   — the PB flash, the record numbers, "new best" marks
```

The MIP variants quantise to the 64-colour palette (`{00,55,AA,FF}³`): teal `#40C8E0` lands
on `0x55AAFF`, still clearly not-green and clearly not-blue-brand. Verify on a MIP sim
before shipping.

Then add a `monkeyC` form to `design/tokens.json` and generate a `WingFoilColors.mc`, so
`design/check_tokens.py --check` guards the watch the way it already guards iOS and web —
otherwise this drifts back within two commits.

### 6.2 HR should not be ladder red — MEDIUM
`garmin/source/ui/PageModel.mc:309`. Heart rate is not a verdict. Use white like every other
neutral value, or the effort layer's indigo `0x8F7CE8` if it needs its own identity.

---

## 7. Cross-cutting: hardcoded pixels and the MIP variants

### 7.1 Every absolute coordinate in the app
The recording pages are almost entirely font-metric-driven, which is genuinely good work.
The absolute numbers that remain:

| file:line | value | breaks where | severity |
|---|---|---|---|
| `RecordingView.mc:125` | PAUSED at `y = 18` | overlaps ring/arc on both AMOLEDs (§5.1) | med |
| `RecordingView.mc:441` | `cy + 12` records bias | clips the bottom number on 454 **and** 416 (§1.1) | **high** |
| `RecordingView.mc:47` | `GRID_BIAS = 20` | 8.3 % of a 240 px screen vs 4.4 % of 454 (§3.2) | low |
| `RecordingView.mc:20` | `CELL_DX_MAX = 105` | 454-authored; chord binds first today | low |
| `RecordingView.mc:28-36` | `BEZEL_PEN/INSET`, `RING_PEN/INSET` | a 10 px ring is 4.4 % of r on 454, 8.3 % on 240 | low |
| `RecordingView.mc:10-15` | `TURNS_*_GAP` 16/12/14 | pushes the tally down the font ladder sooner on narrow glass (§4.2) | low |
| `RecordingView.mc:66-68` | `TL_DOT_R 6`, `TL_DOT_GAP 4`, `TL_MARGIN 6` | fixed dots on 240 px | low |
| `Glyphs.mc:59-110` | `setPenWidth(2)`, `±3`/`±4` arrow-head offsets | a 3 px arrow head inside a 14 px box on MIP | low |
| `SummaryView.mc:18,22,26-35,38` | `40`, `45`, `32`, `height-50`, `±10` | the whole screen (§8) | **high** |

`TL_STRIP_H` / `TL_SPARK_H` are already handled correctly by `bandH()`, and
`StartView.dotRadius`/`dotStep` and `Glyphs.size` already scale off the display. Those three
are the pattern the rest should follow.

### 7.2 The real MIP problem is contrast, not layout — MEDIUM
On the 8 bpp, no-true-black MIP faces, the app leans on `COLOR_DK_GRAY` for information:

- the off-foil flight ring (`RecordingView.mc:255`)
- the unfilled part of the foil-% arc (`:139`)
- the best-2s reference line on the sparkline (`:717`)
- the `" · "` tally separators (`:647`, `:651`)
- the flight timer when not flying (`PageModel.mc:307`)
- the off-foil half of the breadcrumb (`MapPageView.mc:133`)
- the unfilled GPS dots (`StartView.mc:113`)

On AMOLED, dark grey against true black is a legible ~20 % step. On MIP the background is
already a mid-grey and the reflective display loses contrast the moment there is glare on
it — those elements approach invisible in exactly the conditions the app is designed for.

**Fix:** one `dimInk()` helper that returns `COLOR_DK_GRAY` on AMOLED and `COLOR_LT_GRAY`
(or the phase grey `0x97979D`) on MIP, keyed off `System.getDeviceSettings().screenWidth <
416` or, better, a per-product resource. The off-foil ring in particular should be *visibly
drawn*, not implied by absence.

---

## 8. StartView

`garmin/source/ui/StartView.mc`. Rows on 454: title **127**, GPS dots **192**, state **252**,
hint **331**. Dot radius 8, pitch 30. All fitted, nothing clips, and the rewrite away from
the old fixed offsets (documented in the comment at `:40-47`) was the right call.

### 8.1 The app's name is the biggest thing on the screen — LOW
`StartView.mc:9`, `:96-101`. `"WingFoil"` at `FONT_MEDIUM` (61 px line) is the visual anchor
of a screen whose only question is *can I press start yet?* The answer to that question —
`"GPS ready"` — is one rung smaller at `FONT_SMALL`.

**Fix:** drop the title to `FONT_SMALL` or remove it (the rider just launched the app; he
knows), and promote the GPS state to `FONT_LARGE` with the dots directly under it. Better
still: colour the whole dot row green and put `"START"` in the middle of the screen the
moment GPS is usable, so the screen has exactly one state and one word.

### 8.2 Nothing tells the rider what he's about to record — LOW
The wind axis is settable from the recording menu (`RecordingDelegate.mc:52`), never shown
before the start, and it is the one setting that silently changes what the Turns page can
tell you (tack/jibe split). A `FONT_XTINY` line under the hint — `wind NNE · km/h · sport 43`
— would cost 37 px of a screen that has 95 px of dead space at the bottom, and would catch
"I forgot to set the wind" before the session rather than after.

---

## 9. SummaryView — the current screen

`garmin/source/ui/SummaryView.mc`, 64 lines, every coordinate absolute, no layout test.

### 9.1 Consecutive rows overlap — HIGH
`SummaryView.mc:26-35`

The five rows advance **32 px** at `FONT_SMALL`, whose line height is **53 px** (454) /
**50 px** (416). By the codebase's own ink convention (`RecordingView.inkH` = ¾ of line
height = 39 px), consecutive rows overlap by **7 px of ink on 454 and 5 px on 416** — the
descenders of one row land in the caps of the next. The 32 px pitch was authored for a font
about two thirds this size; it is simply the wrong number for a fenix 8.

**Fix:** `y += dc.getFontHeight(FONT_SMALL)`, and derive the whole stack from font heights
the way `heroRowY` / `turnsRowY` do.

### 9.2 A third of the screen is empty, and the content sits in the top half — HIGH
Content occupies y 40 → 266, then nothing until the exit hint at y 404. That is a **138 px
dead band — 30 % of the display height** (103 px / 24 % on 416), and the block's optical
centre is at y ≈ 153 against a screen centre of 227.

### 9.3 The exit hint is at the round edge — MEDIUM
`SummaryView.mc:38`. `"press to exit"` in XTINY is 168 px wide, top-justified at
`height - 50` = 404, so its ink runs to y ≈ 431 where the chord is only **199 px**. It fits
by 31 px in total, which means the descender of the "p" at each end of the string is within
a few pixels of the glass on 454, and there is no fit check anywhere to catch it if the
string ever gets longer or gets translated.

### 9.4 Five numbers, no hierarchy, no verdict — HIGH
All five rows are the same size, same colour, same weight. Nothing is the headline. The
green `"Saved!"` at `FONT_MEDIUM` is the largest element on a screen whose subject is *how
did the session go*, and "saved" is the one thing the rider does not need to be told at
`FONT_MEDIUM` — he pressed save.

### 9.5 Half the session's data never reaches the summary — MEDIUM
Fields the engine holds after the save and no screen ever shows:
`turns.tackCount` / `jibeCount` / `flewCount` / `touchdownCount` / `fellCount` /
`successCount` / `bestScorePct`, `pump.strokes` / `successes` / `attempts()` /
`lastPumpsToTakeoff`, `hrCost.lastCostBpm`, `detector.longestM`, `records.best10sMps`,
`history` (the entire 256-slot session story), `engine.timerS`, `controller.elapsedS`.

A CIQ app gets no native post-activity review, so this screen is the *only* moment between
the water and Garmin Connect. It is currently spending that moment on five rows.

### 9.6 No German — LOW
`manifest.xml` declares `<iq:language>deu</iq:language>`, but `resources/strings/strings.xml`
contains only setting titles and FIT field labels — every string a rider actually reads on
the watch (`"WingFoil"`, `"START to record"`, `"GPS ready"`, `"PAUSED"`, `"Saved!"`,
`"press to exit"`, `"best 2s"`, `"turns"`, `"on foil"`, the menu items `"Resume"` / `"Wind"`
/ `"Save"` / `"Discard"`) is a literal in the `.mc` files, and there is no `resources-deu/`
directory. The German declaration is currently a promise the app does not keep.

---

## 10. Summary redesign proposal — a multi-page post-save review

**What the engine can actually still give us.** `SessionController.finishSave()`
(`:311-334`) nulls `_session` and calls `stopGps()`, but **never touches `engine`** — the
comment at `SummaryView.mc:6` is correct. So `detector`, `records`, `turns`, `pump`,
`hrCost`, `history`, `distM`, `timerS`, and `elapsedS` are all live and complete after the
save. That is enough for six pages without adding a single new measurement.

**Two caveats worth knowing before designing:**

1. **The track buffer is conditional.** `engine.trackLat/trackLon/trackFly` are only filled
   when `trackEnabled` is true, and `WingfoilApp.mc:55` sets that to `PageModel.mapPage` —
   i.e. only if the rider configured a map page. For a track page on the summary this has to
   become unconditional. Cost: `128 × (4 + 4 + 1)` bytes ≈ **1.2 KB** against a 786 KB app
   budget. Trivial.
2. **`MapPageView` cannot be reused post-save.** `MapTrackView` keeps itself centred on the
   *current position*, and `finishSave` has already called `stopGps()`. Paging onto it after
   a save would show a map centred on nothing. The track page therefore has to be drawn by
   us, with `Dc` primitives, from the lat/lon buffer — which is straightforward
   (min/max bounding box, ×`cos(lat)` for the longitude squeeze, scale into the square
   inscribed in the circle: side `2R/√2` ≈ **318 px** on 454) and reuses `TrackTint`'s run
   splitting verbatim for the green/grey — sorry, **teal/grey** — colouring.

### The page set

Same navigation model as recording, so there is nothing new to learn:
**UP / DOWN cycle the pages** (`onNextPage` / `onPreviousPage`, wrapping, exactly as
`PageNav.step`), **START or BACK exits** (as `SummaryDelegate` does today), **taps are
swallowed** (`onTap` returns true, as `RecordingDelegate.mc:69`). A row of small dots on the
bottom arc shows which page you are on — the same idiom as StartView's GPS dots, so the
component already exists.

Reuse `heroRowY` / `drawCellRow` / `drawTally` / `drawTimelinePage` as they stand. The
cheapest implementation is a `SUMMARY_PAGES` array of layout+slot rows fed to the *existing*
`RecordingView` drawing functions, with a `SummaryNav` module mirroring `PageNav` — most of
this screen already exists, it is just not being called.

---

**S1 — Verdict** *(the page you land on)*

| | |
|---|---|
| bezel | foil-% arc, teal (reuse `drawFoilBezel`) |
| giant | **foil %** — THAI_HOT, ~122 px digits |
| unit line | `on foil` |
| row 1 | `42:10 of 1:38:20` — foil time of elapsed, `FONT_LARGE` |
| row 2 | `12.4 km · 3 flights`, `FONT_MEDIUM` |
| corner | a small green `SAVED` pill at the bottom, XTINY — an acknowledgement, not a headline |

Foil % is the one number that answers "was that a good session", it is already the giant on
recording page 2, and the arc gives it a shape you read before you read the digits.

**S2 — Speed**

| | |
|---|---|
| giant | **best 2 s** in the display unit, THAI_HOT |
| unit line | `km/h` / `kn` |
| row 1 | `best 10s 27.9`, `FONT_LARGE` |
| row 2 | `12.4 km`, `FONT_MEDIUM` |
| marker | if the best 2 s beat the stored all-time, an orange `NEW PB` flag above the giant |

The PB marker needs an all-time store, which does not exist yet — but
`Application.Storage` is already in use (`LockGate.mc`, `PhoneLink.mc:304-321`), so it is one
key: read at start, compare at save, write on a beat. Use the **effort orange `#ff9f0a`**,
not green — a record is an effort event, not a verdict (§6.1).

**S3 — Flights**

| | |
|---|---|
| giant | **longest flight**, `m:ss`, THAI_HOT |
| unit line | `longest` |
| row 1 | `1.4 km` — `detector.longestM`, currently tracked and never displayed |
| row 2 | `3 flights · 42:10 on foil` |

**S4 — Turns** *(only when `turns.turnCount > 0`)*

Essentially today's Turns page with the live-oriented parts swapped for session-oriented
ones, since "last outcome" is meaningless once the session is over:

| | |
|---|---|
| header | `tack / jibe  NNE` — or `turns` when no wind axis was set |
| giant | the tack / jibe split (reuse `drawSplitCount`) |
| row 2 | `best 92%` — `turns.bestScorePct`, finding 4.3 |
| row 3 | the flew · touch · swim tally + `% ok` (reuse `drawTally`, with 4.2's fix) |

**S5 — Takeoffs** *(only when `pump.available`, so it silently disappears when the
accelerometer was off)*

| | |
|---|---|
| giant | `9/14` — successes over attempts |
| unit line | `takeoffs` |
| row 1 | `4.2 pumps to foil` — `pumpsSum / successes` |
| row 2 | `+7 bpm cost · 312 strokes` |

**S6 — Story**

`drawTimelinePage` verbatim. `engine.history` is complete and untouched by the save, and
this is the page the timeline was always really for: a coffee-in-hand read of the session
arc, which is a bad fit while riding (§5.6) and a perfect fit here. Add 5.6's captions-with-
numbers while you are in there.

**S7 — Track** *(only when `trackN >= 2`)*

The breadcrumb drawn as a shape, tinted teal / grey by foil state via `TrackTint`, filling
the inscribed square. Plus, at the bottom, `12.4 km`. This is the page that makes the
summary feel like a real post-activity review rather than a receipt — and it is the reason
to make `trackEnabled` unconditional.

### What this needs, in order

1. `SummaryNav` + `SummaryDelegate` page cycling — ~40 lines, mirrors `PageNav`.
2. S1/S2/S3/S5 as HERO-shaped draws through the existing `heroRowY` — the drawing code is
   already there, it needs a slot table.
3. S4 and S6 are near-verbatim reuse of `drawTurnsPage` and `drawTimelinePage`.
4. `trackEnabled = true` unconditionally in `WingfoilApp._applySettings` (+1.2 KB) and the
   new track renderer for S7 — the only genuinely new drawing code.
5. An all-time best-2s in `Storage` for the S2 PB marker.
6. A `summaryPagesFitRoundDisplay` test in the same style as the other five.

---

## 11. Prioritized punch list

**Fix before the next on-water session**

1. **§1.1** Records page: drop the `cy + 12` bias and route both numbers through `fitFont`.
   The bottom record number is clipped 23 px on 454 and 30 px on 416 today. Add the missing
   `recordsPageFitsRoundDisplay` test.
2. **§9.1 / §9.2 / §9.4** SummaryView: 32 px row pitch against a 53 px font — rows overlap;
   30 % dead band; no hierarchy. Even before the multi-page rebuild, stacking from
   `getFontHeight` and promoting foil % to a hero number is a half-hour fix.
3. **§6.1** Green means both "on foil" and "flew through", on the same screen, on the
   Timeline and the map. Move the phase tint to teal `0x40C8E0` / grey `0x97979D` and add a
   `monkeyC` form to `design/tokens.json` so CI holds the line.

**Fix soon**

4. **§2.1 / §3.1** Make `fitRadius()` aware of the ring and the arc. One function, and every
   existing layout test inherits the fix. Today the hero giant overlaps the ring by 2.3 px on
   the 43 mm and a full-width grid cell reaches 5 px into the foil arc.
5. **§5.3** Delete `PbFlash.stop()` from `RecordingView.onHide` — it defeats the module's
   entire stated design.
6. **§5.1** PAUSED banner: stop punching a hole in the ring; compute its y from font heights.
7. **§5.5** Per-channel alert debounce; the turn-outcome vibe language is being eaten by PB
   buzzes.
8. **§5.2** Make the PAUSED state visible on (or refuse paging to) the map page.

**Worth doing**

9. **§4.1 / §4.2** Rebalance the Turns page — promote the score, stop the tally ladder at
   `FONT_SMALL`.
10. **§10** The multi-page summary. It is mostly reuse; the engine already survives the save.
11. **§7.2** A `dimInk()` helper so `COLOR_DK_GRAY` stops carrying information on MIP.
12. **§5.6** Put a number on each Timeline band caption.
13. **§8.1** StartView: the app's name should not be the biggest thing on it.
14. **§6.2** HR should not be ladder red.
15. **§9.6** Move the on-watch strings into `strings.xml` and add `resources-deu/`.
16. **§3.2 / §7.1** Scale `GRID_BIAS`, `CELL_DX_MAX` and the ring/bezel pens off the display,
    the way `Glyphs.size()` and `StartView.dotRadius()` already do.

---

## 12. What 0.9.2 changed

Two things: the rider's own polish list after a session on 0.9.1, and the end of the native
map. Every number below is measured on a 454 px `fenix847mm` unless it says otherwise; the
suite runs the same arithmetic on `fenix7s` (240 px) and asserts it there too.

### 12.1 The native map is gone — the breadcrumb is ours now

Three releases, three ways for the same page to kill the app:

| | what it did | what the watch did |
|---|---|---|
| 0.8.x–0.9.0 | `switchToView` onto `WatchUi.MapTrackView` | Type Error on device; fine in the simulator |
| 0.9.1 | `pushView`, the documented way for a native base view | fenix 8 killed the app on the page during a recording session, **with no CIQ_LOG entry at all** |
| 0.9.2 | draws the trail itself, inside `RecordingView.onUpdate` | — |

A crash a rider reproduces and a log cannot see is not a crash to keep chasing, and there was
never a second opinion available: `MapTrackView` is a *View*, so the layout suite could not
render it, could not measure it, and could not have caught any of this. The post-save Track
page has been drawing the same breadcrumb with `Dc` primitives since 0.8.2 and has never
crashed anything.

So `LAYOUT_MAP` is now an ordinary layout. The renderer both screens call is `TrackDraw`
(`garmin/source/ui/TrackDraw.mc`, which also inherited `TrackTint` from the deleted
`MapPageView.mc`): bounding box, longitudes squeezed by cos(lat), one aspect-preserving scale
into the square inscribed in the glass, one `setColor` per run of equal foil state. The live
page adds the two things a live trail owes the rider and a post-save one does not — a white
marker on the newest point, and the word **"waiting for GPS"** when there are fewer than two
points, because a map page that renders empty reads as a crashed map page. Under it sits the
odometer in `FONT_SMALL`: a map with no number on it is a shape.

What went with it is as much of the point:

- the whole push/pop state machine in `PageNav` — `mapShown`, `_pushMap`, `dropMap`,
  `onPauseToggled`, the two `dropMap()` calls in the save/discard path, and the pop in
  `WingfoilApp._applySettings`. `step()` is `wrap(index + dir)` and a repaint;
- the paused skip (§5.2, punch-list item 8). It existed because a native view can carry no
  PAUSED banner. This page carries it like every other, so the rider gets his map while
  paused — banner and all;
- `PageModel.hasMap()`. The page needed `WatchUi has :MapTrackView` and now needs nothing, so
  it ships on **every** product in the manifest, the fenix 7 family included;
- the hole in the test suite. `everyLayoutRendersHeadless` covers all ten layouts now, and
  `mapPageFitsRoundDisplay` measures the box corners, the caption and the waiting line.

### 12.2 All text is white

Grey text is retired everywhere — recording pages, start, summary, clock, lock screen. Labels,
captions, units, headers, separators and row keys are `COLOR_WHITE`; **size** alone now
separates a label from a value, which it was already doing most of the work of. The colour
vocabulary is untouched (§6): the ladder's green/orange/red, the phase teal, the effort orange,
the PAUSED yellow, the GPS row's green and amber. So is grey where it is **structure rather
than text** — `Ink.dim()` still draws the off-foil ring, the unfilled foil arc, the timeline
rails, the sparkline's best-2s reference, the giant tally's separator dots and the off-foil
half of both breadcrumbs.

### 12.3 The foil matrix, rearranged and a rung bigger

`min` became **`time`** (the cells print `m:ss`, never minutes), and the two column headers
moved from *above* the matrix to *below* it. The move is what pays for the size:

| | 0.9.1 | 0.9.2 |
|---|---|---|
| stack | title · headers · shares · totals · bests, lifted 28 px | title · shares · totals · bests · headers, centred |
| value-row depths | −62 / +9 / +80 | −71 / 0 / +71 |
| table half-width | 185 px | **190 px** |
| row keys | `total` / `max` (63 px) | `tot` / `max` (59 px, see below) |
| column width | 145 px | **152 px** |
| the six numbers | `FONT_MEDIUM` | **`FONT_LARGE`** |

With the headers at the bottom the three value rows are symmetric about the equator, which is
the widest three rows of that height can be; a two-word label row is the cheapest thing to put
where the chord has collapsed. `foilKeys` gained a second rule to go with it: the long word
`total` already gave way when it pushed the worst case below the floor, and now it also gives
way when it costs the matrix **a whole rung** against what `tot` would allow — five letters
were buying two characters of key at the price of every number on the page.

### 12.4 Leading is not layout: five stacks now reserve INK, not line height

Garmin font heights include leading. Where a row's font is *pinned* — a giant that starts at
the top of its own ladder — that leading is knowable dead space, and stacking against it pushes
every row below it deeper into the narrowing chord for nothing. Five stacks now reserve the
giant's ink height instead:

| page | band | freed | what it bought |
|---|---|---|---|
| MAIN | `NUMBER_MEDIUM` 153 → 114 | 39 px | the bigger clock, below |
| HERO (and every summary hero) | `THAI_HOT` 210 → 157 | 53 px | 56 px of chord for sub-row 2 |
| RECORDS | `NUMBER_HOT` 173 → 129 ×2 | 88 px | bottom number's chord 250 → 306 px |
| TURNS | `NUMBER_MEDIUM` 153 → 114 | 39 px | verdict row's chord 328 → 354 px |
| CLOCK | `THAI_HOT` 210 → 157 | 53 px | the bigger timer, below |

The label under a giant is stacked against the ink, i.e. exactly where the digits end. Nothing
moves the giant itself — a block centred on its total puts the giant at the same y either way.

### 12.5 The rest of the font pass

- **MAIN, the time of day** — band `FONT_LARGE` → `FONT_NUMBER_MILD`, fitted through the
  NUMBER ladder (~41 px of digit → ~66). PAUSED, which is a word and wider, still steps down
  into the text fonts and lands on `FONT_LARGE` exactly as before. Net cost to the stack after
  §12.4: **three pixels**.
- **CLOCK, the timer** — the cell is a `FONT_NUMBER_MILD` one now, fitted through the NUMBER
  ladder; all 21 catalogue metrics reach MILD in it at their worst-case strings. It is paid for
  by §12.4 plus a `CLOCK_BIAS` of 32 px — GRID4's lift in the other direction, because what
  this page needs is width at the *top*, where the giant is. The giant keeps THAI_HOT: its
  budget goes 364 → 378 px against the 363 px `"23:59"` needs, i.e. from one pixel of margin
  to fifteen.
- **CELLS2** — the same treatment, and the page that needed it most: two numbers and a label
  line filled 108 px of a 454 px glass, 24 % of it. Band `FONT_LARGE` → `FONT_NUMBER_MILD`,
  values through the NUMBER ladder, floor unchanged.
- **TURNS, the verdict row** — the values were pinned at `FONT_SMALL`, the floor, on a row that
  already reserved a `FONT_MEDIUM` band. They start at MEDIUM and step down now; the P/S half
  is still decided at the floor first, because this row sheds content before size.
- **TIMELINE** — `TL_STRIP_H` 44 → 56, `TL_SPARK_H` 96 → 124. The three bands and their
  captions filled 263 px of a 454 px glass; on the one page whose content is *shapes*, height
  is resolution — a 96 px sparkline resolves a speed run to about two thirds of a knot. The
  bands are pushed a little deeper into the arc for it, so they are ~5 % narrower (strip
  400 → 378 px, sparkline 409 → 390) and the dot row drops two dots (22 → 20). A quarter more
  height on both figures is worth two dots the Turns page also draws.
- **START** — the GPS state row gets the title's rung (§8.1: the answer to the screen's only
  question was smaller than the app's name). Paid for out of the row gaps, a third of a body
  line rather than a half; the wind reminder keeps `FONT_SMALL` on a 240 px glass, which is the
  row that measures closest to its chord anywhere in the app.

**Not enlarged, and why.** The GRID4 giant band stays a `NUMBER_MILD` *line* height — its slack
is not slack, it is where the pair band's caption lives, and cutting it to the ink would demote
that band from `FONT_LARGE` to `FONT_MEDIUM`. GRID4's cells stay `FONT_LARGE`: that is already
the top of the text ladder, and the page carries four of them plus a giant. The RECORDS numbers
stay on the `NUMBER_HOT` rung — `THAI_HOT` needs 280 px and the bottom row has 230 after the
band would have to grow to hold it. The TURNS giant tally still starts at `NUMBER_MEDIUM`:
starting it at `NUMBER_HOT` would make the page's headline number change size as the session
went on. And every XTINY label stayed XTINY — the standing rule is about values, not about
field descriptions.

---

*Measured against ConnectIQ SDK 9.2.0 on `fenix847mm` (454 px, 16 bpp AMOLED) and
`fenix843mm` (416 px, 16 bpp AMOLED). MIP variants (fenix 8 Solar 260/280 px, fenix 7 family
240/260/280 px) are 8 bpp and were reasoned about from their device profiles, not measured —
except `fenix7s` (240 px), which the layout suite has run on since 0.8.2 and still does.*
