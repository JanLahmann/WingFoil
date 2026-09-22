# Presentation contract — UI semantics all implementations follow

`algorithms.md` holds the parameters the three analysis implementations follow; this file
holds the *presentation* semantics the UIs follow. Two full implementations exist today —
the iOS app (SwiftUI) and the web app (inline SVG) — plus the watch's colour vocabulary,
and nothing but convention kept them aligned until this contract. The rule is the same as
for the engine: **semantics are defined once, here. An implementation that needs to deviate
changes this file first, in the same commit.**

Colour *values* live in `design/tokens.json`, which generates the Swift constants
(`DesignTokens`), `web/css/tokens.css`, `web/js/tokens.js` and `garmin/source/DesignTokens.mc`
and is staleness-checked in CI (`design/check_tokens.py --check`). A value is edited there and
nowhere else; this file defines the *meanings*.

**The watch (device app ≥ 0.8.0).** It consumes the `hex` half, like the web: `Dc.setColor`
takes a literal `0xRRGGBB` on every product in `garmin/manifest.xml`. Each token additionally
carries a generated `_MIP` twin — its nearest colour in the fixed 64-entry `{00,55,AA,FF}³`
palette that the 8 bpp products (both fenix 8 Solars, the whole fenix 7 family) quantise to.
The firmware does that snapping itself, so the twin changes no pixel; it exists so the
fallback is a reviewable value and so palette *collisions* are visible in the generated file
rather than on the water — on 8 bpp, `phase.flying`, `effort.takeoff` and `effort.splash` all
land on `0x55AAFF`, and `outcome.touchdown` and `effort.window` both on `0xFFAA00`. None of
those pairs is drawn on one watch screen. `garmin/source/ui/Ink.mc` picks the half per device
and is also where the one contrast concession lives: the "off" half of a two-state mark is
`COLOR_DK_GRAY` on AMOLED over true black, and the phase grey on a reflective MIP, where dark
grey over a mid-grey ground in sun is nothing at all.

Until 0.8.0 the watch reused `Graphics.COLOR_GREEN` for *both* the phase tint and the ladder's
"flew through", which broke on the Timeline page in particular — foil-fraction bars and turn
outcome dots, six rows apart on one screen, in one ink for two meanings. The phase tint is now
the teal, on the ring, the foil-% arc, the flight timer, the timeline bars, the breadcrumb and
the summary's track; green is the verdict and nothing else. Heart rate left the ladder's red
for the effort indigo (a pulse is not a swim), and the PB celebration left green for the
effort orange (a record is something the rider *did*, not a verdict).


This file is an index. Every label, tab, map and page lives in the topic files under
`docs/presentation/`; each one carries a one-line header naming this file and the engine
version it is stamped for.

## Topics

- [`presentation/clean-jibe.md`](presentation/clean-jibe.md) — clean jibe: the name of the
  strict verdict, and how it is spelled.
- [`presentation/layers-map-colour-type.md`](presentation/layers-map-colour-type.md) — Layers,
  map style, colour and glyph vocabulary, text size and theme.
- [`presentation/key-metrics.md`](presentation/key-metrics.md) — the block that opens the
  session.
- [`presentation/session-time-video.md`](presentation/session-time-video.md) — the clock a
  session is drawn on, and the reel it is drawn on.
- [`presentation/sections-tables.md`](presentation/sections-tables.md) — how a session
  divides, and tables over tile walls.
- [`presentation/records.md`](presentation/records.md) — record windows, and the all-time
  records pages.
- [`presentation/trends-periods.md`](presentation/trends-periods.md) — trend charts, trend
  weeks, periods, marker eligibility, filter semantics.
- [`presentation/turn-detail.md`](presentation/turn-detail.md) — turn detail and flight-end
  detail, at the scale of one maneuver.
- [`presentation/one-clock.md`](presentation/one-clock.md) — one clock: every duration a
  rider sees is the engine's cleaned span.
- [`presentation/labels.md`](presentation/labels.md) — the label table, the discipline
  lexicon, the formatter rules.
- [`presentation/scrub-pairing.md`](presentation/scrub-pairing.md) — scrub and zoom, and
  pairing.
- [`presentation/channels-tuning.md`](presentation/channels-tuning.md) — which screen a rider
  sees at all, and the tuning sliders in the dev build.
- [`presentation/watch.md`](presentation/watch.md) — the watch: layout rules, event flash,
  Turns and Tacks & jibes pages, page sets, show/hide switches, the after-save pages, the
  per-page editor, the direct transfer's progress, the watch's words, the watch link.
- [`presentation/not-a-session-spots.md`](presentation/not-a-session-spots.md) — not a
  session, and how a spot gets its name.
- [`presentation/privacy-first-screen.md`](presentation/privacy-first-screen.md) — what
  leaves the phone, and the first screen of a fresh install.
- [`presentation/gear-list-session-page.md`](presentation/gear-list-session-page.md) — gear
  & spots, the session list, and the session page.
- [`presentation/import.md`](presentation/import.md) — import: the doors a session comes in
  by.
- [`presentation/copy-menu-settings.md`](presentation/copy-menu-settings.md) — one copy many
  surfaces, the library menu, settings.
- [`presentation/status-feedback-start-widgets-ipad.md`](presentation/status-feedback-start-widgets-ipad.md)
  — the status line, feedback mail, the start screen, home-screen widgets, iPad and Mac.
- [`presentation/enforcement.md`](presentation/enforcement.md) — enforcement.
