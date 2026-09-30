> Part of `docs/presentation.md`. Engine 0.27.0.

## Scrub and zoom

- **One playhead.** The chart scrub position and the map dot are the same timestamp; moving
  either moves both. (iOS: `ReplayScrubber` shared state; web: the shared scrubber.)
- Chart zoom is a gesture on the time axis (iOS: pinch, because one-finger drag is the
  scrubber; web: wheel/pinch). While zoomed: scrubbing works within the window, a reset
  affordance is visible, the window's place in the session is indicated, and markers and
  shading outside the visible domain are not drawn.
- **Which finger is whose** (iOS, 25 Sep 2026; 28 Sep). On every chart and strip a tap
  places the playhead and a *sideways* drag scrubs; an up-or-down finger scrolls the page
  past it (`ScrubPan`, a UIKit recogniser that the scroll view and a sheet's dismiss wait
  for). It makes its call after 20 pt of travel and scrubs only a drag at least 1.5× as wide
  as tall (`DragClaim`, in the kit); anything else is the page's. The turn and flight-end
  sheets page between turns with the session page's pager (`SessionPager`,
  `SessionPaging.isHorizontal`), not a page-style `TabView`: a vertical scroll view inside a
  paging one lets go of any drag whose first points lean sideways, and a thumb's do, so the
  page stuck (Jan, 28 Sep 2026: "scrolling gets stuck … trying to scroll up again"). So the
  turn and flight-end pages scroll to their foot from anywhere, and a drag that starts on a
  strip is the strip's and never turns to the next turn. On the session page a drag that
  starts on the chart or the replay slider belongs to it and never turns the page
  (`pagerExclusionZone`, which the strips carry too).
- **On an inline map one finger is the page's, two are the map's** (iOS, 30 Sep 2026). On the
  Ride, Turns and Flights maps one finger scrolls the page — and, clearly sideways, turns it
  like anywhere else — while two fingers pan and pinch the map and only a two-finger drag keeps
  the pager out (`pageMap`); taps and marks are untouched, and the full-screen and replay maps
  still pan with one. The first three times per install that one finger which started on such
  a map scrolls the page (`DragClaim` says up-or-down), a capsule on the map says *Use two
  fingers to move the map* above the Maps logo until 1.5 s after the finger lifts
  (`MapFingerHint`, `Copy.twoFingerMap`): no fade under
  Reduce Motion, never under VoiceOver, never for a tap or a page turn, and it takes no
  touches. The lasting home of the fact is the help topic "Reading the map", whose sentence
  names the iPhone app because the site's maps keep one-finger panning.
- **A segment row takes taps, never a vertical drag** (iOS, 30 Sep 2026, Jan on dev 120:
  "scroll back up on turns section still does not work"). A finger that starts on a row of
  segments — the tab switcher, the Turns and Flights filters, every choice in Settings, the
  share and replay sheets — and goes up or down scrolls the page; a tap picks the segment. A
  native `UISegmentedControl` could not keep that promise: a scroll view never takes back a
  touch a `UIControl` has held past its content delay (≈ 150 ms), so a thumb that rested on
  the row before it moved held the page still. Every segmented choice in the app is therefore
  `SegmentRow` — the native look (capsule track, lighter thumb), plain SwiftUI buttons, and a
  segmented `Picker` as its accessibility representation, so VoiceOver reads it as the native
  control. No `.pickerStyle(.segmented)` in the app target; `MapScrollUITests` drags down from
  a resting thumb on each Turns filter row, on the selected segment and an unselected one.
- Zoom state is transient per session view — but it survives a section change, which is not
  a new session view (see "Sections" above). On iOS that means the window is owned by
  `SessionDetailView`, not by the chart.

## Pairing

A takeoff, the flight it started and the end that stopped it are three marks on one event.
Drawing that link *always* — a leader line, a shared number, a badge on every arrow — buys a
fact nobody asked for at the cost of the busiest layer on the map. So the pairing is
**tap-only: nothing about it renders until a mark or a flying segment is tapped**, and what
appears is one extra line on the popover (iOS: the track callout) that was going to open
anyway.

Every fact in it is read verbatim from the analysis document — the flight's own `startTs` /
`endTs` / `distM`, its flight end's `outcome`, its takeoff's `pumps`. Nothing is recomputed
here; the only arithmetic is `endTs - startTs`, which is the same licence
`PumpEpisodeRecord` takes for not encoding its own duration.

The four lines, exactly:

| tapped | line |
|---|---|
| takeoff (pumped or free) | `starts flight 12 · 1:23 · ended: touchdown` |
| failed attempt | `no flight · 3 strokes` |
| straight-line flight end | `ends flight 12 · started 41:07 · 7 pumps` |
| a flying segment of the track | `flight 12 of 55 · 1:23 · 272 m · ended: touchdown` |

`·` separates, times are `m:ss` (`h:mm:ss` past an hour) on the session clock, the flight
number is 1-based, and the outcome words are the flight-end ladder's own: **glided out ·
touchdown · fell in**, plus **recording ended** for an end the engine marked `unknown` or
`truncated` (a recording that stopped is not a verdict).

Absence, as everywhere else, is absence and never zero:

- no accelerometer stream ⇒ `pumps` is nil ⇒ the ` · N pumps` clause is **omitted**, not
  written as `0 pumps`;
- a flight with no distance ⇒ the ` · N m` clause is omitted;
- a mark whose flight cannot be resolved gets **no pairing line at all** rather than
  `flight ?`.

Tapping a flying segment does one more thing: it **focuses the chart on that flight** — the
timeline window is set to the flight's span plus a margin on each side (iOS:
`TimelineWindow.focus(on:)`, the same window the pinch moves; web: the strip's zoom window),
so the tap that asks "what was this stretch?" answers on both figures at once. The focus is
transient like every other zoom, and the reset affordance the zoom already has is the way
out of it.

