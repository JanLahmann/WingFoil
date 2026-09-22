> Part of `docs/presentation.md`. Engine 0.24.0.

## Sections — how a session divides

Both apps open on the key-metrics block and then **switch between four sections**, in this
order: **`Ride` · `Turns` · `Takeoffs` · `Details`**. The ids and the words are `SessionSection`
in the kit. The alternative was measured: one column of ~3 800 pt on the phone and ~6 000 px
on a phone browser, five unrelated subjects deep, with no way to the fifth except through
the other four (`app-ui-review.md` §3.1, §7.2).

| section | holds |
|---|---|
| **`ride`** *(default)* | the map, its legend, the speed chart, the replay scrubber, the foil tiles and the speed-records table — one instrument, one section |
| **`turns`** | the turn cards, then the two filters, the outcome tally, the maneuver map and the turn list |
| **`takeoffs`** | the failed-attempt headline and the takeoff & pumping tiles, then the attempt map and list, then the HR card ("What pumping cost") |
| **`log`** | the gear card, the wind detail, the recording's provenance, and the watch-vs-phone table |

**The four were re-cut on 6 Sep 2026** (Jan), from `Map · Speed | Turns | Takeoffs | Effort`.
Two rationales, and both are about a name describing the wrong thing:

- **Takeoffs and Effort were one subject split by sensor.** The takeoff tiles counted
  attempts off the accelerometer and the HR card priced those same attempts off the optical
  heart rate — "how many did I have to pump for" and "what did the pumping cost" are the same
  question asked twice, and the app was answering them on two tabs. The word gave it away:
  **"effort" was already the map legend's name for the GP3S record window**, so a section
  called Effort was competing for a word the map had spent. The HR card is under the takeoff
  content now and its heading dropped the redundant half (§ "The HR card's own title").
- **The session's own facts had nowhere to live.** The recording's provenance was a footer
  repeated under all four sections, the wind axis the whole analysis is named against was one
  grey line under the date, and the watch-vs-phone table was hidden inside a warning banner
  most riders dismiss. Three facts about the *record*, filed as page furniture. `Details` is
  where they are, with the gear card, which was already the same kind of fact. There are no
  placeholders on it for anything else.

`Ride` replaced `Map · Speed` in the same move: the middle dot was load-bearing while the
name was a list of two figures, and it is dead weight beside three one-word siblings. The
section is the ride — where it went and how fast — and the two figures on it are how it says
so.

**`Log` became `Details` on 19 September 2026** (pattern A: a title names what the screen
does). "Log" reads as a logbook, a list of afternoons, and the section is not a list of
anything: it is the four facts about *this* session — the kit, the wind, where the recording
came from, and where the watch and the phone disagree. No narrower word covers all four, and
`Details` is exactly as wide as the section. The case, the anchors and the `app-shell.json`
id stay `log`, so every deep link written before the rename still lands.

**Every scroll anchor that existed keeps working, and two changed section rather than name**:
`hr` is on `takeoffs`, `gear` is on `log`. A jump to an anchor — a deep link, a screenshot
hook (`UI_SCROLL_TO`), the divergence banner's tap — **must select the anchor's section
first and then scroll**, because a scroll into an unselected section's subtree reaches
nothing at all, silently. The rule is `SessionSection.tabChange(for:current:)`, and it
returns nil for an anchor already on screen and for `key`, which is above the switcher and
therefore on every section.

- **The key-metrics block is above the switcher and is never a section.** It is the answer
  to "was that a good session"; a page you can navigate away from is not an answer. There
  is therefore no `Overview`.
- **The map and the speed chart are on one section, always.** "Scrub and zoom" below
  mandates one playhead across them and "Pairing" focuses the chart on the flight whose
  track you tapped — they are one instrument with a *visible* link, and a switcher that
  gives Map its own page breaks the half of it you can see. Everything that annotates the
  two figures rides with them, which is why the record picker lives there too and why there
  is no `Records` section: a picker whose whole purpose is to highlight a window on the map
  and the chart cannot be on a tab away from them.
- **The chart's zoom window outlives a section change.** Zoom stays transient per *session
  view* (below), but a trip to Turns and back is not a new session view, and silently
  resetting the window would make "transient" mean something the rider did not ask for.
- **The web has the same four, at every width, since 19 September 2026.** Jan: *"iOS is the
  reference, the web is the port"*. The analyzer's `data-section` ids are `ride`, `turns`,
  `takeoffs`, `log` (`web/js/sections.js`), its chips carry these four words, and the
  switcher no longer hides above 760 px. The earlier rules — the desktop session view as a
  single scrolling document, and `mapSpeed` … `data` as the web's own ids — are retired with
  it; the review's §3.4 note was written while the analyzer was a lab tool, and it is a tab
  of an app now. `docs/copy/app-shell.json` carries the four for both surfaces and
  `web/tools/verify_app_shell.py` reads `SessionSection.swift` from the other end, so
  neither side can rename a tab alone.
- **A section the web cannot fill says so in one line.** Takeoffs has no HR card here and
  `Details` has no gear card and no divergence table, so each prints one sentence naming the
  phone. A tab that is quietly half of what its name promises is worse than one that admits
  the half it has.

### The HR card's own title

The card under the takeoff content is headed **"What pumping cost"**, not "Effort — what
pumping cost". The tab it used to sit on carried the first two words, and a card that repeats
its section's name in its own heading is decoration that says nothing (§ "Tables over tile
walls"). The section already says Takeoffs; the heading only has to say which half of the
takeoff question this half answers.

### The divergence banner is one line, and it links

The watch-vs-phone banner sits under the key-metrics block, as it did, and it is now a
**one-line warning with a chevron**: the four-column table it used to unfold in place is on
`Details`. Tapping the banner selects `Details` and scrolls to the table. The dismiss X is unchanged
and still per session and per divergence (`DivergenceDismissal`). A disclosure that put the
most technical thing on the page in the second most prominent place on it was the wrong
weight for a provenance footnote; a banner's job is to say there is something and to take you
to it.

## Tables over tile walls

Where a screen shows one number per row with the same shape on every row, it is a table:
`record | value | at` for the session's speed records, `record | value | +Δ PB | when ·
where` for the all-time ones. Eight 2-up cards spent ~520 pt and ~2 000 pt respectively to
show eight numbers each, and the values could not be compared by eye because they did not
line up in a column (`app-ui-review.md` §1.4, §6.2). A table also has no odd-count parity
problem, which is what left `Glide-outs 0` alone beside an empty cell.

Decoration that repeats the row's own text is not information: the record medallion
contained the same words as the title beside it, and a 90 px sparkline read as a flat line
with a bump on all eight rows. The *distinction* a decoration encodes may still be worth
keeping — record freshness survives as a 7 pt dot — but it is kept at the size the fact is
worth, not at the size the ornament was.

